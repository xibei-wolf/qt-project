import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================================
// ActivityDispatchView.qml — 活动排班 / 活动互动 双模式视图
//
// 模式分流（RBAC）：
//   角色 10/20/30（老师/队长/部长）→ 管理员排班模式
//     - GET_ACTIVITIES 拉取活动列表
//     - FILTER_AVAILABLE_MEMBERS 无课筛选
//     - CONFIRM_ASSIGN 一键录用落盘
//
//   角色 40（普通队员）→ 成员互动模式
//     - GET_ACTIVITIES 拉取活动列表（含 status 字段）
//     - APPLY_ACTIVITY   申请参与活动
//     - LEAVE_ACTIVITY   主动请假 / 取消申请
//
// 活动状态语义：
//   status == 1 → 未开始（可申请/可请假）
//   status == 2 → 进行中（禁止变更）
//   status == 3 → 已完结（禁止变更）
//
// 约束：全文件禁止 String.arg()，字符串拼接一律用原生 +
// ============================================================================

Item {
    id: root

    // ---- 活动状态中文映射 ----
    function statusLabel(s) {
        switch (s) {
            case 1: return "未开始"
            case 2: return "进行中"
            case 3: return "已完结"
            default: return "未知"
        }
    }

    function statusBadgeColor(s) {
        switch (s) {
            case 1: return "#1565C0"
            case 2: return "#E65100"
            case 3: return "#757575"
            default: return "#9E9E9E"
        }
    }

    function statusBgColor(s) {
        switch (s) {
            case 1: return "#E3F2FD"
            case 2: return "#FFF3E0"
            case 3: return "#F5F5F5"
            default: return "#F5F5F5"
        }
    }

    // ---- 数据模型：候选人名单（管理员模式）----
    ListModel {
        id: memberModel
    }

    // ---- 数据模型：活动列表（两种模式共用）----
    ListModel {
        id: activityPresetModel
    }

    // ---- 预设部门列表 ----
    ListModel {
        id: deptModel
        Component.onCompleted: {
            append({ name: "全部部门", id: 0 })
            append({ name: "策划部",   id: 1 })
            append({ name: "外联部",   id: 2 })
            append({ name: "办公室",   id: 3 })
            append({ name: "宣传部",   id: 4 })
            append({ name: "云教室",   id: 5 })
        }
    }

    // ---- 预设角色筛选列表 ----
    ListModel {
        id: roleFilterModel
        Component.onCompleted: {
            append({ name: "全部角色", rid: 0 })
            append({ name: "带队老师", rid: 10 })
            append({ name: "队长",     rid: 20 })
            append({ name: "部长",     rid: 30 })
            append({ name: "普通队员", rid: 40 })
        }
    }

    // ---- 预设性别筛选列表 ----
    ListModel {
        id: genderFilterModel
        Component.onCompleted: {
            append({ name: "全部性别", value: -1 })
            append({ name: "男生 👦",   value: 1  })
            append({ name: "女生 👧",   value: 2  })
            append({ name: "未知 ⚪",   value: 0  })
        }
    }

    // ---- 角色中文映射 ----
    function roleName(rid) {
        switch (rid) {
            case 10: return "带队老师"
            case 20: return "队长"
            case 30: return "部长"
            case 40: return "普通队员"
            default: return "未知"
        }
    }

    function roleBadgeColor(rid) {
        switch (rid) {
            case 10: return "#C62828"
            case 20: return "#1565C0"
            case 30: return "#00897B"
            case 40: return "#757575"
            default: return "#9E9E9E"
        }
    }

    // ---- 运行时状态标签 ----
    function stateText(st) {
        switch (st) {
            case "free":          return "🍀 此时空闲"
            case "busy_activity": return "🔥 别处有活动"
            case "busy_course":   return "📚 正在上课"
            default:              return "🍀 此时空闲"
        }
    }
    function stateTextColor(st) {
        switch (st) {
            case "free":          return "#2E7D32"
            case "busy_activity": return "#E65100"
            case "busy_course":   return "#C62828"
            default:              return "#2E7D32"
        }
    }
    function stateBgColor(st) {
        switch (st) {
            case "free":          return "#E8F5E9"
            case "busy_activity": return "#FFF3E0"
            case "busy_course":   return "#FFEBEE"
            default:              return "#E8F5E9"
        }
    }

    // ================================================================
    // 页面初始化
    // ================================================================
    Component.onCompleted: {
        triggerFetchActivities()
    }

    function triggerFetchActivities() {
        if (!NetworkClient.connected) {
            console.log("GET_ACTIVITIES: 未连接，等待连接建立后自动拉取")
            return
        }
        console.log("触发 GET_ACTIVITIES 请求…")
        NetworkClient.sendRequest("GET_ACTIVITIES", {})
    }

    // ================================================================
    // 管理员模式 — 按钮状态管理
    // ================================================================
    function setAssignPending() {
        assignBtn.enabled = false
        assignBtn.text    = "录用中…"
        statusText.text   = "录用落盘中…"
        statusText.color  = "#F57C00"
    }

    function restoreAssignBtn() {
        assignBtn.enabled = true
        assignBtn.text    = "一键录用所有候选人"
    }

    // ---- 本地多维筛选引擎 ----
    property var rawAvailableMembers: []

    function applyLocalSchedulingFilters() {
        if (!rawAvailableMembers || rawAvailableMembers.length === 0) {
            memberModel.clear()
            return
        }

        var filtered = rawAvailableMembers.slice()

        // 1. 搜索过滤（姓名 或 学号）
        var kw = searchField.text.trim().toLowerCase()
        if (kw !== "") {
            filtered = filtered.filter(function(m) {
                return (m.name || "").toLowerCase().indexOf(kw) !== -1
                    || (m.student_id || "").toLowerCase().indexOf(kw) !== -1
            })
        }

        // 2. 部门过滤
        var deptObj = deptModel.get(deptCombo.currentIndex)
        if (deptObj && deptObj.id !== 0) {
            var targetDept = deptObj.name
            filtered = filtered.filter(function(m) {
                return m.dept_name === targetDept
            })
        }

        // 3. 角色过滤
        var roleObj = roleFilterModel.get(roleFilterCombo.currentIndex)
        if (roleObj && roleObj.rid !== 0) {
            var targetRole = roleObj.rid
            filtered = filtered.filter(function(m) {
                return m.role_id === targetRole
            })
        }

        // 4. 性别过滤
        var genderObj = genderFilterModel.get(genderFilterCombo.currentIndex)
        if (genderObj && genderObj.value !== -1) {
            var targetGender = genderObj.value
            filtered = filtered.filter(function(m) {
                return m.gender === targetGender
            })
        }

        // 5. 排序
        var mode = sortCombo.currentIndex
        if (mode === 0) {
            filtered.sort(function(a, b) { return (a.student_id || "").localeCompare(b.student_id || "") })
        } else if (mode === 1) {
            filtered.sort(function(a, b) { return (b.total_count || 0) - (a.total_count || 0) })
        } else if (mode === 2) {
            filtered.sort(function(a, b) { return (b.total_hours || 0) - (a.total_hours || 0) })
        } else if (mode === 3) {
            filtered.sort(function(a, b) { return new Date(b.last_time || 0) - new Date(a.last_time || 0) })
        }

        // 6. 灌入展示模型
        memberModel.clear()
        for (var i = 0; i < filtered.length; i++) {
            var m = filtered[i]
            memberModel.append({
                "user_id":       m.user_id,
                "name":          m.name,
                "student_id":    m.student_id,
                "dept_name":     m.dept_name,
                "role_id":       m.role_id || 0,
                "phone":         m.phone || "-",
                "total_count":   m.total_count || 0,
                "total_hours":   m.total_hours || 0,
                "last_time":     (m.last_time === "1970-01-01 00:00:00" || m.last_time === "无记录") ? "暂无历史" : m.last_time,
                "current_state": m.current_state || "free",
                "gender":        m.gender || 0
            })
        }

        var dirty = (rawAvailableMembers.length !== filtered.length)
        statusText.text = "共 " + filtered.length + " 名候选人" + (dirty ? " (已筛选)" : "")
        statusText.color = dirty ? "#1565C0" : "#555555"
    }

    // ================================================================
    // 主布局
    // ================================================================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // ================================================================
        // 标题行（双模式自适应）
        // ================================================================
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: mainWindow.isRole40 ? "活动互动 · 报名与请假" : "活动排班 · 智能无课筛选"
                font.pixelSize: 20
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Button {
                text: "➕ 发布新活动"
                visible: mainWindow.isLoggedIn && !mainWindow.isRole40
                onClicked: addActivityDialog.open()

                background: Rectangle {
                    color: "#1565C0"
                    radius: 4
                }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font.pixelSize: 12
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Button {
                text: "📊 排班透视"
                visible: mainWindow.isLoggedIn && !mainWindow.isRole40
                onClicked: {
                    schedulerDialog.stagedMembers = ([])
                    schedulerDialog.open()
                }

                background: Rectangle {
                    color: "#6A1B9A"
                    radius: 4
                }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font.pixelSize: 12
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        // ---- 通用状态文字 ----
        Text {
            id: statusText
            text: "就绪"
            font.pixelSize: 12
            color: "#666666"
        }

        // ---- 成员模式专属状态文字 ----
        Text {
            id: memberStatusText
            text: ""
            font.pixelSize: 12
            color: "#2E7D32"
            visible: mainWindow.isRole40 && text !== ""
        }

        // ================================================================
        // 🔹 管理员排班模式（role 10/20/30）
        // ================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: mainWindow.isLoggedIn && !mainWindow.isRole40

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                // ---- 筛选 + 录用 条件行 ----
                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true

                    ComboBox {
                        id: activityCombo
                        Layout.preferredWidth: 260
                        textRole: "name"
                        model: activityPresetModel
                        displayText: activityPresetModel.count > 0
                                     ? (currentIndex >= 0 ? currentText : "请选择活动…")
                                     : "（暂无活动，请检查连接）"

                        delegate: ItemDelegate {
                            width: activityCombo.popup.width
                            contentItem: Column {
                                spacing: 2
                                Text {
                                    text: model.name
                                    font.pixelSize: 13
                                }
                                Text {
                                    text: "Week " + model.activityWeek
                                          + " · mask=0x" + model.timeMask.toString(16).toUpperCase()
                                          + " · " + (model.location || "")
                                          + " · " + statusLabel(model.status)
                                    font.pixelSize: 10
                                    color: "#888888"
                                }
                                Text {
                                    text: "DB ID: " + (model.db_id || "—")
                                    font.pixelSize: 9
                                    color: "#BBBBBB"
                                }
                            }
                        }
                    }

                    Button {
                        text: "刷新活动"
                        enabled: NetworkClient.connected
                        onClicked: {
                            statusText.text  = "正在拉取活动列表…"
                            statusText.color = "#1565C0"
                            triggerFetchActivities()
                        }
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

                    Text { text: "部门:"; font.pixelSize: 12; color: "#555555" }

                    ComboBox {
                        id: deptCombo
                        Layout.preferredWidth: 100
                        textRole: "name"
                        model: deptModel
                        currentIndex: 0
                        onCurrentIndexChanged: root.applyLocalSchedulingFilters()
                    }

                    Text { text: "角色:"; font.pixelSize: 12; color: "#555555" }

                    ComboBox {
                        id: roleFilterCombo
                        Layout.preferredWidth: 100
                        textRole: "name"
                        model: roleFilterModel
                        currentIndex: 0
                        onCurrentIndexChanged: root.applyLocalSchedulingFilters()
                    }

                    Text { text: "性别:"; font.pixelSize: 12; color: "#555555" }

                    ComboBox {
                        id: genderFilterCombo
                        Layout.preferredWidth: 100
                        textRole: "name"
                        model: genderFilterModel
                        currentIndex: 0
                        onCurrentIndexChanged: root.applyLocalSchedulingFilters()
                    }

                    Text { text: "排序:"; font.pixelSize: 12; color: "#555555" }

                    ComboBox {
                        id: sortCombo
                        Layout.preferredWidth: 150
                        model: ["按学号默认排序", "按参与次数从多到少", "按总时长从多到少", "按最近参与时间"]
                        onCurrentIndexChanged: root.applyLocalSchedulingFilters()
                    }
                }

                // ---- 搜索 + 操作按钮行 ----
                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true

                    TextField {
                        id: searchField
                        Layout.preferredWidth: 180
                        placeholderText: "搜索姓名 / 学号…"
                        font.pixelSize: 12
                        onTextChanged: root.applyLocalSchedulingFilters()
                    }

                    Button {
                        text: "一键筛选有空队员"
                        enabled: NetworkClient.connected && activityCombo.currentIndex >= 0

                        onClicked: {
                            var preset = activityPresetModel.get(activityCombo.currentIndex)
                            var payload = {
                                "activity_week": preset.activityWeek,
                                "time_mask":     preset.timeMask
                            }

                            console.log("发送 FILTER_AVAILABLE_MEMBERS:", JSON.stringify(payload))

                            statusText.text  = "筛选中…"
                            statusText.color = "#F57C00"

                            NetworkClient.sendRequest("FILTER_AVAILABLE_MEMBERS", payload)
                        }

                        background: Rectangle {
                            color: parent.enabled ? "#1565C0" : "#BDBDBD"
                            radius: 4
                        }
                        contentItem: Text {
                            text: parent.text
                            color: "white"
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        id: assignBtn
                        text: "一键录用所有候选人"
                        enabled: NetworkClient.connected
                                 && memberModel.count > 0
                                 && activityCombo.currentIndex >= 0

                        onClicked: {
                            var currentActivity = activityPresetModel.get(activityCombo.currentIndex)
                            var realActivityId = currentActivity.db_id

                            if (!realActivityId || realActivityId <= 0) {
                                statusText.text  = "错误: 当前活动缺少有效的 activity_id"
                                statusText.color = "#C62828"
                                return
                            }

                            var idList = []
                            for (var i = 0; i < memberModel.count; i++) {
                                idList.push(memberModel.get(i).user_id)
                            }

                            console.log("发送 CONFIRM_ASSIGN, activity_id=" + realActivityId
                                        + ", user_ids:", JSON.stringify(idList))

                            setAssignPending()

                            NetworkClient.sendRequest("CONFIRM_ASSIGN", {
                                "activity_id": realActivityId,
                                "user_ids": idList
                            })
                        }

                        background: Rectangle {
                            color: assignBtn.enabled ? "#E65100" : "#BDBDBD"
                            radius: 4
                        }
                        contentItem: Text {
                            text: assignBtn.text
                            color: "white"
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                // ---- 人数统计 ----
                Text {
                    text: memberModel.count > 0
                          ? ("共有 " + memberModel.count + " 名候选人符合条件") : ""
                    font.pixelSize: 12
                    color: "#1565C0"
                }

                // ---- 当前筛选参数回显 ----
                Text {
                    visible: activityCombo.currentIndex >= 0
                    text: {
                        var p = activityPresetModel.get(activityCombo.currentIndex)
                        return "当前筛选: Week " + p.activityWeek
                               + " · time_mask=0x" + p.timeMask.toString(16).toUpperCase()
                               + " · " + p.name
                               + " [db_id=" + (p.db_id || "—") + "]"
                    }
                    font.pixelSize: 11
                    color: "#888888"
                    font.family: "Courier New"
                }

                // ---- 候选人名单列表头 ----
                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    color: "#E3F2FD"
                    radius: 4

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        spacing: 0

                        Text { text: "ID";       font.bold: true; Layout.preferredWidth: 50 }
                        Text { text: "姓名";     font.bold: true; Layout.preferredWidth: 80 }
                        Text { text: "学号";     font.bold: true; Layout.preferredWidth: 120 }
                        Text { text: "部门";     font.bold: true; Layout.preferredWidth: 80 }
                        Text { text: "角色";     font.bold: true; Layout.preferredWidth: 80 }
                        Text { text: "手机号";   font.bold: true; Layout.preferredWidth: 100 }
                        Text { text: "次数";     font.bold: true; Layout.preferredWidth: 50 }
                        Text { text: "累计时长"; font.bold: true; Layout.preferredWidth: 70 }
                        Text { text: "最近参与时间"; font.bold: true; Layout.fillWidth: true }
                        Text { text: "空闲状态"; font.bold: true; Layout.preferredWidth: 96 }
                    }
                }

                // ---- 候选人名单列表 ----
                ListView {
                    id: memberList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: memberModel

                    Label {
                        anchors.centerIn: parent
                        text: memberModel.count === 0
                              ? "暂无结果 — 请选择一个活动并点击「一键筛选」"
                              : ""
                        color: "#999999"
                        font.pixelSize: 13
                    }

                    delegate: Rectangle {
                        width: memberList.width
                        height: 44
                        color: index % 2 === 0 ? "#FAFAFA" : "#FFFFFF"
                        border { color: "#E0E0E0"; width: 0.5 }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12; anchors.rightMargin: 12
                            spacing: 0

                            Text {
                                text: model.user_id || "-"
                                Layout.preferredWidth: 50
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
                                text: model.dept_name || "-"
                                Layout.preferredWidth: 80
                                font.pixelSize: 13
                            }
                            Rectangle {
                                Layout.preferredWidth: 72; height: 24
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
                            Text {
                                text: model.phone || "-"
                                Layout.preferredWidth: 100
                                font.pixelSize: 12
                                color: "#777777"
                            }
                            Text {
                                text: model.total_count || 0
                                Layout.preferredWidth: 50
                                font.pixelSize: 13
                                font.bold: true
                                color: model.total_count > 0 ? "#1565C0" : "#9E9E9E"
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                text: (model.total_hours || 0) + "h"
                                Layout.preferredWidth: 70
                                font.pixelSize: 13
                                font.bold: true
                                color: model.total_hours > 0 ? "#2E7D32" : "#9E9E9E"
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                text: model.last_time || "暂无历史"
                                Layout.fillWidth: true
                                font.pixelSize: 11
                                color: model.last_time === "暂无历史" ? "#9E9E9E" : "#555555"
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                Layout.preferredWidth: 96; height: 24
                                radius: 12
                                color: stateBgColor(model.current_state)
                                Text {
                                    anchors.centerIn: parent
                                    text: stateText(model.current_state)
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: stateTextColor(model.current_state)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ================================================================
        // 🔹 成员互动模式（role 40）
        // ================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: mainWindow.isLoggedIn && mainWindow.isRole40

            ColumnLayout {
                anchors.fill: parent
                spacing: 8

                // ---- 活动列表头 ----
                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    color: "#E3F2FD"
                    radius: 4

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        spacing: 0

                        Text { text: "ID";   font.bold: true; Layout.preferredWidth: 40 }
                        Text { text: "活动名称"; font.bold: true; Layout.preferredWidth: 240 }
                        Text { text: "周数"; font.bold: true; Layout.preferredWidth: 50 }
                        Text { text: "地点"; font.bold: true; Layout.preferredWidth: 100 }
                        Text { text: "状态"; font.bold: true; Layout.preferredWidth: 80 }
                        Item { Layout.fillWidth: true }
                        Text { text: "操作"; font.bold: true; Layout.preferredWidth: 200 }
                    }
                }

                // ---- 成员活动列表 ----
                ListView {
                    id: memberActivityList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: activityPresetModel
                    spacing: 4

                    Label {
                        anchors.centerIn: parent
                        text: activityPresetModel.count === 0
                              ? "暂无活动 — 请刷新列表"
                              : ""
                        color: "#999999"
                        font.pixelSize: 13
                    }

                    delegate: Rectangle {
                        width: memberActivityList.width
                        height: 52
                        color: index % 2 === 0 ? "#FAFAFA" : "#FFFFFF"
                        border { color: "#E0E0E0"; width: 0.5 }
                        radius: 4

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12; anchors.rightMargin: 12
                            spacing: 0

                            // 活动 ID
                            Text {
                                text: model.db_id || "-"
                                Layout.preferredWidth: 40
                                font.pixelSize: 12
                                font.family: "Courier New"
                                color: "#888888"
                            }

                            // 活动名称
                            Text {
                                text: model.name || "-"
                                Layout.preferredWidth: 240
                                font.pixelSize: 13
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            // 周数
                            Rectangle {
                                Layout.preferredWidth: 44; height: 22
                                radius: 11
                                color: "#E3F2FD"
                                Text {
                                    anchors.centerIn: parent
                                    text: "W" + (model.activityWeek || 0)
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: "#1565C0"
                                }
                            }

                            // 地点
                            Text {
                                text: model.location || "-"
                                Layout.preferredWidth: 100
                                font.pixelSize: 12
                                color: "#555555"
                                elide: Text.ElideRight
                            }

                            // 状态徽章
                            Rectangle {
                                Layout.preferredWidth: 72; height: 24
                                radius: 12
                                color: statusBgColor(model.status)

                                Text {
                                    anchors.centerIn: parent
                                    text: statusLabel(model.status)
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: statusBadgeColor(model.status)
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // 操作按钮组
                            RowLayout {
                                Layout.preferredWidth: 200
                                spacing: 6

                                // 申请参与（status==1 时可用）
                                Button {
                                    text: "申请参与"
                                    enabled: model.status === 1

                                    onClicked: {
                                        if (!mainWindow.isLoggedIn || !mainWindow.currentUser.user_id) return
                                        memberStatusText.text = "正在提交申请…"
                                        memberStatusText.color = "#F57C00"
                                        NetworkClient.sendRequest("APPLY_ACTIVITY", {
                                            "activity_id": model.db_id,
                                            "user_id": mainWindow.currentUser.user_id
                                        })
                                    }

                                    background: Rectangle {
                                        color: parent.enabled ? "#43A047" : "#BDBDBD"
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

                                // 请假/取消申请（status==1 时可用）
                                Button {
                                    text: "请假/取消"
                                    enabled: model.status === 1

                                    onClicked: {
                                        if (!mainWindow.isLoggedIn || !mainWindow.currentUser.user_id) return
                                        memberStatusText.text = "正在提交请假…"
                                        memberStatusText.color = "#F57C00"
                                        NetworkClient.sendRequest("LEAVE_ACTIVITY", {
                                            "activity_id": model.db_id,
                                            "user_id": mainWindow.currentUser.user_id
                                        })
                                    }

                                    background: Rectangle {
                                        color: parent.enabled ? "#EF6C00" : "#BDBDBD"
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

                                // 状态提示（status != 1 时显示）
                                Text {
                                    text: model.status === 2 ? "活动已开始，禁止变更"
                                          : model.status === 3 ? "活动已完结"
                                          : ""
                                    font.pixelSize: 11
                                    color: model.status === 2 ? "#E65100" : "#9E9E9E"
                                    font.bold: true
                                    visible: model.status !== 1
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- 发布新活动弹窗 ----
    AddActivityDialog {
        id: addActivityDialog
    }

    // ====================================================================
    // 📊 排班透视调度器 对话框实例
    // ====================================================================
    ActivitySchedulerDialog {
        id: schedulerDialog

        onMembersStaged: {
            if (!memberIds || memberIds.length === 0) return

            var selIdx = activityCombo.currentIndex
            if (selIdx < 0) {
                statusText.text  = "请先在活动下拉框中选择一个目标活动"
                statusText.color = "#C62828"
                return
            }
            var currentActivity = activityPresetModel.get(selIdx)
            var realActivityId = currentActivity.db_id
            if (!realActivityId || realActivityId <= 0) {
                statusText.text  = "所选活动 ID 无效，请重新选择活动"
                statusText.color = "#C62828"
                return
            }

            console.log("排班透视 一键征召 BATCH_ASSIGN: activity_id=" + realActivityId
                        + ", user_ids:", JSON.stringify(memberIds))

            NetworkClient.sendRequest("BATCH_ASSIGN_MEMBERS", {
                "activity_id": realActivityId,
                "user_ids":    memberIds
            })

            schedulerDialog.close()

            statusText.text  = "已发送批量征召请求，正在将 " + memberIds.length
                             + " 名候选人录用至活动 " + realActivityId + " …"
            statusText.color = "#F57C00"
        }
    }

    // ====================================================================
    // 全局响应监听（多链路合并）
    // ====================================================================
    Connections {
        target: NetworkClient

        function onResponseReceived(action, data) {
            // ============================================================
            // 链路 A：GET_ACTIVITIES 活动列表拉取响应
            // ============================================================
            var isActivitiesResp = (action === "GET_ACTIVITIES")
                                || (data.action === "GET_ACTIVITIES")

            if (isActivitiesResp) {
                if (data.status === "ok" && data.data && data.data.activities) {
                    var activities = data.data.activities

                    if (!Array.isArray(activities)) {
                        console.warn("GET_ACTIVITIES: activities is not an array")
                        return
                    }

                    activityPresetModel.clear()

                    for (var k = 0; k < activities.length; k++) {
                        var act = activities[k]
                        activityPresetModel.append({
                            name:         act.title         || "",
                            activityWeek: act.activity_week || 0,
                            timeMask:     act.time_mask     || 0,
                            db_id:        act.activity_id   || 0,
                            location:     act.location      || "",
                            status:       act.status        || 1
                        })
                    }

                    statusText.text  = "活动列表已刷新，共 " + activities.length + " 个活动"
                    statusText.color = "#1565C0"

                    console.log("GET_ACTIVITIES 响应:",
                                activities.length, "个活动已灌入列表")
                } else {
                    statusText.text  = "活动列表拉取失败: " + (data.message || "未知错误")
                    statusText.color = "#C62828"
                }
                return
            }

            // ============================================================
            // 链路 B：CONFIRM_ASSIGN 录用落盘响应
            // ============================================================
            var isAssignResp = (action === "CONFIRM_ASSIGN")
                            || (data.action === "CONFIRM_ASSIGN")

            if (isAssignResp) {
                restoreAssignBtn()

                if (data.status === "ok" || data.code === 0) {
                    statusText.text  = "排班成功！已成功批量录用落盘并计入 schedules"
                    statusText.color = "#2E7D32"
                    memberModel.clear()
                    rawAvailableMembers = []
                    console.log("CONFIRM_ASSIGN 成功，列表已清空")
                } else {
                    statusText.text  = "录用落盘失败: " + (data.message || "未知错误")
                    statusText.color = "#C62828"
                    console.log("CONFIRM_ASSIGN 失败:", data.message)
                }
                return
            }

            // ============================================================
            // 链路 C：ADD_ACTIVITY 添加活动响应
            // ============================================================
            var isAddActivityResp = (action === "ADD_ACTIVITY")
                                 || (data.action === "ADD_ACTIVITY")

            if (isAddActivityResp) {
                addActivityDialog.resetForm()
                addActivityDialog.close()

                if (data.status === "ok" || data.code === 0) {
                    statusText.text  = "新活动已发布，正在刷新列表…"
                    statusText.color = "#2E7D32"
                    triggerFetchActivities()
                    console.log("ADD_ACTIVITY 成功，已触发活动列表刷新")
                } else {
                    statusText.text  = "活动发布失败: " + (data.message || "未知错误")
                    statusText.color = "#C62828"
                }
                return
            }

            // ============================================================
            // 链路 D：FILTER_AVAILABLE_MEMBERS 筛选响应
            // ============================================================
            var isFilterResp = (action === "FILTER_AVAILABLE_MEMBERS")
                            || (data.action === "FILTER_AVAILABLE_MEMBERS")

            if (isFilterResp) {
                if (data.status === "ok" && data.data && data.data.members) {
                    var members = data.data.members

                    if (!Array.isArray(members)) {
                        console.warn("FILTER_AVAILABLE_MEMBERS: members is not an array")
                        return
                    }

                    rawAvailableMembers = members
                    applyLocalSchedulingFilters()

                    statusText.text  = "筛选完成，共 " + members.length + " 人"
                    statusText.color = "#2E7D32"

                    console.log("FILTER_AVAILABLE_MEMBERS 响应:",
                                members.length, "名候选人")
                } else {
                    statusText.text  = "筛选失败: " + (data.message || "未知错误")
                    statusText.color = "#C62828"
                }
                return
            }

            // ============================================================
            // 链路 E：BATCH_ASSIGN_MEMBERS 排班透视批量征召落盘响应
            // ============================================================
            var isBatchAssignResp = (action === "BATCH_ASSIGN_MEMBERS")
                                 || (data.action === "BATCH_ASSIGN_MEMBERS")

            if (isBatchAssignResp) {
                if (data.status === "ok" || data.code === 0) {
                    statusText.text  = "一键征召落盘成功！已批量录用 "
                              + (data.data ? (data.data.assigned_count || "?") : "?")
                              + " 人至当前活动"
                    statusText.color = "#2E7D32"
                    console.log("BATCH_ASSIGN_MEMBERS 成功:", data.data)
                    triggerFetchActivities()
                } else {
                    statusText.text  = "批量征召失败: " + (data.message || "未知错误")
                    statusText.color = "#C62828"
                    console.log("BATCH_ASSIGN_MEMBERS 失败:", data.message)
                }
                return
            }

            // ============================================================
            // 链路 F：APPLY_ACTIVITY 申请参与响应
            // ============================================================
            var isApplyResp = (action === "APPLY_ACTIVITY")
                           || (data.action === "APPLY_ACTIVITY")

            if (isApplyResp) {
                if (data.status === "ok" || data.code === 0) {
                    memberStatusText.text  = "申请成功！您已报名参与该活动"
                    memberStatusText.color = "#2E7D32"
                } else {
                    memberStatusText.text  = "申请失败: " + (data.message || "未知错误")
                    memberStatusText.color = "#C62828"
                }
                return
            }

            // ============================================================
            // 链路 F：LEAVE_ACTIVITY 请假/取消申请响应
            // ============================================================
            var isLeaveResp = (action === "LEAVE_ACTIVITY")
                           || (data.action === "LEAVE_ACTIVITY")

            if (isLeaveResp) {
                if (data.status === "ok" || data.code === 0) {
                    memberStatusText.text  = "已提交请假/取消申请"
                    memberStatusText.color = "#2E7D32"
                } else {
                    memberStatusText.text  = "请假失败: " + (data.message || "未知错误")
                    memberStatusText.color = "#C62828"
                }
                return
            }
        }

        // ---- 连接状态变化 → 自动拉取活动列表 ----
        function onConnectedChanged(connected) {
            if (connected) {
                triggerFetchActivities()
            }
        }

        // ---- 网络错误 ----
        function onConnectionError(errorString) {
            if (memberModel.count === 0) {
                statusText.text  = "网络错误: " + errorString
                statusText.color = "#C62828"
            }
            restoreAssignBtn()
        }
    }
}
