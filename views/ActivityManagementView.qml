import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================================
// ActivityManagementView.qml — 活动管理看板（队长/老师专用）
//
// 功能：
//   1. GET_MANAGEMENT_ACTIVITIES 自动拉取活动列表（含 assigned_count, status）
//   2. 卡片式 ListView 展示：ID / 名称 / 周数 / 地点 / 状态 / 人数 / 录用进度
//   3. 行内操作：【📝 修改】弹出编辑弹窗 → UPDATE_ACTIVITY
//               【❌ 删除】二次确认弹窗 → DELETE_ACTIVITY
//               【✅ 完结结算】弹出结算面板 → COMPLETE_ACTIVITY（status != 3 可见）
//   4. 修改/删除/结算成功后自动刷新列表
//
// 活动状态语义：
//   status == 1 → 未开始
//   status == 2 → 进行中
//   status == 3 → 已完结
//
// 约束：全文件禁止 String.arg()，字符串拼接一律用原生 +
// ============================================================================

Item {
    id: root

    // ---- 数据模型 ----
    ListModel {
        id: activityMgmtModel
    }

    // ---- 结算面板成员模型 ----
    ListModel {
        id: settlementMemberModel
    }

    // ---- 当前正在编辑的活动 ID（-1 = 无）----
    property int editingActivityId: -1

    // ---- 结算中的活动信息 ----
    property int settlementActivityId: -1
    property string settlementActivityTitle: ""

    // ---- 活动状态映射 ----
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

    // ================================================================
    // 页面初始化
    // ================================================================
    Component.onCompleted: {
        fetchManagementActivities()
    }

    function fetchManagementActivities() {
        if (!NetworkClient.connected) {
            statusText.text = "未连接服务器，无法加载活动列表"
            statusText.color = "#C62828"
            return
        }
        statusText.text = "加载中…"
        statusText.color = "#F57C00"
        NetworkClient.sendRequest("GET_MANAGEMENT_ACTIVITIES", {})
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
                text: "⚙️ 活动管理看板"
                font.pixelSize: 20
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Button {
                text: "刷新列表"
                enabled: NetworkClient.connected
                onClicked: fetchManagementActivities()

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

                Text { text: "ID";       font.bold: true; Layout.preferredWidth: 40 }
                Text { text: "活动名称"; font.bold: true; Layout.preferredWidth: 180 }
                Text { text: "周数";     font.bold: true; Layout.preferredWidth: 50 }
                Text { text: "地点";     font.bold: true; Layout.preferredWidth: 70 }
                Text { text: "状态";     font.bold: true; Layout.preferredWidth: 80 }
                Text { text: "录用进度"; font.bold: true; Layout.preferredWidth: 90 }
                Item { Layout.fillWidth: true }
                Text { text: "操作";     font.bold: true; Layout.preferredWidth: 250 }
            }
        }

        // ---- 活动卡片列表 ----
        ListView {
            id: activityList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: activityMgmtModel
            spacing: 4

            Label {
                anchors.centerIn: parent
                text: activityMgmtModel.count === 0
                      ? "暂无活动数据 — 点击右上角「刷新列表」加载"
                      : ""
                color: "#999999"
                font.pixelSize: 13
            }

            delegate: Rectangle {
                width: activityList.width
                height: 56
                color: index % 2 === 0 ? "#FAFAFA" : "#FFFFFF"
                border { color: "#E0E0E0"; width: 0.5 }
                radius: 4

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    spacing: 0

                    // 活动 ID
                    Text {
                        text: model.activity_id || "-"
                        Layout.preferredWidth: 40
                        font.pixelSize: 12
                        font.family: "Courier New"
                        color: "#888888"
                    }

                    // 活动名称
                    Text {
                        text: model.title || "-"
                        Layout.preferredWidth: 180
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
                            text: "W" + (model.activity_week || 0)
                            font.pixelSize: 11
                            font.bold: true
                            color: "#1565C0"
                        }
                    }

                    // 地点
                    Text {
                        text: model.location || "-"
                        Layout.preferredWidth: 70
                        font.pixelSize: 12
                        color: "#555555"
                        elide: Text.ElideRight
                    }

                    // 状态徽章
                    Rectangle {
                        Layout.preferredWidth: 70; height: 24
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

                    // 录用进度
                    Rectangle {
                        Layout.preferredWidth: 86; height: 26
                        radius: 4
                        color: (model.assigned_count > 0) ? "#E8F5E9" : "#F5F5F5"

                        Text {
                            anchors.centerIn: parent
                            text: model.assigned_count + " / " + model.max_participants + " 人"
                            font.pixelSize: 12
                            font.bold: true
                            color: (model.assigned_count > 0) ? "#2E7D32" : "#9E9E9E"
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // 操作按钮组
                    RowLayout {
                        Layout.preferredWidth: 250
                        spacing: 6

                        // 📝 修改
                        Button {
                            text: "📝 修改"
                            onClicked: {
                                editingActivityId = model.activity_id
                                editTitleField.text = model.title || ""
                                editLocationField.text = model.location || ""
                                editMaxSpin.value = model.max_participants || 1
                                editErrorText.text = ""
                                editDialog.open()
                            }

                            background: Rectangle {
                                color: "#1565C0"
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

                        // ❌ 删除（仅未开始状态可删除；进行中/已完结锁死以防历史审计断裂）
                        Button {
                            text: "❌ 删除"
                            visible: model.status === 1
                            onClicked: {
                                editingActivityId = model.activity_id
                                deleteConfirmDialog.open()
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

                        // ✅ 完结结算（status != 3 时可见）
                        Button {
                            text: "✅ 完结结算"
                            visible: model.status !== 3

                            onClicked: {
                                settlementActivityId = model.activity_id
                                settlementActivityTitle = model.title || ""
                                settlementMemberModel.clear()
                                settlementStatusText.text = "正在加载该活动已录用成员…"
                                settlementStatusText.color = "#F57C00"
                                settlementSubmitBtn.enabled = true
                                settlementSubmitBtn.text = "确认结算并封存"

                                NetworkClient.sendRequest("GET_ASSIGNED_MEMBERS", {
                                    "activity_id": model.activity_id
                                })
                            }

                            background: Rectangle {
                                color: "#00897B"
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
            }
        }
    }

    // ====================================================================
    // 📝 修改活动弹窗
    // ====================================================================
    Dialog {
        id: editDialog
        title: "修改活动信息"
        modal: true
        width: 420
        height: 320
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            RowLayout {
                spacing: 8
                Text {
                    text: "名称："
                    font.pixelSize: 13
                    Layout.preferredWidth: 50
                }
                TextField {
                    id: editTitleField
                    Layout.fillWidth: true
                    font.pixelSize: 13
                }
            }

            RowLayout {
                spacing: 8
                Text {
                    text: "地点："
                    font.pixelSize: 13
                    Layout.preferredWidth: 50
                }
                TextField {
                    id: editLocationField
                    Layout.fillWidth: true
                    font.pixelSize: 13
                }
            }

            RowLayout {
                spacing: 8
                Text {
                    text: "人数上限："
                    font.pixelSize: 13
                    Layout.preferredWidth: 72
                }
                SpinBox {
                    id: editMaxSpin
                    from: 1
                    to: 200
                    editable: true
                    Layout.preferredWidth: 100
                }
            }

            Text {
                id: editErrorText
                font.pixelSize: 12
                color: "#C62828"
                visible: text !== ""
            }

            Button {
                id: editSaveBtn
                text: "保存修改"
                Layout.fillWidth: true
                Layout.preferredHeight: 40

                onClicked: {
                    var title = editTitleField.text.trim()
                    if (title === "") {
                        editErrorText.text = "活动名称不能为空"
                        return
                    }

                    editSaveBtn.enabled = false
                    editSaveBtn.text = "保存中…"
                    editErrorText.text = ""

                    NetworkClient.sendRequest("UPDATE_ACTIVITY", {
                        "activity_id":      editingActivityId,
                        "title":            title,
                        "location":         editLocationField.text.trim(),
                        "max_participants": editMaxSpin.value
                    })
                }

                background: Rectangle {
                    color: editSaveBtn.enabled ? "#1565C0" : "#BDBDBD"
                    radius: 4
                }
                contentItem: Text {
                    text: editSaveBtn.text
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
    // ❌ 删除确认弹窗
    // ====================================================================
    Dialog {
        id: deleteConfirmDialog
        title: "确认删除"
        modal: true
        width: 400
        height: 200
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        ColumnLayout {
            anchors.fill: parent
            spacing: 16

            Text {
                text: "确定要删除该活动及对应的所有录用分配记录吗？\n仅清除活动与成员录用关系，不影响成员个人课表。"
                font.pixelSize: 14
                color: "#333333"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Text {
                text: "此操作不可撤销。已完结活动禁止删除以保护审计记录。"
                font.pixelSize: 12
                color: "#C62828"
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                Button {
                    text: "取消"
                    onClicked: deleteConfirmDialog.close()

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
                    id: deleteConfirmBtn
                    text: "确定删除"

                    onClicked: {
                        deleteConfirmBtn.enabled = false
                        deleteConfirmBtn.text = "删除中…"

                        NetworkClient.sendRequest("DELETE_ACTIVITY", {
                            "activity_id": editingActivityId
                        })
                    }

                    background: Rectangle {
                        color: deleteConfirmBtn.enabled ? "#C62828" : "#BDBDBD"
                        radius: 4
                    }
                    contentItem: Text {
                        text: deleteConfirmBtn.text
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
    // ✅ 完结结算弹窗
    //
    // 工时 SpinBox 说明：
    //   Qt 6 SpinBox 的 textFromValue / valueFromText 是 C++ virtual 方法，
    //   不能在 QML 侧以 function 赋值覆写（赋值语句被静默忽略）。
    //   因此这里使用原生 SpinBox（整数 0~40，步长 1，→ 0h~20h）并搭配
    //   一个 Text label 显示小时数，彻底消除自定义 contentItem 导致的
    //   鼠标事件吞没和箭头无法点击问题。
    // ====================================================================

    Dialog {
        id: settlementDialog
        title: "完结结算 — " + settlementActivityTitle
        modal: true
        width: 520
        height: 480
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            // 状态提示
            Text {
                id: settlementStatusText
                text: settlementMemberModel.count > 0
                      ? "共 " + settlementMemberModel.count + " 名已录用成员，请确认出勤与工时"
                      : "暂无已录用成员数据"
                font.pixelSize: 12
                color: "#555555"
            }

            // 成员列表头
            Rectangle {
                Layout.fillWidth: true
                height: 30
                color: "#E8F5E9"
                radius: 4

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    spacing: 0

                    Text { text: "姓名"; font.bold: true; Layout.fillWidth: true }
                    Text { text: "出勤"; font.bold: true; Layout.preferredWidth: 60 }
                    Text { text: "工时(h)"; font.bold: true; Layout.preferredWidth: 110 }
                }
            }

            // 成员列表
            ListView {
                id: settlementMemberList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: settlementMemberModel
                spacing: 2

                delegate: Rectangle {
                    width: settlementMemberList.width
                    height: 40
                    color: index % 2 === 0 ? "#FAFAFA" : "#FFFFFF"
                    border { color: "#E0E0E0"; width: 0.5 }
                    radius: 2

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 0

                        // 成员姓名
                        Text {
                            text: model.name || "-"
                            Layout.fillWidth: true
                            font.pixelSize: 13
                            font.bold: true
                        }

                        // 出勤勾选（自动填充/清零工时）
                        CheckBox {
                            id: attendedCheck
                            checked: model.is_attended === 1
                            Layout.preferredWidth: 60
                            Layout.alignment: Qt.AlignHCenter
                            onCheckedChanged: {
                                settlementMemberModel.setProperty(index, "is_attended", checked ? 1 : 0)
                                if (!checked) {
                                    settlementMemberModel.setProperty(index, "duration_hours", 0.0)
                                    durationSpin.value = 0
                                } else {
                                    var defHours = model.default_duration_hours || 0.0
                                    settlementMemberModel.setProperty(index, "duration_hours", defHours)
                                    durationSpin.value = Math.round(defHours * 2)
                                }
                            }
                        }

                        // 工时：原生 SpinBox（int 0~40 → 0h~20h）+ 小时数 label
                        RowLayout {
                            Layout.preferredWidth: 110
                            spacing: 4

                            SpinBox {
                                id: durationSpin
                                from: 0
                                to: 40
                                stepSize: 1
                                editable: true
                                Layout.preferredWidth: 60

                                Component.onCompleted: {
                                    durationSpin.value = Math.round((model.duration_hours || 0) * 2)
                                }

                                onValueChanged: {
                                    var hours = value / 2.0
                                    if (model.duration_hours !== hours) {
                                        settlementMemberModel.setProperty(index, "duration_hours", hours)
                                    }
                                }
                            }

                            Text {
                                text: ((model.duration_hours || 0).toFixed(1) + "h")
                                Layout.preferredWidth: 40
                                font.pixelSize: 12
                                color: "#555555"
                                horizontalAlignment: Text.AlignLeft
                            }
                        }
                    }
                }
            }

            // 操作按钮行
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                Button {
                    text: "取消"
                    onClicked: settlementDialog.close()

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
                    id: settlementSubmitBtn
                    text: "确认结算并封存"

                    onClicked: {
                        var memberHours = []
                        for (var i = 0; i < settlementMemberModel.count; i++) {
                            var m = settlementMemberModel.get(i)
                            memberHours.push({
                                "user_id":  parseInt(m.user_id),
                                "duration": parseFloat(m.duration_hours || 0),
                                "attended": parseInt(m.is_attended !== undefined ? m.is_attended : 1)
                            })
                        }

                        settlementSubmitBtn.enabled = false
                        settlementSubmitBtn.text = "结算中…"

                        console.log("COMPLETE_ACTIVITY, activity_id=" + settlementActivityId
                                    + ", member_hours:", JSON.stringify(memberHours))

                        NetworkClient.sendRequest("COMPLETE_ACTIVITY", {
                            "activity_id": settlementActivityId,
                            "member_hours": memberHours
                        })
                    }

                    background: Rectangle {
                        color: settlementSubmitBtn.enabled ? "#2E7D32" : "#BDBDBD"
                        radius: 4
                    }
                    contentItem: Text {
                        text: settlementSubmitBtn.text
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
            // ---- 链路 A：GET_MANAGEMENT_ACTIVITIES ----
            var isMgmtResp = (action === "GET_MANAGEMENT_ACTIVITIES")
                          || (data.action === "GET_MANAGEMENT_ACTIVITIES")

            if (isMgmtResp) {
                if (data.status === "ok" && data.data && data.data.activities) {
                    var activities = data.data.activities

                    if (!Array.isArray(activities)) {
                        console.warn("GET_MANAGEMENT_ACTIVITIES: activities is not an array")
                        return
                    }

                    activityMgmtModel.clear()

                    for (var i = 0; i < activities.length; i++) {
                        var a = activities[i]
                        activityMgmtModel.append({
                            activity_id:      a.activity_id      || 0,
                            title:            a.title            || "",
                            activity_week:    a.activity_week    || 0,
                            location:         a.location         || "",
                            max_participants: a.max_participants || 0,
                            assigned_count:   a.assigned_count   || 0,
                            status:           a.status           || 1
                        })
                    }

                    statusText.text  = "已加载 " + activities.length + " 个活动"
                    statusText.color = "#2E7D32"
                    console.log("GET_MANAGEMENT_ACTIVITIES: " + activities.length + " 条记录")
                } else {
                    statusText.text  = "加载失败: " + (data.message || "未知错误")
                    statusText.color = "#C62828"
                }
                return
            }

            // ---- 链路 B：UPDATE_ACTIVITY ----
            var isUpdateResp = (action === "UPDATE_ACTIVITY")
                            || (data.action === "UPDATE_ACTIVITY")

            if (isUpdateResp) {
                editSaveBtn.enabled = true
                editSaveBtn.text = "保存修改"

                if (data.status === "ok" || data.code === 0) {
                    editDialog.close()
                    statusText.text  = "活动信息已更新，正在刷新…"
                    statusText.color = "#2E7D32"
                    fetchManagementActivities()
                } else {
                    editErrorText.text = "修改失败: " + (data.message || "未知错误")
                }
                return
            }

            // ---- 链路 C：DELETE_ACTIVITY ----
            var isDeleteResp = (action === "DELETE_ACTIVITY")
                            || (data.action === "DELETE_ACTIVITY")

            if (isDeleteResp) {
                deleteConfirmBtn.enabled = true
                deleteConfirmBtn.text = "确定删除"

                if (data.status === "ok" || data.code === 0) {
                    deleteConfirmDialog.close()
                    statusText.text  = "活动已删除，正在刷新列表…"
                    statusText.color = "#2E7D32"
                    fetchManagementActivities()
                } else {
                    statusText.text  = "删除失败: " + (data.message || "未知错误")
                    statusText.color = "#C62828"
                    deleteConfirmDialog.close()
                }
                return
            }

            // ---- 链路 D：GET_ASSIGNED_MEMBERS 获取已录用成员列表 ----
            var isGetAssignedResp = (action === "GET_ASSIGNED_MEMBERS")
                                 || (data.action === "GET_ASSIGNED_MEMBERS")

            if (isGetAssignedResp) {
                if (data.status === "ok" && data.data && data.data.members) {
                    var assignedMembers = data.data.members

                    if (!Array.isArray(assignedMembers)) {
                        console.warn("GET_ASSIGNED_MEMBERS: members is not an array")
                        return
                    }

                    settlementMemberModel.clear()

                    for (var j = 0; j < assignedMembers.length; j++) {
                        var m = assignedMembers[j]
                        var defDur = m.duration_hours || 0.0
                        settlementMemberModel.append({
                            "user_id":               m.user_id || m.id || 0,
                            "name":                  m.name || "",
                            "is_attended":           1,
                            "duration_hours":        defDur,
                            "default_duration_hours": defDur
                        })
                    }

                    settlementStatusText.text = "共 " + assignedMembers.length + " 名已录用成员，请确认出勤与工时"
                    settlementStatusText.color = "#555555"
                    settlementDialog.open()

                    console.log("GET_ASSIGNED_MEMBERS: " + assignedMembers.length + " 人")
                } else {
                    settlementStatusText.text = "加载成员失败: " + (data.message || "未知错误")
                    settlementStatusText.color = "#C62828"
                    settlementDialog.open()
                }
                return
            }

            // ---- 链路 E：COMPLETE_ACTIVITY 完结结算响应 ----
            var isCompleteResp = (action === "COMPLETE_ACTIVITY")
                              || (data.action === "COMPLETE_ACTIVITY")

            if (isCompleteResp) {
                settlementSubmitBtn.enabled = true
                settlementSubmitBtn.text = "确认结算并封存"

                if (data.status === "ok" || data.code === 0) {
                    settlementDialog.close()
                    settlementMemberModel.clear()
                    statusText.text  = "活动已完结结算！正在刷新列表…"
                    statusText.color = "#2E7D32"
                    fetchManagementActivities()
                    console.log("COMPLETE_ACTIVITY 成功")
                } else {
                    settlementStatusText.text  = "结算失败: " + (data.message || "未知错误")
                    settlementStatusText.color = "#C62828"
                    console.log("COMPLETE_ACTIVITY 失败:", data.message)
                }
                return
            }

            // ---- 链路 F：LOGIN 成功 → 自动拉取活动列表 ----
            var isLoginResp = (action === "LOGIN" || data.action === "LOGIN")
            if (isLoginResp && (data.status === "ok" || data.code === 0) && data.data) {
                statusText.text = "加载中…"
                statusText.color = "#F57C00"
                NetworkClient.sendRequest("GET_MANAGEMENT_ACTIVITIES", {})
                return
            }
        }

        // ---- 连接建立后自动拉取 ----
        function onConnectedChanged(connected) {
            if (connected && activityMgmtModel.count === 0) {
                fetchManagementActivities()
            }
        }
    }
}
