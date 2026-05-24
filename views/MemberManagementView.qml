import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// ============================================================================
// MemberManagementView.qml — 成员管理看板（RBAC 数据可见性隔离）
//
// 入口限制：仅 role_id <= 30（老师/队长/部长）可访问，普通队员不可见
//
// 数据权限：
//   role 10（带队老师）→ 服务端返回全量数据
//   role 20（队长）    → 服务端返回全量数据
//   role 30（部长）    → 服务端返回本部门数据
//
// 请求注入 request_user_role + request_user_dept，由后端做权限裁剪
//
// 功能：
//   1. GET_MEMBERS 拉取成员列表（含 major / class_name 专业班级信息）
//   2. 【手动添加成员】弹窗 → 单条组装 BULK_REGISTER_USERS
//   3. 【导入 CSV 模板】→ FileDialog + XMLHttpRequest 本地解析 → 批量 BULK_REGISTER_USERS
//      CSV 格式：姓名,学号,密码,角色ID,部门ID,专业,班级
//   4. BULK_REGISTER_USERS 响应 → 自动 fetchMembers() 刷新列表
//
// 约束：全文件禁止 String.arg()，字符串拼接一律用原生 +
// ============================================================================

Item {
    id: root

    // ---- 角色中文映射 ----
    function roleName(rid) {
        switch (rid) {
            case 10: return "带队老师"
            case 20: return "队长"
            case 30: return "部长"
            case 40: return "普通队员"
            default: return "未知角色"
        }
    }

    // ---- 角色徽章颜色 ----
    function roleBadgeColor(rid) {
        switch (rid) {
            case 10: return "#C62828"
            case 20: return "#1565C0"
            case 30: return "#00897B"
            case 40: return "#757575"
            default: return "#9E9E9E"
        }
    }

    // ---- 运行时状态徽章 ----
    function stateLabel(st) {
        switch (st) {
            case "busy_activity": return "活动中"
            case "busy_course":   return "上课中"
            case "free":          return "空闲中"
            default:              return "空闲中"
        }
    }
    function stateBadgeColor(st) {
        switch (st) {
            case "busy_activity": return "#C62828"  // 红色：已有活动冲突
            case "busy_course":   return "#F9A825"  // 黄色：课程冲突
            case "free":          return "#2E7D32"  // 绿色：可指派
            default:              return "#9E9E9E"
        }
    }
    function stateEmoji(st) {
        switch (st) {
            case "busy_activity": return "🔥"
            case "busy_course":   return "📚"
            case "free":          return "🍀"
            default:              return "🍀"
        }
    }

    // ---- 数据模型：成员列表（展示用，经筛选排序后渲染） ----
    ListModel {
        id: memberModel
    }

    // ---- 全量成员原始缓存（前端筛选/排序的数据源） ----
    property var allMembersRaw: []

    // ---- 筛选 — 角色下拉模型 ----
    ListModel {
        id: filterRoleModel
        Component.onCompleted: {
            append({ text: "全部角色", rid: 0 })
            append({ text: "带队老师", rid: 10 })
            append({ text: "队长",     rid: 20 })
            append({ text: "部长",     rid: 30 })
            append({ text: "普通队员", rid: 40 })
        }
    }

    // ---- 排序 — 排序模式下拉模型 ----
    ListModel {
        id: filterSortModel
        Component.onCompleted: {
            append({ text: "默认 (ID 升序)",   mode: 0 })
            append({ text: "志愿时长: 高→低",  mode: 1 })
            append({ text: "志愿时长: 低→高",  mode: 2 })
            append({ text: "志愿次数: 高→低",  mode: 3 })
        }
    }

    // ---- 手动添加弹窗 — 角色下拉模型 ----
    ListModel {
        id: addRoleModel
        Component.onCompleted: {
            append({ text: "带队老师", rid: 10 })
            append({ text: "队长",     rid: 20 })
            append({ text: "部长",     rid: 30 })
            append({ text: "普通队员", rid: 40 })
        }
    }

    // ---- 手动添加弹窗 — 部门下拉模型 ----
    ListModel {
        id: addDeptModel
        Component.onCompleted: {
            append({ text: "策划部", did: 1 })
            append({ text: "外联部", did: 2 })
            append({ text: "办公室", did: 3 })
            append({ text: "宣传部", did: 4 })
            append({ text: "云教室", did: 5 })
        }
    }

    // ---- 身份标识文案 ----
    property string identityBannerText: {
        if (!mainWindow.isLoggedIn) return "未登录"
        var u = mainWindow.currentUser
        switch (u.role_id) {
            case 10: return "您当前拥有全量数据视角 — 可查看所有部门成员"
            case 20: return "您当前拥有全量数据视角 — 可查看所有部门成员"
            case 30: return "您当前属于局部部门视角，仅展现本部门（" + (u.department_id || "—") + "）数据"
            default: return ""
        }
    }

    property string identityBannerColor: {
        if (!mainWindow.isLoggedIn) return "#F5F5F5"
        switch (mainWindow.currentUser.role_id) {
            case 10:
            case 20: return "#E8F5E9"
            case 30: return "#FFF3E0"
            default: return "#F5F5F5"
        }
    }

    // ---- 批量除名模式 ----
    property bool batchDeleteMode: false
    property var batchSelectedIds: ({})
    function enterBatchDeleteMode() {
        batchDeleteMode = true
        batchSelectedIds = ({})
        applyFilterAndSort()
    }

    function exitBatchDeleteMode() {
        batchDeleteMode = false
        batchSelectedIds = ({})
        applyFilterAndSort()
    }

    function isMemberSelected(userId) {
        return batchSelectedIds.hasOwnProperty(String(userId))
    }

    function toggleMemberSelection(userId) {
        var key = String(userId)
        if (batchSelectedIds.hasOwnProperty(key)) {
            delete batchSelectedIds[key]
        } else {
            batchSelectedIds[key] = true
        }
        // 同步更新 memberModel 中的 selected 字段（驱动 CheckBox binding）
        syncModelSelection(key)
        // 触发 count 文本绑定刷新
        batchSelectedIds = Object.assign({}, batchSelectedIds)
    }

    function syncModelSelection(userIdKey) {
        var selected = isMemberSelected(parseInt(userIdKey))
        for (var i = 0; i < memberModel.count; i++) {
            if (String(memberModel.get(i).user_id) === userIdKey) {
                memberModel.setProperty(i, "selected", selected)
                break
            }
        }
    }

    function selectAllVisible() {
        for (var i = 0; i < memberModel.count; i++) {
            var uid = memberModel.get(i).user_id
            batchSelectedIds[String(uid)] = true
            memberModel.setProperty(i, "selected", true)
        }
        batchSelectedIds = Object.assign({}, batchSelectedIds)
    }

    function deselectAll() {
        for (var i = 0; i < memberModel.count; i++) {
            memberModel.setProperty(i, "selected", false)
        }
        batchSelectedIds = ({})
    }

    function executeBatchDelete() {
        var ids = Object.keys(batchSelectedIds)
        if (ids.length === 0) return

        var targetIds = ids.map(Number)

        batchDeleteConfirmBtn.enabled = false
        batchDeleteConfirmBtn.text = "批量处理中…"
        batchDeleteStatusText.text = "正在批量除名 " + targetIds.length + " 名成员..."

        NetworkClient.sendRequest("BATCH_DELETE_MEMBERS", {
            "target_user_ids": targetIds
        })
    }

    // ================================================================
    // 页面初始化
    // ================================================================
    Component.onCompleted: {
        fetchMembers()
    }

    function fetchMembers() {
        if (!NetworkClient.connected) {
            statusText.text = "未连接服务器，无法加载成员数据"
            statusText.color = "#C62828"
            return
        }
        if (!mainWindow.isLoggedIn) {
            statusText.text = "未登录，无法拉取成员数据"
            statusText.color = "#C62828"
            return
        }

        statusText.text = "加载中…"
        statusText.color = "#F57C00"

        NetworkClient.sendRequest("GET_MEMBERS", {
            "request_user_role": mainWindow.currentUser.role_id,
            "request_user_dept": mainWindow.currentUser.department_id
        })
    }

    // ================================================================
    // CSV 文件解析 + 批量导入引擎
    // 标准模板格式：姓名,学号,密码,角色ID,部门ID,专业,班级
    // ================================================================

    function parseCsvAndImport(fileUrl) {
        // URL → 本地路径归一化：FileDialog 返回的 selectedFile 是 QUrl，
        // Windows 上格式为 "file:///C:/path"，Linux 上为 "file:///home/path"。
        // 通过 toString() 规范化后裁剪前缀，避免 C++ 侧路径解析歧义。
        var path = fileUrl.toString()
        if (path.startsWith("file:///")) {
            path = path.substring(8)  // Windows: file:///C:/...
        } else if (path.startsWith("file://")) {
            path = path.substring(7)  // Linux:   file:///home/...
        }

        // 通过 C++ QStringDecoder 以 GBK/UTF-8 自适应解码读取本地 CSV
        // 解决 QML XMLHttpRequest 无法处理 Windows GBK 编码的问题
        var content = NetworkClient.readLocalFileGbk(path)

        if (!content || content.length === 0) {
            statusText.text = "CSV 文件读取失败或内容为空"
            statusText.color = "#C62828"
            return
        }

        // 去除 BOM 头（UTF-8 文件可能携带）
        if (content.charCodeAt(0) === 0xFEFF) {
            content = content.slice(1)
        }

        // 统一将 \r\n 和 \r 归一化为 \n，然后按 \n 拆分
        var normalized = content.replace(/\r\n/g, "\n").replace(/\r/g, "\n")
        var lines = normalized.split("\n")
        var users = []
        var skippedHeader = false

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line === "") continue

            var fields = line.split(",")
            if (fields.length < 7) continue

            // 跳过表头行（首列为"姓名"或"name"）
            if (!skippedHeader && i === 0) {
                var firstCol = fields[0].trim()
                if (firstCol === "姓名" || firstCol === "name" || firstCol === "Name") {
                    skippedHeader = true
                    continue
                }
            }

            // 每个字段独立 trim，并显式剔除 \r 残留（防止 Windows 记事本
            // 在 UTF-8 文件行尾嵌入 0x0D 污染最后一个字段值）
            var user = {
                "name":          fields[0].trim().replace(/\r/g, ""),
                "student_id":    fields[1].trim().replace(/\r/g, ""),
                "password":      fields[2].trim().replace(/\r/g, ""),
                "role_id":       parseInt(fields[3].trim()) || 40,
                "department_id": parseInt(fields[4].trim()) || 1,
                "major":         fields[5].trim().replace(/\r/g, ""),
                "class_name":    fields[6].trim().replace(/\r/g, "")
            }
            users.push(user)
        }

        if (users.length === 0) {
            statusText.text = "CSV 解析结果为空 — 请检查文件格式（姓名,学号,密码,角色ID,部门ID,专业,班级）"
            statusText.color = "#C62828"
            return
        }

        statusText.text = "正在导入 " + users.length + " 名成员…"
        statusText.color = "#F57C00"

        NetworkClient.sendRequest("BULK_REGISTER_USERS", { "users": users })
    }

    // ================================================================
    // 前端筛选 & 排序引擎
    //   从 allMembersRaw 缓存读取 → 按角色/搜索词过滤 → 按时长/次数排序
    //   → 灌入 memberModel 渲染。所有控件 onChange 自动触发。
    // ================================================================

    function applyFilterAndSort() {
        var searchText = filterSearchField.text.trim().toLowerCase()
        var filterRoleId = 0
        var roleItem = filterRoleModel.get(filterRoleCombo.currentIndex)
        if (roleItem) filterRoleId = roleItem.rid || 0

        var sortMode = 0
        var sortItem = filterSortModel.get(filterSortCombo.currentIndex)
        if (sortItem) sortMode = sortItem.mode || 0

        // ---- 1. 从原始缓存筛选 ----
        var filtered = []
        for (var i = 0; i < allMembersRaw.length; i++) {
            var m = allMembersRaw[i]

            // 角色过滤
            if (filterRoleId !== 0 && m.role_id !== filterRoleId) continue

            // 模糊搜索（姓名 或 学号）
            if (searchText !== "") {
                var nameHit = (m.name || "").toLowerCase().indexOf(searchText) !== -1
                var sidHit  = (m.student_id || "").toLowerCase().indexOf(searchText) !== -1
                if (!nameHit && !sidHit) continue
            }

            filtered.push(m)
        }

        // ---- 2. 排序 ----
        switch (sortMode) {
            case 1: // 志愿时长: 高→低
                filtered.sort(function(a, b) { return (b.total_hours || 0) - (a.total_hours || 0) })
                break
            case 2: // 志愿时长: 低→高
                filtered.sort(function(a, b) { return (a.total_hours || 0) - (b.total_hours || 0) })
                break
            case 3: // 志愿次数: 高→低
                filtered.sort(function(a, b) { return (b.total_count || 0) - (a.total_count || 0) })
                break
            default: // 默认: ID 升序
                filtered.sort(function(a, b) { return (a.user_id || 0) - (b.user_id || 0) })
                break
        }

        // ---- 3. 灌入展示模型 ----
        memberModel.clear()
        for (var j = 0; j < filtered.length; j++) {
            var m = filtered[j]
            memberModel.append({
                user_id:     m.user_id || m.id || 0,
                name:        m.name || "",
                student_id:  m.student_id || "",
                class_name:  m.class_name || "",
                dept_name:   m.dept_name || "",
                role_id:     m.role_id || 0,
                status:      (m.status === "active" || m.status === 1) ? "active" : "disabled",
                total_count: m.total_count || 0,
                total_hours: m.total_hours || 0,
                current_state: m.current_state || "free",
                selected:    batchDeleteMode ? isMemberSelected(m.user_id || m.id || 0) : false
            })
        }

        // ---- 4. 状态反馈 ----
        var dirty = (allMembersRaw.length !== filtered.length)
        statusText.text = "共 " + filtered.length + " 名成员" + (dirty ? " (已筛选)" : "")
        statusText.color = dirty ? "#1565C0" : "#555555"
    }

    // ================================================================
    // 主布局
    // ================================================================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // ---- 标题行 ----
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "👥 成员管理"
                font.pixelSize: 20
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            // ---- 手动添加成员 ----
            Button {
                text: "➕ 手动添加成员"
                enabled: NetworkClient.connected && mainWindow.isLoggedIn
                visible: mainWindow.isLoggedIn && mainWindow.currentUser.role_id <= 30
                onClicked: {
                    addNameField.text = ""
                    addStudentIdField.text = ""
                    addPasswordField.text = ""
                    addMajorField.text = ""
                    addClassNameField.text = ""
                    addRoleCombo.currentIndex = 3
                    addDeptCombo.currentIndex = 0
                    addMemberErrorText.text = ""
                    addMemberDialog.open()
                }

                background: Rectangle {
                    color: parent.enabled ? "#1565C0" : "#BDBDBD"
                    radius: 4
                }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font.pixelSize: 11
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // ---- 导入 CSV ----
            Button {
                text: "📊 导入 CSV 模板"
                enabled: NetworkClient.connected && mainWindow.isLoggedIn
                visible: mainWindow.isLoggedIn && mainWindow.currentUser.role_id <= 30
                onClicked: csvFileDialog.open()

                background: Rectangle {
                    color: parent.enabled ? "#00897B" : "#BDBDBD"
                    radius: 4
                }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font.pixelSize: 11
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // ---- 刷新成员 ----
            Button {
                text: "刷新成员"
                enabled: NetworkClient.connected && mainWindow.isLoggedIn
                onClicked: fetchMembers()

                background: Rectangle {
                    color: parent.enabled ? "#00897B" : "#BDBDBD"
                    radius: 4
                }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font.pixelSize: 11
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // ---- 批量除名模式切换 ----
            Button {
                text: batchDeleteMode ? "退出批量除名" : "🗑 批量除名"
                enabled: NetworkClient.connected && mainWindow.isLoggedIn
                visible: mainWindow.isLoggedIn && mainWindow.currentUser.role_id <= 20

                onClicked: {
                    if (batchDeleteMode) {
                        exitBatchDeleteMode()
                    } else {
                        enterBatchDeleteMode()
                    }
                }

                background: Rectangle {
                    color: batchDeleteMode ? "#E65100" : (parent.enabled ? "#C62828" : "#BDBDBD")
                    radius: 4
                }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font.pixelSize: 11
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        // ---- 身份通知条 ----
        Rectangle {
            Layout.fillWidth: true
            height: 36
            radius: 4
            color: identityBannerColor

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 12
                spacing: 8

                Text {
                    text: {
                        if (!mainWindow.isLoggedIn) return "⚠"
                        switch (mainWindow.currentUser.role_id) {
                            case 10: return "🔴"
                            case 20: return "🔵"
                            case 30: return "🟠"
                            default: return ""
                        }
                    }
                    font.pixelSize: 13
                }

                Text {
                    text: identityBannerText
                    font.pixelSize: 12
                    font.bold: true
                    color: {
                        switch (identityBannerColor) {
                            case "#E8F5E9": return "#2E7D32"
                            case "#FFF3E0": return "#E65100"
                            default: return "#666666"
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "共 " + memberModel.count + " 人"
                    font.pixelSize: 12
                    color: "#888888"
                    visible: memberModel.count > 0
                }
            }
        }

        // ---- 筛选 & 排序控制栏 ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            TextField {
                id: filterSearchField
                Layout.fillWidth: true
                Layout.preferredWidth: 180
                placeholderText: "搜索姓名或学号…"
                font.pixelSize: 12

                background: Rectangle {
                    radius: 4
                    border { color: "#BDBDBD"; width: 1 }
                    color: "#FFFFFF"
                }

                onTextChanged: applyFilterAndSort()
            }

            Text {
                text: "角色:"
                font.pixelSize: 12
                color: "#555555"
            }

            ComboBox {
                id: filterRoleCombo
                Layout.preferredWidth: 100
                textRole: "text"
                model: filterRoleModel
                currentIndex: 0
                font.pixelSize: 12

                onCurrentIndexChanged: applyFilterAndSort()
            }

            Text {
                text: "排序:"
                font.pixelSize: 12
                color: "#555555"
            }

            ComboBox {
                id: filterSortCombo
                Layout.preferredWidth: 150
                textRole: "text"
                model: filterSortModel
                currentIndex: 0
                font.pixelSize: 12

                onCurrentIndexChanged: applyFilterAndSort()
            }
        }

        // ---- 批量除名操作栏（批量模式下显示） ----
        Rectangle {
            Layout.fillWidth: true
            height: 36
            radius: 4
            color: "#FFEBEE"
            border { color: "#EF9A9A"; width: 1 }
            visible: batchDeleteMode

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 12
                spacing: 10

                // 全选 / 取消全选
                Text {
                    text: "全选"
                    font.pixelSize: 12
                    font.underline: true
                    color: "#1565C0"

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: selectAllVisible()
                    }
                }

                Text { text: "|"; color: "#E0E0E0"; font.pixelSize: 12 }

                Text {
                    text: "取消全选"
                    font.pixelSize: 12
                    font.underline: true
                    color: "#1565C0"

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: deselectAll()
                    }
                }

                Item { Layout.fillWidth: true }

                // 已选计数
                Text {
                    text: "已选 " + Object.keys(batchSelectedIds).length + " 人"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#C62828"
                }

                // 执行批量除名
                Button {
                    text: "批量除名(" + Object.keys(batchSelectedIds).length + ")"
                    enabled: Object.keys(batchSelectedIds).length > 0

                    onClicked: batchDeleteConfirmDialog.open()

                    background: Rectangle {
                        color: parent.enabled ? "#C62828" : "#BDBDBD"
                        radius: 4
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "white"
                        font.pixelSize: 11
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        // ---- 状态文字 ----
        Text {
            id: statusText
            text: "就绪"
            font.pixelSize: 12
            color: "#666666"
        }

        // ---- 列表头 ----
        Rectangle {
            Layout.fillWidth: true
            height: 32
            color: "#E3F2FD"
            radius: 4

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 12
                spacing: 0

                // 批量模式下列表头复选框列
                Item {
                    Layout.preferredWidth: 36
                    visible: batchDeleteMode
                }

                Text { text: "用户ID";   font.bold: true; Layout.preferredWidth: 60 }
                Text { text: "姓名";     font.bold: true; Layout.preferredWidth: 80 }
                Text { text: "学号";     font.bold: true; Layout.preferredWidth: 120 }
                Text { text: "专业班级"; font.bold: true; Layout.preferredWidth: 130 }
                Text { text: "所属部门"; font.bold: true; Layout.preferredWidth: 100 }
                Text { text: "运行时";   font.bold: true; Layout.preferredWidth: 72 }
                Text { text: "系统角色"; font.bold: true; Layout.preferredWidth: 100 }
                Text { text: "状态";     font.bold: true; Layout.preferredWidth: 70 }
                Text { text: "志愿次数"; font.bold: true; Layout.preferredWidth: 70 }
                Text { text: "志愿时长"; font.bold: true; Layout.preferredWidth: 80 }
                Item { Layout.fillWidth: true }
            }
        }

        // ---- 成员列表 ----
        ListView {
            id: memberList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: memberModel
            spacing: 2

            Label {
                anchors.centerIn: parent
                text: memberModel.count === 0
                      ? "暂无成员数据 — 请点击右上角「刷新成员」加载"
                      : ""
                color: "#999999"
                font.pixelSize: 13
            }

            delegate: Rectangle {
                width: memberList.width
                height: 44
                color: index % 2 === 0 ? "#FAFAFA" : "#FFFFFF"
                border { color: "#E0E0E0"; width: 0.5 }
                radius: 4

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    spacing: 0

                    // 批量模式：勾选复选框（绑定 model.selected，避免外部对象引用闪烁）
                    CheckBox {
                        Layout.preferredWidth: 36
                        visible: batchDeleteMode
                        checked: model.selected || false
                        onCheckedChanged: {
                            toggleMemberSelection(model.user_id)
                        }
                    }

                    Text {
                        text: model.user_id || "-"
                        Layout.preferredWidth: 60
                        font.pixelSize: 12
                        font.family: "Courier New"
                        color: "#888888"
                    }

                    Text {
                        text: model.name || "-"
                        Layout.preferredWidth: 80
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        text: model.student_id || "-"
                        Layout.preferredWidth: 120
                        font.pixelSize: 13
                        font.family: "Courier New"
                        color: "#555555"
                    }

                    Text {
                        text: model.class_name || "-"
                        Layout.preferredWidth: 130
                        font.pixelSize: 13
                        color: "#333333"
                        elide: Text.ElideRight
                    }

                    Text {
                        text: model.dept_name || "-"
                        Layout.preferredWidth: 100
                        font.pixelSize: 13
                        color: "#333333"
                    }

                    // 运行时状态徽章
                    Rectangle {
                        Layout.preferredWidth: 72; height: 24
                        radius: 12
                        color: stateBadgeColor(model.current_state)

                        Text {
                            anchors.centerIn: parent
                            text: stateEmoji(model.current_state) + " " + stateLabel(model.current_state)
                            color: "white"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 84; height: 24
                        radius: 12
                        color: roleBadgeColor(model.role_id)

                        Text {
                            anchors.centerIn: parent
                            text: roleName(model.role_id)
                            color: "white"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 60; height: 24
                        radius: 12
                        color: model.status === "active" ? "#E8F5E9" : "#FFEBEE"

                        Text {
                            anchors.centerIn: parent
                            text: model.status === "active" ? "✓ 正常" : "✗ 禁用"
                            font.pixelSize: 11
                            color: model.status === "active" ? "#2E7D32" : "#C62828"
                        }
                    }

                    Text {
                        text: model.total_count || 0
                        Layout.preferredWidth: 70
                        font.pixelSize: 13
                        font.bold: true
                        color: (model.total_count || 0) > 0 ? "#1565C0" : "#9E9E9E"
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        text: (model.total_hours || 0) + " h"
                        Layout.preferredWidth: 80
                        font.pixelSize: 13
                        font.bold: true
                        color: (model.total_hours || 0) > 0 ? "#2E7D32" : "#9E9E9E"
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // 🗑 除名按钮（批量模式下隐藏）
                    Button {
                        text: "🗑 除名"
                        Layout.preferredWidth: 72
                        visible: !batchDeleteMode && mainWindow.isLoggedIn && mainWindow.currentUser.role_id <= 20

                        onClicked: {
                            deleteMemberTargetId = model.user_id || model.id || 0
                            deleteMemberTargetName = model.name || ""
                            deleteMemberDialog.open()
                        }

                        background: Rectangle {
                            color: "#C62828"
                            radius: 4
                        }
                        contentItem: Text {
                            text: parent.text
                            color: "white"
                            font.pixelSize: 11
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }

    // ---- 除名操作临时变量 ----
    property int    deleteMemberTargetId:   -1
    property string deleteMemberTargetName: ""

    // ====================================================================
    // 📂 CSV 文件选择对话框
    // ====================================================================
    FileDialog {
        id: csvFileDialog
        title: "选择 CSV 成员导入模板"
        nameFilters: ["CSV 文件 (*.csv)"]
        fileMode: FileDialog.OpenFile
        onAccepted: {
            parseCsvAndImport(selectedFile)
        }
    }

    // ====================================================================
    // ✏️ 手动添加成员弹窗（含专业/班级字段）
    // ====================================================================
    Dialog {
        id: addMemberDialog
        title: "手动添加成员"
        modal: true
        width: 420
        height: 500
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            // 姓名
            RowLayout {
                spacing: 8
                Text {
                    text: "姓名："
                    font.pixelSize: 13
                    Layout.preferredWidth: 60
                }
                TextField {
                    id: addNameField
                    Layout.fillWidth: true
                    font.pixelSize: 13
                    placeholderText: "真实姓名"
                }
            }

            // 学号
            RowLayout {
                spacing: 8
                Text {
                    text: "学号："
                    font.pixelSize: 13
                    Layout.preferredWidth: 60
                }
                TextField {
                    id: addStudentIdField
                    Layout.fillWidth: true
                    font.pixelSize: 13
                    placeholderText: "2026001"
                }
            }

            // 密码
            RowLayout {
                spacing: 8
                Text {
                    text: "密码："
                    font.pixelSize: 13
                    Layout.preferredWidth: 60
                }
                TextField {
                    id: addPasswordField
                    Layout.fillWidth: true
                    font.pixelSize: 13
                    echoMode: TextInput.Password
                    placeholderText: "初始登录密码"
                }
            }

            // 专业
            RowLayout {
                spacing: 8
                Text {
                    text: "专业："
                    font.pixelSize: 13
                    Layout.preferredWidth: 60
                }
                TextField {
                    id: addMajorField
                    Layout.fillWidth: true
                    font.pixelSize: 13
                    placeholderText: "如：计算机科学与技术"
                }
            }

            // 班级
            RowLayout {
                spacing: 8
                Text {
                    text: "班级："
                    font.pixelSize: 13
                    Layout.preferredWidth: 60
                }
                TextField {
                    id: addClassNameField
                    Layout.fillWidth: true
                    font.pixelSize: 13
                    placeholderText: "如：2026级1班"
                }
            }

            // 角色
            RowLayout {
                spacing: 8
                Text {
                    text: "角色："
                    font.pixelSize: 13
                    Layout.preferredWidth: 60
                }
                ComboBox {
                    id: addRoleCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    model: addRoleModel
                    currentIndex: 3
                }
            }

            // 部门
            RowLayout {
                spacing: 8
                Text {
                    text: "部门："
                    font.pixelSize: 13
                    Layout.preferredWidth: 60
                }
                ComboBox {
                    id: addDeptCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    model: addDeptModel
                    currentIndex: 0
                }
            }

            // 错误提示
            Text {
                id: addMemberErrorText
                font.pixelSize: 12
                color: "#C62828"
                visible: text !== ""
            }

            // 提交按钮
            Button {
                id: addMemberSubmitBtn
                text: "确认添加"
                Layout.fillWidth: true
                Layout.preferredHeight: 40

                onClicked: {
                    var name = addNameField.text.trim()
                    var sid  = addStudentIdField.text.trim()
                    var pwd  = addPasswordField.text.trim()

                    if (name === "" || sid === "" || pwd === "") {
                        addMemberErrorText.text = "姓名、学号和密码均不能为空"
                        return
                    }

                    var roleItem = addRoleModel.get(addRoleCombo.currentIndex)
                    var deptItem = addDeptModel.get(addDeptCombo.currentIndex)

                    addMemberSubmitBtn.enabled = false
                    addMemberSubmitBtn.text = "提交中…"
                    addMemberErrorText.text = ""

                    NetworkClient.sendRequest("BULK_REGISTER_USERS", {
                        "users": [{
                            "name":          name,
                            "student_id":    sid,
                            "password":      pwd,
                            "role_id":       roleItem.rid,
                            "department_id": deptItem.did,
                            "major":         addMajorField.text.trim(),
                            "class_name":    addClassNameField.text.trim()
                        }]
                    })
                }

                background: Rectangle {
                    color: addMemberSubmitBtn.enabled ? "#1565C0" : "#BDBDBD"
                    radius: 4
                }
                contentItem: Text {
                    text: addMemberSubmitBtn.text
                    color: "white"
                    font.pixelSize: 13
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    // ====================================================================
    // ✅ CSV 批量导入成功弹窗
    // ====================================================================
    Dialog {
        id: csvSuccessDialog
        title: "导入成功"
        modal: true
        width: 360
        height: 180
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        ColumnLayout {
            anchors.fill: parent
            spacing: 16

            Text {
                id: csvSuccessText
                text: ""
                font.pixelSize: 14
                color: "#2E7D32"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }

            Item { Layout.fillHeight: true }

            Button {
                text: "确定"
                Layout.alignment: Qt.AlignHCenter
                onClicked: csvSuccessDialog.close()

                background: Rectangle {
                    color: "#1565C0"
                    radius: 4
                }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font.pixelSize: 13
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    // ====================================================================
    // 🗑 除名确认弹窗
    // ====================================================================
    Dialog {
        id: deleteMemberDialog
        title: "确认除名"
        modal: true
        width: 420
        height: 220
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        ColumnLayout {
            anchors.fill: parent
            spacing: 16

            Text {
                text: "确定要将「" + deleteMemberTargetName + "」彻底除名吗？"
                font.pixelSize: 14
                color: "#333333"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Text {
                text: "此操作将同步清除其排班与活动记录，不可撤销。"
                font.pixelSize: 12
                color: "#C62828"
                font.bold: true
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                Button {
                    text: "取消"
                    onClicked: deleteMemberDialog.close()

                    background: Rectangle {
                        color: "#E0E0E0"
                        radius: 4
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "#333333"
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Button {
                    id: deleteMemberConfirmBtn
                    text: "确定除名"

                    onClicked: {
                        deleteMemberConfirmBtn.enabled = false
                        deleteMemberConfirmBtn.text = "处理中…"

                        NetworkClient.sendRequest("DELETE_MEMBER", {
                            "target_user_id": deleteMemberTargetId
                        })
                    }

                    background: Rectangle {
                        color: deleteMemberConfirmBtn.enabled ? "#C62828" : "#BDBDBD"
                        radius: 4
                    }
                    contentItem: Text {
                        text: deleteMemberConfirmBtn.text
                        color: "white"
                        font.pixelSize: 13
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    // ====================================================================
    // 🗑 批量除名确认弹窗
    // ====================================================================
    Dialog {
        id: batchDeleteConfirmDialog
        title: "批量除名确认"
        modal: true
        width: 460
        height: 260
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        ColumnLayout {
            anchors.fill: parent
            spacing: 16

            Text {
                text: "确定要批量除名 " + Object.keys(batchSelectedIds).length + " 名成员吗？"
                font.pixelSize: 14
                color: "#333333"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Text {
                text: "此操作将同步清除选中成员的排班与活动记录，不可撤销。\n建议操作前先确认筛选列表无误。"
                font.pixelSize: 12
                color: "#C62828"
                font.bold: true
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Text {
                id: batchDeleteStatusText
                font.pixelSize: 12
                color: "#F57C00"
                visible: text !== ""
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                Button {
                    text: "取消"
                    onClicked: batchDeleteConfirmDialog.close()

                    background: Rectangle {
                        color: "#E0E0E0"
                        radius: 4
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "#333333"
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Button {
                    id: batchDeleteConfirmBtn
                    text: "确定除名"

                    onClicked: executeBatchDelete()

                    background: Rectangle {
                        color: batchDeleteConfirmBtn.enabled ? "#C62828" : "#BDBDBD"
                        radius: 4
                    }
                    contentItem: Text {
                        text: batchDeleteConfirmBtn.text
                        color: "white"
                        font.pixelSize: 13
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    // ====================================================================
    // 全局响应监听
    // ====================================================================
    Connections {
        target: NetworkClient

        function onResponseReceived(action, data) {
            // ---- 链路 A：GET_MEMBERS 响应 ----
            var isMembersResp = (action === "GET_MEMBERS")
                             || (data.action === "GET_MEMBERS")

            if (isMembersResp) {
                if (data.status === "ok" && data.data && data.data.members) {
                    var members = data.data.members

                    if (!Array.isArray(members)) {
                        console.warn("GET_MEMBERS: members is not an array")
                        return
                    }

                    // 缓存全量原始数据，交由 applyFilterAndSort() 筛选排序渲染
                    allMembersRaw = members
                    applyFilterAndSort()

                    console.log("GET_MEMBERS: " + members.length + " 条记录")
                } else {
                    statusText.text  = "加载失败: " + (data.message || "未知错误")
                    statusText.color = "#C62828"
                }
                return
            }

            // ---- 链路 B：BULK_REGISTER_USERS 响应 ----
            var isBulkResp = (action === "BULK_REGISTER_USERS")
                          || (data.action === "BULK_REGISTER_USERS")

            if (isBulkResp) {
                addMemberSubmitBtn.enabled = true
                addMemberSubmitBtn.text = "确认添加"

                if (data.status === "ok" || data.code === 0) {
                    var registeredCount = 0
                    if (data.data) {
                        registeredCount = data.data.count
                                       || data.data.registered_count
                                       || data.data.affected_rows
                                       || 0
                    }

                    addMemberDialog.close()

                    statusText.text  = "批量注册成功！已导入 " + registeredCount + " 名成员"
                    statusText.color = "#2E7D32"
                    console.log("BULK_REGISTER_USERS 成功: " + registeredCount + " 人")

                    // 弹窗提示导入总件数
                    csvSuccessText.text = "成功导入 " + registeredCount + " 名成员！\n数据已同步至服务器。"
                    csvSuccessDialog.open()

                    fetchMembers()
                } else {
                    var errMsg = data.message || "未知错误"
                    addMemberErrorText.text = "添加失败: " + errMsg
                    statusText.text  = "批量注册失败: " + errMsg
                    statusText.color = "#C62828"
                    console.log("BULK_REGISTER_USERS 失败: " + errMsg)
                }
                return
            }

            // ---- 链路 C：LOGIN 成功 → 自动拉取成员列表 ----
            var isLoginResp = (action === "LOGIN" || data.action === "LOGIN")
            if (isLoginResp && (data.status === "ok" || data.code === 0) && data.data) {
                statusText.text = "加载中…"
                statusText.color = "#F57C00"
                NetworkClient.sendRequest("GET_MEMBERS", {
                    "request_user_role": data.data.role_id,
                    "request_user_dept": data.data.department_id
                })
                return
            }

            // ---- 链路 D：BATCH_DELETE_MEMBERS 批量除名响应 ----
            var isBatchDeleteResp = (action === "BATCH_DELETE_MEMBERS")
                                 || (data.action === "BATCH_DELETE_MEMBERS")

            if (isBatchDeleteResp) {
                batchDeleteConfirmBtn.enabled = true
                batchDeleteConfirmBtn.text = "确定除名"

                if (data.status === "ok" || data.code === 0) {
                    batchDeleteConfirmDialog.close()
                    exitBatchDeleteMode()
                    var deletedCount = data.deleted_count || data.data.deleted_count || 0
                    statusText.text  = "批量除名完成！成功移除 " + deletedCount + " 人"
                    statusText.color = "#2E7D32"
                    console.log("BATCH_DELETE_MEMBERS 成功: " + deletedCount + " 人")
                    fetchMembers()
                } else {
                    batchDeleteStatusText.text = "批量除名失败: " + (data.message || "未知错误")
                }
                return
            }

            // ---- 链路 E：DELETE_MEMBER 单条除名响应 ----
            var isDeleteMemberResp = (action === "DELETE_MEMBER")
                                  || (data.action === "DELETE_MEMBER")

            if (isDeleteMemberResp) {
                if (data.status === "ok" || data.code === 0) {
                    deleteMemberConfirmBtn.enabled = true
                    deleteMemberConfirmBtn.text = "确定除名"
                    deleteMemberDialog.close()
                    statusText.text  = "成员已除名，正在刷新列表…"
                    statusText.color = "#2E7D32"
                    console.log("DELETE_MEMBER 成功: user_id=" + deleteMemberTargetId)
                    fetchMembers()
                } else {
                    deleteMemberConfirmBtn.enabled = true
                    deleteMemberConfirmBtn.text = "确定除名"
                    var errMsg = data.message || "未知错误"
                    statusText.text  = "除名失败: " + errMsg
                    statusText.color = "#C62828"
                    console.log("DELETE_MEMBER 失败, message:", errMsg, "full:", JSON.stringify(data))
                    deleteMemberDialog.close()
                }
                return
            }

        }

        // ---- 连接建立后自动拉取 ----
        function onConnectedChanged(connected) {
            if (connected && memberModel.count === 0 && mainWindow.isLoggedIn) {
                fetchMembers()
            }
        }
    }
}
