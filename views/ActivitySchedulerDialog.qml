import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================================
// ActivitySchedulerDialog.qml — 活动排班 · 多维空闲率全瞻透视（修复角色本地过滤版）
//
// 功能：
//    1. 时段选择（5×6 网格 + 周数）→ GET_TIME_ANALYTICS 请求
//    2. TabView 结果展示：空闲名单 / 上课忙碌（包含队长、部长、普通队员）
//    3. 部门 + 性别 + 角色（本地无网络IO损耗级联筛选）
//    4. 一键征召：暂存候选人到本地队列，通知父视图
//
// 约束：全文件禁止 String.arg()，字符串拼接一律用原生 +
// ============================================================================

Dialog {
    id: root
    title: "活动排班 · 多维空闲率全瞻透视"
    modal: true
    width: 850
    height: 720
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // ---- 暂存征召队列 ----
    property var stagedMembers: ([])
    signal membersStaged(var memberIds)

    // ---- 角色中文映射 ----
    function roleLabel(rid) {
        switch (rid) {
            case 10: return "带队老师"
            case 20: return "队长"
            case 30: return "部长"
            case 40: return "普通队员"
            default: return "普通队员"
        }
    }

    // ---- 性别映射 ----
    function genderLabel(g) {
        switch (g) {
            case 1: return "男生 👦"
            case 2: return "女生 👧"
            default: return "未知 ⚪"
        }
    }

    // ---- 运行时状态徽章 ----
    function stateEmoji(st) {
        switch (st) {
            case "free":          return "🍀"
            case "busy_activity": return "🔥"
            case "busy_course":   return "📚"
            default:              return "🍀"
        }
    }
    function stateLabel(st) {
        switch (st) {
            case "free":          return "空闲"
            case "busy_activity": return "活动中"
            case "busy_course":   return "上课中"
            default:              return "空闲"
        }
    }

    // ---- 5×6 单时段选择模型 ----
    ListModel {
        id: analyticsGridModel
        Component.onCompleted: {
            for (var period = 0; period < 6; ++period) {
                for (var day = 0; day < 5; ++day) {
                    append({
                        day:      day,
                        period:   period,
                        bitIndex: day * 6 + period,
                        checked:  false
                    })
                }
            }
        }
    }

    function computeSelectedMask() {
        var mask = 0
        for (var i = 0; i < analyticsGridModel.count; ++i) {
            var item = analyticsGridModel.get(i)
            if (item.checked) {
                mask |= (1 << item.bitIndex)
            }
        }
        return mask >>> 0
    }

    function updateMaskPreview() {
        var mask = computeSelectedMask()
        maskPreview.text = "0x" + ("00000000" + mask.toString(16).toUpperCase()).slice(-8)
        maskPreviewDec.text = "(" + mask + ")"
    }

    function clearAllChecks() {
        for (var i = 0; i < analyticsGridModel.count; ++i) {
            analyticsGridModel.setProperty(i, "checked", false)
        }
    }

    // ---- 空闲成员真实原始缓存模型 ----
    ListModel { id: freeMemberModel }

    // ---- 忙碌成员真实原始缓存模型 ----
    ListModel { id: busyMemberModel }

    // ---- 前端多维筛选器状态状态持久化 ----
    property string filterDept: "全部部门"
    property string filterGender: "全部性别"
    property int filterRole: 0  // 0=全部角色, 20=队长, 30=部长, 40=普通队员

    // ---- 部门过滤器数据源 ----
    ListModel {
        id: deptFilterModel
        Component.onCompleted: {
            append({ name: "全部部门" })
            append({ name: "策划部"   })
            append({ name: "外联部"   })
            append({ name: "办公室"   })
            append({ name: "宣传部"   })
            append({ name: "云教室"   })
        }
    }

    // ---- 性别过滤器数据源 ----
    ListModel {
        id: genderFilterModel
        Component.onCompleted: {
            append({ name: "全部性别", value: -1 })
            append({ name: "男生 👦",   value: 1  })
            append({ name: "女生 👧",   value: 2  })
            append({ name: "未知 ⚪",   value: 0  })
        }
    }

    // ---- 角色过滤器数据源（扩容补齐） ----
    ListModel {
        id: roleFilterModel
        Component.onCompleted: {
            append({ name: "全部角色", rid: 0 })
            append({ name: "队长",     rid: 20 })
            append({ name: "部长",     rid: 30 })
            append({ name: "普通队员", rid: 40 })
        }
    }

    // ========================================================================
    // 🧠 核心重构漏斗：本地多维交叉筛选引擎（避开频繁发网络包带来的死锁与开销）
    // ========================================================================
    function applyFilters(sourceModel, targetModel) {
        targetModel.clear()
        for (var i = 0; i < sourceModel.count; i++) {
            var m = sourceModel.get(i)
            
            // 1. 部门检索环
            var deptMatch = (filterDept === "全部部门" || m.dept_name === filterDept)
            
            // 2. 性别检索环
            var genderMatch = (filterGender === "全部性别")
                           || (filterGender === "男生 👦" && m.gender === 1)
                           || (filterGender === "女生 👧" && m.gender === 2)
                           || (filterGender === "未知 ⚪" && (m.gender === 0 || !m.gender))
            
            // 3. 角色系统检索环（补齐漏洞）
            var roleMatch = (filterRole === 0 || m.role_id === filterRole)

            if (deptMatch && genderMatch && roleMatch) {
                targetModel.append(m)
            }
        }
    }

    // ---- 暂存队列维护环 ----
    function isStaged(memberId) {
        for (var i = 0; i < stagedMembers.length; i++) {
            if (stagedMembers[i].user_id === memberId) return true
        }
        return false
    }

    function toggleStaged(memberData) {
        var mid = memberData.user_id
        for (var i = 0; i < stagedMembers.length; i++) {
            if (stagedMembers[i].user_id === mid) {
                stagedMembers.splice(i, 1)
                stagedMembers = Object.assign([], stagedMembers)
                return
            }
        }
        stagedMembers.push(memberData)
        stagedMembers = Object.assign([], stagedMembers)
    }

    function confirmStaging() {
        if (stagedMembers.length === 0) return
        var ids = []
        for (var i = 0; i < stagedMembers.length; i++) {
            ids.push(stagedMembers[i].user_id)
        }
        root.membersStaged(ids)
        stagedMembers = ([])
        scanStatusText.text = "已通知父视图接收 " + ids.length + " 名征召成员"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ---- 上半区：扫描参数区 ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: "目标周数："
                font.pixelSize: 13
            }
            SpinBox {
                id: weekSpin
                from: 1
                to: 16
                value: 1
                editable: true
                Layout.preferredWidth: 120
                font.pixelSize: 14
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "transparent"
            }

            Text {
                text: "选一个时段后点击扫描"
                font.pixelSize: 11
                color: "#888888"
            }
        }

        // ---- 5×6 时段网格 ----
        RowLayout {
            spacing: 0

            Column {
                spacing: 2
                Rectangle { width: 48; height: 22; color: "transparent" }
                Repeater {
                    model: ["第1节\n(08:00)", "第2节\n(10:10)", "中午档\n(12:00)",
                            "第3节\n(14:10)", "第4节\n(16:10)", "傍晚档\n(18:00)"]
                    Rectangle {
                        width: 48; height: 34
                        color: "#E8EAF6"
                        radius: 2
                        border { color: "#9FA8DA"; width: 0.5 }
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 8
                            font.bold: true
                            color: "#3949AB"
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }

            Column {
                spacing: 2

                Row {
                    spacing: 2
                    Repeater {
                        model: ["周一","周二","周三","周四","周五"]
                        Rectangle {
                            width: 62; height: 22
                            color: "#3F51B5"
                            radius: 2
                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                color: "white"
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }
                    }
                }

                Grid {
                    columns: 5
                    spacing: 2
                    Repeater {
                        model: analyticsGridModel
                        Rectangle {
                            width: 62; height: 34
                            color: model.checked ? "#C5CAE9" : "#E8EAF6"
                            radius: 2
                            border {
                                color: model.checked ? "#5C6BC0" : "#9FA8DA"
                                width: 0.5
                            }

                            CheckBox {
                                anchors.centerIn: parent
                                text: "选"
                                font.pixelSize: 9
                                checked: model.checked
                                onCheckedChanged: {
                                    if (checked) {
                                        for (var i = 0; i < analyticsGridModel.count; ++i) {
                                            if (i !== index) {
                                                analyticsGridModel.setProperty(i, "checked", false)
                                            }
                                        }
                                        analyticsGridModel.setProperty(index, "checked", true)
                                    } else {
                                        analyticsGridModel.setProperty(index, "checked", false)
                                    }
                                    updateMaskPreview()
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- 掩码预览 + 扫描按钮 ----
        RowLayout {
            spacing: 8

            Text { text: "time_mask:"; font.pixelSize: 11; color: "#555555" }
            Text {
                id: maskPreview
                text: "0x00000000"
                font.pixelSize: 12
                font.bold: true
                font.family: "Courier New"
                color: "#3F51B5"
            }
            Text {
                id: maskPreviewDec
                text: "(0)"
                font.pixelSize: 11
                color: "#888888"
                font.family: "Courier New"
            }

            Item { Layout.fillWidth: true }

            Button {
                id: scanBtn
                text: "执行透视扫描"
                Layout.preferredHeight: 34

                onClicked: {
                    var mask = computeSelectedMask()
                    if (mask === 0) {
                        scanStatusText.text = "请先选择一个时段"
                        return
                    }
                    scanBtn.enabled = false
                    scanBtn.text = "扫描中…"
                    scanStatusText.text = ""
                    stagedMembers = ([])
                    NetworkClient.sendRequest("GET_TIME_ANALYTICS", {
                        "target_week": weekSpin.value,
                        "time_mask":   mask
                    })
                }

                background: Rectangle {
                    color: scanBtn.enabled ? "#3F51B5" : "#BDBDBD"
                    radius: 4
                }
                contentItem: Text {
                    text: scanBtn.text
                    color: "white"
                    font.pixelSize: 13
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Text {
            id: scanStatusText
            font.pixelSize: 12
            color: "#555555"
            visible: text !== ""
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#E0E0E0"
        }

        // ---- 下半区：结果展示头 ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "预测结果：共 " + (totalCountText.text || "0") + " 人"
                font.pixelSize: 13
                font.bold: true
                color: "#333333"
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "空闲 " + (freeCountText.text || "0") + " 人 ("
                      + (freeRateText.text || "0%") + ")"
                font.pixelSize: 13
                color: "#2E7D32"
                font.bold: true
            }
        }

        // ====================================================================
        // 🛠️ 升级过滤控制栏：补齐漏掉的角色 ComboBox
        // ====================================================================
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text { text: "部门："; font.pixelSize: 12 }
            ComboBox {
                id: deptFilterCombo
                model: deptFilterModel
                textRole: "name"
                Layout.preferredWidth: 100
                onCurrentTextChanged: {
                    filterDept = currentText
                    applyFilters(freeMemberModel, freeFilteredModel)
                    applyFilters(busyMemberModel, busyFilteredModel)
                }
            }

            Text { text: "性别："; font.pixelSize: 12 }
            ComboBox {
                id: genderFilterCombo
                model: genderFilterModel
                textRole: "name"
                Layout.preferredWidth: 100
                onCurrentTextChanged: {
                    filterGender = currentText
                    applyFilters(freeMemberModel, freeFilteredModel)
                    applyFilters(busyMemberModel, busyFilteredModel)
                }
            }

            // 👉 补齐组件：角色选择器
            Text { text: "角色："; font.pixelSize: 12 }
            ComboBox {
                id: roleFilterCombo
                model: roleFilterModel
                textRole: "name"
                Layout.preferredWidth: 110
                onCurrentIndexChanged: {
                    var item = roleFilterModel.get(currentIndex)
                    if (item) {
                        filterRole = item.rid
                        applyFilters(freeMemberModel, freeFilteredModel)
                        applyFilters(busyMemberModel, busyFilteredModel)
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        // ---- 展示视图綁定的已过滤模型群 ----
        ListModel { id: freeFilteredModel }
        ListModel { id: busyFilteredModel }

        TabBar {
            id: resultTabBar
            Layout.fillWidth: true

            TabButton { text: "空闲名单 👍" }
            TabButton { text: "上课忙碌 📚" }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: resultTabBar.currentIndex

            // ===== Tab 0: 空闲名单 =====
            ColumnLayout {
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    height: 24
                    color: "#E8F5E9"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8; anchors.rightMargin: 8
                        spacing: 0
                        Text { text: "ID";       font.bold: true; Layout.preferredWidth: 55; font.pixelSize: 11 }
                        Text { text: "姓名";     font.bold: true; Layout.preferredWidth: 75; font.pixelSize: 11 }
                        Text { text: "学号";     font.bold: true; Layout.preferredWidth: 95; font.pixelSize: 11 }
                        Text { text: "部门";     font.bold: true; Layout.preferredWidth: 85; font.pixelSize: 11 }
                        Text { text: "角色";     font.bold: true; Layout.preferredWidth: 85; font.pixelSize: 11 }
                        Text { text: "性别";     font.bold: true; Layout.preferredWidth: 70; font.pixelSize: 11 }
                        Text { text: "志愿时长"; font.bold: true; Layout.preferredWidth: 70; font.pixelSize: 11 }
                        Text { text: "瞬时状态"; font.bold: true; Layout.preferredWidth: 90; font.pixelSize: 11 }
                        Item { Layout.fillWidth: true }
                    }
                }

                ListView {
                    id: freeListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: freeFilteredModel

                    Label {
                        anchors.centerIn: parent
                        text: freeFilteredModel.count === 0 ? "没有匹配当前筛选条件的空闲成员" : ""
                        color: "#999999"
                        font.pixelSize: 12
                    }

                    delegate: Rectangle {
                        width: freeListView.width
                        height: 36
                        color: index % 2 === 0 ? "#FAFAFA" : "#FFFFFF"
                        border { color: "#E0E0E0"; width: 0.5 }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            spacing: 0

                            Text {
                                text: model.user_id || "-"
                                Layout.preferredWidth: 55
                                font.pixelSize: 11
                                font.family: "Courier New"
                                color: "#888888"
                            }
                            Text {
                                text: model.name || "-"
                                Layout.preferredWidth: 75
                                font.pixelSize: 12
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: model.student_id || "-"
                                Layout.preferredWidth: 95
                                font.pixelSize: 11
                                font.family: "Courier New"
                                color: "#555555"
                                elide: Text.ElideRight
                            }
                            Text {
                                text: model.dept_name || "-"
                                Layout.preferredWidth: 85
                                font.pixelSize: 11
                                color: "#555555"
                                elide: Text.ElideRight
                            }
                            Text {
                                text: roleLabel(model.role_id)
                                Layout.preferredWidth: 85
                                font.pixelSize: 11
                                color: model.role_id <= 20 ? "#1565C0" : "#555555"
                            }
                            Text {
                                text: genderLabel(model.gender)
                                Layout.preferredWidth: 70
                                font.pixelSize: 11
                            }
                            Text {
                                text: (model.total_hours || 0) + "h"
                                Layout.preferredWidth: 70
                                font.pixelSize: 11
                                color: model.total_hours > 0 ? "#2E7D32" : "#9E9E9E"
                            }
                            Text {
                                text: "🍀 空闲"
                                Layout.preferredWidth: 90
                                font.pixelSize: 11
                                color: "#2E7D32"
                            }

                            Item { Layout.fillWidth: true }

                            Button {
                                text: isStaged(model.user_id) ? "已暂存" : "一键征召"
                                Layout.preferredWidth: 80
                                Layout.preferredHeight: 26

                                onClicked: {
                                    var memberData = {
                                        "user_id":    model.user_id,
                                        "name":      model.name,
                                        "dept_name": model.dept_name,
                                        "gender":    model.gender,
                                        "role_id":   model.role_id
                                    }
                                    toggleStaged(memberData)
                                }

                                background: Rectangle {
                                    color: isStaged(model.user_id || model.id) ? "#9E9E9E" : "#2E7D32"
                                    radius: 4
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: "white"
                                    font.pixelSize: 10
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }
            }

            // ===== Tab 1: 上课忙碌 =====
            ColumnLayout {
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    height: 24
                    color: "#FFEBEE"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8; anchors.rightMargin: 8
                        spacing: 0
                        Text { text: "ID";       font.bold: true; Layout.preferredWidth: 55; font.pixelSize: 11 }
                        Text { text: "姓名";     font.bold: true; Layout.preferredWidth: 75; font.pixelSize: 11 }
                        Text { text: "学号";     font.bold: true; Layout.preferredWidth: 95; font.pixelSize: 11 }
                        Text { text: "部门";     font.bold: true; Layout.preferredWidth: 85; font.pixelSize: 11 }
                        Text { text: "角色";     font.bold: true; Layout.preferredWidth: 85; font.pixelSize: 11 }
                        Text { text: "性别";     font.bold: true; Layout.preferredWidth: 70; font.pixelSize: 11 }
                        Text { text: "志愿时长"; font.bold: true; Layout.preferredWidth: 70; font.pixelSize: 11 }
                        Text { text: "瞬时状态"; font.bold: true; Layout.preferredWidth: 90; font.pixelSize: 11 }
                        Item { Layout.fillWidth: true }
                    }
                }

                ListView {
                    id: busyListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: busyFilteredModel

                    Label {
                        anchors.centerIn: parent
                        text: busyFilteredModel.count === 0 ? "无匹配筛选条件的忙碌成员" : ""
                        color: "#999999"
                        font.pixelSize: 12
                    }

                    delegate: Rectangle {
                        width: busyListView.width
                        height: 36
                        color: index % 2 === 0 ? "#FAFAFA" : "#FFFFFF"
                        border { color: "#E0E0E0"; width: 0.5 }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            spacing: 0

                            Text {
                                text: model.user_id || "-"
                                Layout.preferredWidth: 55
                                font.pixelSize: 11
                                font.family: "Courier New"
                                color: "#888888"
                            }
                            Text {
                                text: model.name || "-"
                                Layout.preferredWidth: 75
                                font.pixelSize: 12
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: model.student_id || "-"
                                Layout.preferredWidth: 95
                                font.pixelSize: 11
                                font.family: "Courier New"
                                color: "#555555"
                                elide: Text.ElideRight
                            }
                            Text {
                                text: model.dept_name || "-"
                                Layout.preferredWidth: 85
                                font.pixelSize: 11
                                color: "#555555"
                                elide: Text.ElideRight
                            }
                            Text {
                                text: roleLabel(model.role_id)
                                Layout.preferredWidth: 85
                                font.pixelSize: 11
                                color: model.role_id <= 20 ? "#1565C0" : "#555555"
                            }
                            Text {
                                text: genderLabel(model.gender)
                                Layout.preferredWidth: 70
                                font.pixelSize: 11
                            }
                            Text {
                                text: (model.total_hours || 0) + "h"
                                Layout.preferredWidth: 70
                                font.pixelSize: 11
                                color: model.total_hours > 0 ? "#2E7D32" : "#9E9E9E"
                            }
                            Text {
                                text: stateEmoji(model.current_state) + " " + stateLabel(model.current_state)
                                Layout.preferredWidth: 90
                                font.pixelSize: 11
                                color: model.current_state === "busy_activity" ? "#E65100" : "#C62828"
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }
        }

        // ---- 底部暂存栏 ----
        Rectangle {
            Layout.fillWidth: true
            height: 40
            color: "#FFF8E1"
            radius: 4
            visible: stagedMembers.length > 0

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 12
                spacing: 8

                Text {
                    text: "已暂存 " + stagedMembers.length + " 名候选人待征召"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#F57C00"
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "清空暂存"
                    Layout.preferredHeight: 28
                    onClicked: { stagedMembers = ([]) }
                    background: Rectangle { color: "#E0E0E0"; radius: 4 }
                    contentItem: Text {
                        text: parent.text; color: "#333333"; font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                }

                Button {
                    text: "确认征召"
                    Layout.preferredHeight: 28
                    onClicked: confirmStaging()
                    background: Rectangle { color: "#E65100"; radius: 4 }
                    contentItem: Text {
                        text: parent.text; color: "white"; font.pixelSize: 11; font.bold: true
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    // ---- 隐藏存储项 ----
    Text { id: totalCountText; text: "0"; visible: false }
    Text { id: freeCountText;  text: "0"; visible: false }
    Text { id: freeRateText;   text: "0%"; visible: false }

    Connections {
        target: NetworkClient

        function onResponseReceived(action, data) {
            var isAnalyticsResp = (action === "GET_TIME_ANALYTICS")
                               || (data.action === "GET_TIME_ANALYTICS")

            if (!isAnalyticsResp) return

            scanBtn.enabled = true
            scanBtn.text = "执行透视扫描"

            if (data.status === "ok" || data.code === 0) {
                var dd = data.data || data
                var total = dd.total_count || 0
                var free  = dd.free_count  || 0
                var rate  = total > 0 ? ((free / total) * 100).toFixed(1) : 0

                totalCountText.text = "" + total
                freeCountText.text  = "" + free
                freeRateText.text   = rate + "%"

                var freeMembers = dd.free_members || []
                freeMemberModel.clear()
                for (var i = 0; i < freeMembers.length; i++) {
                    // 兼容后端可能传回的不同 id 命名
                    var itemF = freeMembers[i]
                    if (!itemF.hasOwnProperty("role_id")) itemF["role_id"] = 40 // 默认补齐兜底
                    freeMemberModel.append(itemF)
                }

                var busyMembers = dd.busy_members || []
                busyMemberModel.clear()
                for (var j = 0; j < busyMembers.length; j++) {
                    var itemB = busyMembers[j]
                    if (!itemB.hasOwnProperty("role_id")) itemB["role_id"] = 40
                    busyMemberModel.append(itemB)
                }

                applyFilters(freeMemberModel, freeFilteredModel)
                applyFilters(busyMemberModel, busyFilteredModel)

                scanStatusText.text = "透视完成 — 共 " + total + " 人，"
                                    + free + " 人空闲 (" + rate + "%)"
            } else {
                scanStatusText.text = "扫描失败: " + (data.message || "未知错误")
            }
        }
    }
}