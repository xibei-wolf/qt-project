import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../js/EventRecurrenceLogic.js" as EventLogic

// ============================================================================
// ActivitySchedulerDialog.qml — 活动排班 · 多维空闲率全瞻透视 v3
//
// GET_TIME_ANALYTICS 请求体（与后端 Muduo 协议对齐）：
//   { target_week: int, day_of_week: int (1=Mon), time_mask: uint32 }
//
// 功能：
//   1. 可视化日历点选日期 + 时间范围选择器
//   2. TabView 结果展示：空闲名单 / 忙碌名单
//   3. 部门 + 性别 + 角色多维级联筛选
//   4. 一键征召：暂存候选人到本地队列，通知父视图
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

    // ---- 日历状态 ----
    property date   selectedDate: new Date()
    property int    calendarYear:  new Date().getFullYear()
    property int    calendarMonth: new Date().getMonth() + 1

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

    function genderLabel(g) {
        switch (g) {
            case 1: return "男生 👦"
            case 2: return "女生 👧"
            default: return "未知 ⚪"
        }
    }

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

    function monthName(m) {
        var names = ["","一月","二月","三月","四月","五月","六月",
                     "七月","八月","九月","十月","十一月","十二月"]
        return names[m] || ""
    }

    // ---- 日历网格 ----
    property var calendarGrid: EventLogic.buildCalendarGrid(calendarYear, calendarMonth)

    function refreshGrid() {
        calendarGrid = EventLogic.buildCalendarGrid(calendarYear, calendarMonth)
    }
    function goPrevMonth() {
        if (calendarMonth === 1) { calendarMonth = 12; calendarYear-- }
        else { calendarMonth-- }
        refreshGrid()
    }
    function goNextMonth() {
        if (calendarMonth === 12) { calendarMonth = 1; calendarYear++ }
        else { calendarMonth++ }
        refreshGrid()
    }

    // ---- 空闲/忙碌成员原始缓存 ----
    ListModel { id: freeMemberModel }
    ListModel { id: busyMemberModel }

    // ---- 前端多维筛选器 ----
    property string filterDept: "全部部门"
    property string filterGender: "全部性别"
    property int filterRole: 0

    // ---- 过滤器数据源 ----
    ListModel {
        id: deptFilterModel
        Component.onCompleted: {
            append({ name: "全部部门" }); append({ name: "策划部" })
            append({ name: "外联部" });   append({ name: "办公室" })
            append({ name: "宣传部" });   append({ name: "云教室" })
        }
    }
    ListModel {
        id: genderFilterModel
        Component.onCompleted: {
            append({ name: "全部性别", value: -1 })
            append({ name: "男生 👦",   value: 1  })
            append({ name: "女生 👧",   value: 2  })
            append({ name: "未知 ⚪",   value: 0  })
        }
    }
    ListModel {
        id: roleFilterModel
        Component.onCompleted: {
            append({ name: "全部角色", rid: 0 })
            append({ name: "队长",     rid: 20 })
            append({ name: "部长",     rid: 30 })
            append({ name: "普通队员", rid: 40 })
        }
    }

    function applyFilters(sourceModel, targetModel) {
        targetModel.clear()
        for (var i = 0; i < sourceModel.count; i++) {
            var m = sourceModel.get(i)
            var deptMatch = (filterDept === "全部部门" || m.dept_name === filterDept)
            var genderMatch = (filterGender === "全部性别")
                           || (filterGender === "男生 👦" && m.gender === 1)
                           || (filterGender === "女生 👧" && m.gender === 2)
                           || (filterGender === "未知 ⚪" && (m.gender === 0 || !m.gender))
            var roleMatch = (filterRole === 0 || m.role_id === filterRole)
            if (deptMatch && genderMatch && roleMatch) targetModel.append(m)
        }
    }

    function isStaged(memberId) {
        for (var i = 0; i < stagedMembers.length; i++)
            if (stagedMembers[i].user_id === memberId) return true
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
        for (var i = 0; i < stagedMembers.length; i++)
            ids.push(stagedMembers[i].user_id)
        root.membersStaged(ids)
        stagedMembers = ([])
        scanStatusText.text = "已通知父视图接收 " + ids.length + " 名征召成员"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ================================================================
        // 上半区：扫描参数（日历 + 时间）
        // ================================================================
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // 日历
            ColumnLayout {
                Layout.preferredWidth: 280
                spacing: 2

                // 月份导航
                RowLayout {
                    Layout.fillWidth: true
                    Button {
                        text: "◀"; Layout.preferredWidth: 28; Layout.preferredHeight: 28
                        onClicked: goPrevMonth()
                        background: Rectangle { color: "transparent" }
                        contentItem: Text { text: parent.text; font.pixelSize: 14; color: "#3F51B5"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                    Text {
                        text: calendarYear + " " + monthName(calendarMonth)
                        font.pixelSize: 13; font.bold: true; color: "#3F51B5"
                        Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                    }
                    Button {
                        text: "▶"; Layout.preferredWidth: 28; Layout.preferredHeight: 28
                        onClicked: goNextMonth()
                        background: Rectangle { color: "transparent" }
                        contentItem: Text { text: parent.text; font.pixelSize: 14; color: "#3F51B5"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                }

                // 星期表头
                Row {
                    spacing: 0; Layout.fillWidth: true
                    Repeater {
                        model: ["一","二","三","四","五","六","日"]
                        Rectangle {
                            width: 40; height: 20; color: "#E8EAF6"
                            Text {
                                anchors.centerIn: parent
                                text: modelData; font.pixelSize: 10; font.bold: true; color: "#3949AB"
                            }
                        }
                    }
                }

                // 日期网格
                Grid {
                    columns: 7; spacing: 1
                    Repeater {
                        model: 42
                        Rectangle {
                            width: 39; height: 28; radius: 2
                            color: {
                                var cell = calendarGrid[index]
                                if (!cell) return "transparent"
                                if (EventLogic.isSameDay(cell.date, selectedDate)) return "#3F51B5"
                                if (!cell.isCurrentMonth) return "#F5F5F5"
                                return "#FFFFFF"
                            }
                            Text {
                                anchors.centerIn: parent
                                text: { var cell = calendarGrid[index]; return cell ? cell.day : "" }
                                font.pixelSize: 11
                                color: {
                                    var cell = calendarGrid[index]
                                    if (!cell) return "#CCC"
                                    if (EventLogic.isSameDay(cell.date, selectedDate)) return "#FFFFFF"
                                    if (!cell.isCurrentMonth) return "#CCC"
                                    return "#333333"
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var cell = calendarGrid[index]
                                    if (cell && cell.isCurrentMonth) selectedDate = cell.date
                                }
                            }
                        }
                    }
                }
            }

            // 右侧：已选日期 + 时间范围
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true; height: 36; radius: 4
                    color: "#E8EAF6"; border { color: "#9FA8DA"; width: 1 }
                    Text {
                        anchors.centerIn: parent
                        text: "已选：" + EventLogic.formatDate(selectedDate)
                              + "  " + EventLogic.DAY_LABELS[EventLogic.dayOfWeek(selectedDate)]
                        font.pixelSize: 13; font.bold: true; color: "#283593"
                    }
                }

                Text {
                    text: "时间范围（7:00-22:00）："
                    font.pixelSize: 12; font.bold: true; color: "#E65100"
                }

                RowLayout {
                    spacing: 6
                    Text { text: "开始"; font.pixelSize: 12; Layout.preferredWidth: 30 }
                    SpinBox {
                        id: startHourSpin; from: 7; to: 21; value: 14
                        Layout.preferredWidth: 55; editable: true
                    }
                    Text { text: ":"; font.pixelSize: 14 }
                    SpinBox {
                        id: startMinSpin; from: 0; to: 30; stepSize: 30; value: 0
                        Layout.preferredWidth: 55; editable: true
                    }
                }
                RowLayout {
                    spacing: 6
                    Text { text: "结束"; font.pixelSize: 12; Layout.preferredWidth: 30 }
                    SpinBox {
                        id: endHourSpin; from: 8; to: 22; value: 16
                        Layout.preferredWidth: 55; editable: true
                    }
                    Text { text: ":"; font.pixelSize: 14 }
                    SpinBox {
                        id: endMinSpin; from: 0; to: 30; stepSize: 30; value: 30
                        Layout.preferredWidth: 55; editable: true
                    }
                }

                Item { Layout.fillHeight: true }

                Button {
                    id: scanBtn
                    text: "执行透视扫描"
                    Layout.preferredHeight: 34; Layout.fillWidth: true

                    onClicked: {
                        var h1 = startHourSpin.value, m1 = startMinSpin.value
                        var h2 = endHourSpin.value, m2 = endMinSpin.value
                        if (EventLogic.durationHours(h1, m1, h2, m2) <= 0) {
                            scanStatusText.text = "结束时间必须晚于开始时间"
                            return
                        }
                        scanBtn.enabled = false
                        scanBtn.text = "扫描中…"
                        scanStatusText.text = ""
                        stagedMembers = ([])

                        var dow = EventLogic.dayOfWeek(selectedDate)
                        var mask = EventLogic.calculateTimeMask(h1, m1, h2, m2)
                        var week = EventLogic.teachingWeek(selectedDate, EventLogic.TERM_START_DATE)

                        var payload = {
                            "target_week": week,
                            "day_of_week": dow,
                            "time_mask":   mask
                        }
                        console.log("发送 GET_TIME_ANALYTICS:", JSON.stringify(payload))
                        NetworkClient.sendRequest("GET_TIME_ANALYTICS", payload)
                    }

                    background: Rectangle {
                        color: scanBtn.enabled ? "#3F51B5" : "#BDBDBD"; radius: 4
                    }
                    contentItem: Text {
                        text: scanBtn.text; color: "white"; font.pixelSize: 13; font.bold: true
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        Text {
            id: scanStatusText
            font.pixelSize: 12; color: "#555555"; visible: text !== ""
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#E0E0E0" }

        // ---- 结果展示头 ----
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Text {
                text: "透视结果：共 " + (totalCountText.text || "0") + " 人"
                font.pixelSize: 13; font.bold: true; color: "#333333"
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "空闲 " + (freeCountText.text || "0") + " 人 ("
                      + (freeRateText.text || "0%") + ")"
                font.pixelSize: 13; color: "#2E7D32"; font.bold: true
            }
        }

        // ---- 过滤控制栏 ----
        RowLayout {
            Layout.fillWidth: true; spacing: 12
            Text { text: "部门："; font.pixelSize: 12 }
            ComboBox {
                id: deptFilterCombo; model: deptFilterModel; textRole: "name"
                Layout.preferredWidth: 100
                onCurrentTextChanged: {
                    filterDept = currentText
                    applyFilters(freeMemberModel, freeFilteredModel)
                    applyFilters(busyMemberModel, busyFilteredModel)
                }
            }
            Text { text: "性别："; font.pixelSize: 12 }
            ComboBox {
                id: genderFilterCombo; model: genderFilterModel; textRole: "name"
                Layout.preferredWidth: 100
                onCurrentTextChanged: {
                    filterGender = currentText
                    applyFilters(freeMemberModel, freeFilteredModel)
                    applyFilters(busyMemberModel, busyFilteredModel)
                }
            }
            Text { text: "角色："; font.pixelSize: 12 }
            ComboBox {
                id: roleFilterCombo; model: roleFilterModel; textRole: "name"
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

        ListModel { id: freeFilteredModel }
        ListModel { id: busyFilteredModel }

        TabBar {
            id: resultTabBar; Layout.fillWidth: true
            TabButton { text: "空闲名单 👍" }
            TabButton { text: "上课忙碌 📚" }
        }

        StackLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            currentIndex: resultTabBar.currentIndex

            // ===== Tab 0: 空闲名单 =====
            ColumnLayout {
                spacing: 0
                Rectangle {
                    Layout.fillWidth: true; height: 24; color: "#E8F5E9"
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 0
                        Text { text: "ID"; font.bold: true; Layout.preferredWidth: 55; font.pixelSize: 11 }
                        Text { text: "姓名"; font.bold: true; Layout.preferredWidth: 75; font.pixelSize: 11 }
                        Text { text: "学号"; font.bold: true; Layout.preferredWidth: 95; font.pixelSize: 11 }
                        Text { text: "部门"; font.bold: true; Layout.preferredWidth: 85; font.pixelSize: 11 }
                        Text { text: "角色"; font.bold: true; Layout.preferredWidth: 85; font.pixelSize: 11 }
                        Text { text: "性别"; font.bold: true; Layout.preferredWidth: 70; font.pixelSize: 11 }
                        Text { text: "志愿时长"; font.bold: true; Layout.preferredWidth: 70; font.pixelSize: 11 }
                        Text { text: "状态"; font.bold: true; Layout.preferredWidth: 90; font.pixelSize: 11 }
                        Item { Layout.fillWidth: true }
                    }
                }
                ListView {
                    id: freeListView; Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    model: freeFilteredModel
                    Label {
                        anchors.centerIn: parent
                        text: freeFilteredModel.count === 0 ? "没有匹配的空闲成员" : ""
                        color: "#999999"; font.pixelSize: 12
                    }
                    delegate: Rectangle {
                        width: freeListView.width; height: 36
                        color: index % 2 === 0 ? "#FAFAFA" : "#FFFFFF"
                        border { color: "#E0E0E0"; width: 0.5 }
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 0
                            Text { text: model.user_id || "-"; Layout.preferredWidth: 55; font.pixelSize: 11; font.family: "Courier New"; color: "#888888" }
                            Text { text: model.name || "-"; Layout.preferredWidth: 75; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight }
                            Text { text: model.student_id || "-"; Layout.preferredWidth: 95; font.pixelSize: 11; font.family: "Courier New"; color: "#555555"; elide: Text.ElideRight }
                            Text { text: model.dept_name || "-"; Layout.preferredWidth: 85; font.pixelSize: 11; color: "#555555"; elide: Text.ElideRight }
                            Text { text: roleLabel(model.role_id); Layout.preferredWidth: 85; font.pixelSize: 11; color: model.role_id <= 20 ? "#1565C0" : "#555555" }
                            Text { text: genderLabel(model.gender); Layout.preferredWidth: 70; font.pixelSize: 11 }
                            Text { text: (model.total_hours || 0) + "h"; Layout.preferredWidth: 70; font.pixelSize: 11; color: model.total_hours > 0 ? "#2E7D32" : "#9E9E9E" }
                            Text { text: "🍀 空闲"; Layout.preferredWidth: 90; font.pixelSize: 11; color: "#2E7D32" }
                            Item { Layout.fillWidth: true }
                            Button {
                                text: isStaged(model.user_id) ? "已暂存" : "征召"
                                Layout.preferredWidth: 60; Layout.preferredHeight: 26
                                onClicked: toggleStaged({ "user_id": model.user_id, "name": model.name, "dept_name": model.dept_name, "gender": model.gender, "role_id": model.role_id })
                                background: Rectangle { color: isStaged(model.user_id) ? "#9E9E9E" : "#2E7D32"; radius: 4 }
                                contentItem: Text { text: parent.text; color: "white"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                        }
                    }
                }
            }

            // ===== Tab 1: 忙碌名单 =====
            ColumnLayout {
                spacing: 0
                Rectangle {
                    Layout.fillWidth: true; height: 24; color: "#FFEBEE"
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 0
                        Text { text: "ID"; font.bold: true; Layout.preferredWidth: 55; font.pixelSize: 11 }
                        Text { text: "姓名"; font.bold: true; Layout.preferredWidth: 75; font.pixelSize: 11 }
                        Text { text: "学号"; font.bold: true; Layout.preferredWidth: 95; font.pixelSize: 11 }
                        Text { text: "部门"; font.bold: true; Layout.preferredWidth: 85; font.pixelSize: 11 }
                        Text { text: "角色"; font.bold: true; Layout.preferredWidth: 85; font.pixelSize: 11 }
                        Text { text: "性别"; font.bold: true; Layout.preferredWidth: 70; font.pixelSize: 11 }
                        Text { text: "志愿时长"; font.bold: true; Layout.preferredWidth: 70; font.pixelSize: 11 }
                        Text { text: "状态"; font.bold: true; Layout.preferredWidth: 90; font.pixelSize: 11 }
                        Item { Layout.fillWidth: true }
                    }
                }
                ListView {
                    id: busyListView; Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    model: busyFilteredModel
                    Label {
                        anchors.centerIn: parent
                        text: busyFilteredModel.count === 0 ? "无匹配的忙碌成员" : ""
                        color: "#999999"; font.pixelSize: 12
                    }
                    delegate: Rectangle {
                        width: busyListView.width; height: 36
                        color: index % 2 === 0 ? "#FAFAFA" : "#FFFFFF"
                        border { color: "#E0E0E0"; width: 0.5 }
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 0
                            Text { text: model.user_id || "-"; Layout.preferredWidth: 55; font.pixelSize: 11; font.family: "Courier New"; color: "#888888" }
                            Text { text: model.name || "-"; Layout.preferredWidth: 75; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight }
                            Text { text: model.student_id || "-"; Layout.preferredWidth: 95; font.pixelSize: 11; font.family: "Courier New"; color: "#555555"; elide: Text.ElideRight }
                            Text { text: model.dept_name || "-"; Layout.preferredWidth: 85; font.pixelSize: 11; color: "#555555"; elide: Text.ElideRight }
                            Text { text: roleLabel(model.role_id); Layout.preferredWidth: 85; font.pixelSize: 11; color: model.role_id <= 20 ? "#1565C0" : "#555555" }
                            Text { text: genderLabel(model.gender); Layout.preferredWidth: 70; font.pixelSize: 11 }
                            Text { text: (model.total_hours || 0) + "h"; Layout.preferredWidth: 70; font.pixelSize: 11; color: model.total_hours > 0 ? "#2E7D32" : "#9E9E9E" }
                            Text {
                                text: stateEmoji(model.current_state) + " " + stateLabel(model.current_state)
                                Layout.preferredWidth: 90; font.pixelSize: 11
                                color: model.current_state === "busy_activity" ? "#C62828" : "#F57F17"
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }
        }

        // ---- 底部暂存栏 ----
        Rectangle {
            Layout.fillWidth: true; height: 40; color: "#FFF8E1"; radius: 4
            visible: stagedMembers.length > 0
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 8
                Text {
                    text: "已暂存 " + stagedMembers.length + " 名候选人待征召"
                    font.pixelSize: 13; font.bold: true; color: "#F57C00"
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: "清空"; Layout.preferredHeight: 28
                    onClicked: { stagedMembers = ([]) }
                    background: Rectangle { color: "#E0E0E0"; radius: 4 }
                    contentItem: Text { text: parent.text; color: "#333333"; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                }
                Button {
                    text: "确认征召"; Layout.preferredHeight: 28
                    onClicked: confirmStaging()
                    background: Rectangle { color: "#E65100"; radius: 4 }
                    contentItem: Text { text: parent.text; color: "white"; font.pixelSize: 11; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                }
            }
        }
    }

    Text { id: totalCountText; text: "0"; visible: false }
    Text { id: freeCountText;  text: "0"; visible: false }
    Text { id: freeRateText;   text: "0%"; visible: false }

    Component.onCompleted: refreshGrid()

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
                    var itemF = freeMembers[i]
                    if (!itemF.hasOwnProperty("role_id")) itemF["role_id"] = 40
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
