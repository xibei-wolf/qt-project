import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../js/EventRecurrenceLogic.js" as EventLogic

// ============================================================================
// AddActivityDialog.qml — 发布新活动弹窗 v3（队长/老师专用）
//
// 重构要点：
//   1. 废弃手动 SpinBox 输入日期 → 改用可视化日历点选
//   2. 新增 RecurrenceModel：单次 / 每周重复 / 每两周重复
//   3. 前端直接提取 YYYY-MM-DD 发送后端，不再计算 time_mask
//   4. 日历自动高亮已选日期，展示将生成的 EventInstance 列表
//
// ADD_ACTIVITY 请求体：
//   title, description, location
//   start_date, end_date: "YYYY-MM-DD"
//   start_time, end_time: "HH:MM:SS"
//   period_type: 0=单次 / 1=每周 / 2=每两周
//   organizer_id, department_id
//
// 约束：全文件禁止 String.arg()，字符串拼接一律用原生 +
// ============================================================================

Dialog {
    id: root
    title: "发布新活动"
    modal: true
    width: 560
    height: 700
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // ====================================================================
    // 状态
    // ====================================================================
    property date   selectedDate: new Date()       // 日历当前高亮日期
    property int    calendarYear:  new Date().getFullYear()
    property int    calendarMonth: new Date().getMonth() + 1  // 1-12

    // ====================================================================
    // 工具
    // ====================================================================
    function monthName(m) {
        var names = ["","一月","二月","三月","四月","五月","六月",
                     "七月","八月","九月","十月","十一月","十二月"]
        return names[m] || ""
    }

    function selectedDateText() {
        return EventLogic.formatDate(selectedDate) + "  "
             + EventLogic.DAY_LABELS[EventLogic.dayOfWeek(selectedDate)]
    }

    // ---- 刷新日历网格 ----
    property var calendarGrid: EventLogic.buildCalendarGrid(calendarYear, calendarMonth)

    function refreshGrid() {
        calendarGrid = EventLogic.buildCalendarGrid(calendarYear, calendarMonth)
    }

    function goPrevMonth() {
        if (calendarMonth === 1) {
            calendarMonth = 12
            calendarYear--
        } else {
            calendarMonth--
        }
        refreshGrid()
    }
    function goNextMonth() {
        if (calendarMonth === 12) {
            calendarMonth = 1
            calendarYear++
        } else {
            calendarMonth++
        }
        refreshGrid()
    }

    // ---- 预览实例列表（用于底部提示） ----
    function previewInstances() {
        var h1 = startHourSpin.value, m1 = startMinSpin.value
        var h2 = endHourSpin.value,   m2 = endMinSpin.value
        var dur = EventLogic.durationHours(h1, m1, h2, m2)
        if (dur <= 0) return []

        var endD = (recurCombo.currentValue === EventLogic.RECUR_ONCE)
                   ? selectedDate
                   : EventLogic.makeDate(endYearSpin.value, endMonthSpin.value, endDaySpin.value)

        return EventLogic.generateInstances(
            selectedDate, endD, h1, m1, h2, m2, recurCombo.currentValue)
    }

    function updateInstancePreview() {
        var list = previewInstances()
        if (list.length === 0) {
            instancePreviewText.text = "（请设置有效的时间范围）"
            return
        }
        if (list.length === 1) {
            instancePreviewText.text = "将生成 1 场活动："
                    + list[0].date + " " + list[0].start_time + "-" + list[0].end_time
            return
        }
        instancePreviewText.text = "将生成 " + list.length + " 场活动："
                + list[0].date + " … " + list[list.length-1].date
                + " 每次 " + list[0].start_time + "-" + list[0].end_time
    }

    // ====================================================================
    // 发布
    // ====================================================================
    function doPublish() {
        var title = titleField.text.trim()
        if (title === "") { errorText.text = "请输入活动名称"; return }
        if (locationField.text.trim() === "") { errorText.text = "请输入活动地点"; return }

        var h1 = startHourSpin.value, m1 = startMinSpin.value
        var h2 = endHourSpin.value,   m2 = endMinSpin.value
        var dur = EventLogic.durationHours(h1, m1, h2, m2)
        if (dur <= 0) { errorText.text = "结束时间必须晚于开始时间"; return }

        var recurrence = recurCombo.currentValue
        var startDateStr = EventLogic.formatDate(selectedDate)

        var endDateStr
        if (recurrence === EventLogic.RECUR_ONCE) {
            endDateStr = startDateStr
        } else {
            endDateStr = EventLogic.formatDate(
                EventLogic.makeDate(endYearSpin.value, endMonthSpin.value, endDaySpin.value))
        }

        publishBtn.enabled = false
        publishBtn.text = "发布中…"
        errorText.text = ""

        NetworkClient.sendRequest("ADD_ACTIVITY", {
            "title":         title,
            "description":   descField.text.trim(),
            "location":      locationField.text.trim(),
            "start_date":    startDateStr,
            "end_date":      endDateStr,
            "start_time":    EventLogic.formatTime(h1, m1),
            "end_time":      EventLogic.formatTime(h2, m2),
            "period_type":   EventLogic.periodType(recurrence),
            "organizer_id":  mainWindow.currentUser.user_id,
            "department_id": mainWindow.currentUser.department_id || 1
        })
    }

    // ---- 重置表单 ----
    function resetForm() {
        titleField.text = ""
        locationField.text = ""
        descField.text = ""

        var now = new Date()
        selectedDate = now
        calendarYear = now.getFullYear()
        calendarMonth = now.getMonth() + 1
        refreshGrid()

        endYearSpin.value = now.getFullYear()
        endMonthSpin.value = now.getMonth() + 1
        endDaySpin.value = now.getDate()

        startHourSpin.value = 14
        startMinSpin.value = 0
        endHourSpin.value = 16
        endMinSpin.value = 30
        recurCombo.currentIndex = 0

        publishBtn.enabled = true
        publishBtn.text = "确认发布活动"
        errorText.text = ""
        updateInstancePreview()
    }

    // ====================================================================
    // UI
    // ====================================================================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // ---- 名称 + 地点 + 简介 ----
        RowLayout {
            spacing: 6
            Text { text: "名称："; font.pixelSize: 13; Layout.preferredWidth: 40 }
            TextField {
                id: titleField
                Layout.fillWidth: true
                placeholderText: "例：周三下午 支教活动"
                font.pixelSize: 13
            }
        }
        RowLayout {
            spacing: 6
            Text { text: "地点："; font.pixelSize: 13; Layout.preferredWidth: 40 }
            TextField {
                id: locationField
                Layout.fillWidth: true
                placeholderText: "例：云教室"
                font.pixelSize: 13
            }
        }
        RowLayout {
            spacing: 6
            Text { text: "简介："; font.pixelSize: 13; Layout.preferredWidth: 40 }
            TextField {
                id: descField
                Layout.fillWidth: true
                placeholderText: "活动简介（可选）"
                font.pixelSize: 13
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#E0E0E0" }

        // ---- 已选日期回显 ----
        Rectangle {
            Layout.fillWidth: true; height: 36; radius: 4
            color: "#E3F2FD"; border { color: "#90CAF9"; width: 1 }
            RowLayout {
                anchors.centerIn: parent; spacing: 8
                Text {
                    text: "已选活动日期："
                    font.pixelSize: 13; font.bold: true; color: "#1565C0"
                }
                Text {
                    text: selectedDateText()
                    font.pixelSize: 14; font.bold: true; color: "#0D47A1"
                }
            }
        }

        // ---- 日历 ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            // 左箭头
            Button {
                text: "◀"
                Layout.preferredWidth: 32; Layout.preferredHeight: 32
                onClicked: goPrevMonth()
                background: Rectangle { color: "transparent" }
                contentItem: Text {
                    text: parent.text; font.pixelSize: 16; color: "#1565C0"
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                // 月份标题
                Text {
                    text: calendarYear + " 年 " + monthName(calendarMonth)
                    font.pixelSize: 15; font.bold: true
                    color: "#1565C0"
                    Layout.alignment: Qt.AlignHCenter
                }

                // 星期表头
                Row {
                    spacing: 0
                    Layout.fillWidth: true
                    Repeater {
                        model: ["一","二","三","四","五","六","日"]
                        Rectangle {
                            width: Math.floor((root.width - 100) / 7)
                            height: 24; color: "#E3F2FD"
                            Text {
                                anchors.centerIn: parent
                                text: modelData; font.pixelSize: 11
                                font.bold: true; color: "#1565C0"
                            }
                        }
                    }
                }

                // 日期网格 (6行 × 7列)
                Grid {
                    columns: 7
                    spacing: 1
                    Layout.fillWidth: true
                    Repeater {
                        model: 42  // 固定 42 格
                        Rectangle {
                            width: Math.floor((root.width - 100) / 7)
                            height: 34
                            radius: 3
                            color: {
                                var cell = calendarGrid[index]
                                if (!cell) return "transparent"
                                if (EventLogic.isSameDay(cell.date, selectedDate))
                                    return "#1565C0"  // 选中
                                if (!cell.isCurrentMonth)
                                    return "#F5F5F5"  // 非当月
                                return "#FFFFFF"
                            }
                            border {
                                color: {
                                    var cell = calendarGrid[index]
                                    if (cell && EventLogic.isSameDay(cell.date, new Date()))
                                        return "#E65100"  // 今天
                                    return "#E0E0E0"
                                }
                                width: {
                                    var cell = calendarGrid[index]
                                    return (cell && EventLogic.isSameDay(cell.date, new Date())) ? 2 : 0.5
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: {
                                    var cell = calendarGrid[index]
                                    return cell ? cell.day : ""
                                }
                                font.pixelSize: 12
                                font.bold: {
                                    var cell = calendarGrid[index]
                                    return cell && EventLogic.isSameDay(cell.date, selectedDate)
                                }
                                color: {
                                    var cell = calendarGrid[index]
                                    if (!cell) return "#CCC"
                                    if (EventLogic.isSameDay(cell.date, selectedDate))
                                        return "#FFFFFF"
                                    if (!cell.isCurrentMonth) return "#CCC"
                                    return "#333333"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var cell = calendarGrid[index]
                                    if (cell && cell.isCurrentMonth) {
                                        selectedDate = cell.date
                                        updateInstancePreview()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 右箭头
            Button {
                text: "▶"
                Layout.preferredWidth: 32; Layout.preferredHeight: 32
                onClicked: goNextMonth()
                background: Rectangle { color: "transparent" }
                contentItem: Text {
                    text: parent.text; font.pixelSize: 16; color: "#1565C0"
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#E0E0E0" }

        // ---- 活动时间 ----
        Text {
            text: "活动时间（7:00-22:00）："
            font.pixelSize: 13; font.bold: true; color: "#E65100"
        }

        RowLayout {
            spacing: 6
            Text { text: "开始："; font.pixelSize: 12; Layout.preferredWidth: 40 }
            SpinBox {
                id: startHourSpin; from: 7; to: 21; value: 14
                Layout.preferredWidth: 55; editable: true
                onValueChanged: updateInstancePreview()
            }
            Text { text: "时"; font.pixelSize: 11; color: "#888" }
            SpinBox {
                id: startMinSpin; from: 0; to: 30; stepSize: 30; value: 0
                Layout.preferredWidth: 55; editable: true
                onValueChanged: updateInstancePreview()
            }
            Text { text: "分"; font.pixelSize: 11; color: "#888" }

            Item { Layout.preferredWidth: 16 }

            Text { text: "结束："; font.pixelSize: 12 }
            SpinBox {
                id: endHourSpin; from: 8; to: 22; value: 16
                Layout.preferredWidth: 55; editable: true
                onValueChanged: updateInstancePreview()
            }
            Text { text: "时"; font.pixelSize: 11; color: "#888" }
            SpinBox {
                id: endMinSpin; from: 0; to: 30; stepSize: 30; value: 30
                Layout.preferredWidth: 55; editable: true
                onValueChanged: updateInstancePreview()
            }
            Text { text: "分"; font.pixelSize: 11; color: "#888" }
        }

        // ---- 重复规则 ----
        Text {
            text: "重复规则："
            font.pixelSize: 13; font.bold: true; color: "#E65100"
        }

        RowLayout {
            spacing: 8
            ComboBox {
                id: recurCombo
                Layout.preferredWidth: 150
                textRole: "label"
                valueRole: "value"
                model: [
                    { label: "单次活动",       value: EventLogic.RECUR_ONCE },
                    { label: "每周重复",       value: EventLogic.RECUR_WEEKLY },
                    { label: "每两周重复",     value: EventLogic.RECUR_BIWEEKLY }
                ]
                onCurrentIndexChanged: updateInstancePreview()
            }

            Text {
                text: recurCombo.currentValue !== EventLogic.RECUR_ONCE
                      ? "截止日期：" : ""
                font.pixelSize: 12; color: "#555"
                visible: recurCombo.currentValue !== EventLogic.RECUR_ONCE
            }

            SpinBox {
                id: endYearSpin; from: 2024; to: 2030
                value: new Date().getFullYear()
                Layout.preferredWidth: 60; editable: true
                visible: recurCombo.currentValue !== EventLogic.RECUR_ONCE
                onValueChanged: updateInstancePreview()
            }
            Text {
                text: "-"; font.pixelSize: 13
                visible: recurCombo.currentValue !== EventLogic.RECUR_ONCE
            }
            SpinBox {
                id: endMonthSpin; from: 1; to: 12
                value: new Date().getMonth() + 1
                Layout.preferredWidth: 45; editable: true
                visible: recurCombo.currentValue !== EventLogic.RECUR_ONCE
                onValueChanged: updateInstancePreview()
            }
            Text {
                text: "-"; font.pixelSize: 13
                visible: recurCombo.currentValue !== EventLogic.RECUR_ONCE
            }
            SpinBox {
                id: endDaySpin; from: 1; to: 31
                value: new Date().getDate()
                Layout.preferredWidth: 45; editable: true
                visible: recurCombo.currentValue !== EventLogic.RECUR_ONCE
                onValueChanged: updateInstancePreview()
            }
        }

        // ---- 实例预览 ----
        Rectangle {
            Layout.fillWidth: true; height: 40; radius: 4
            color: "#F3E5F5"; border { color: "#CE93D8"; width: 0.5 }
            Text {
                id: instancePreviewText
                anchors.centerIn: parent
                text: ""
                font.pixelSize: 11; color: "#6A1B9A"
                elide: Text.ElideRight
                width: parent.width - 16
            }
        }

        // ---- 错误提示 ----
        Text {
            id: errorText
            font.pixelSize: 12; color: "#C62828"
            visible: text !== ""
        }

        // ---- 发布按钮 ----
        Button {
            id: publishBtn
            text: "确认发布活动"
            Layout.fillWidth: true; Layout.preferredHeight: 42
            onClicked: doPublish()

            background: Rectangle {
                color: publishBtn.enabled ? "#1565C0" : "#BDBDBD"; radius: 4
            }
            contentItem: Text {
                text: publishBtn.text; color: "white"
                font.pixelSize: 14; font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // ---- 初始化 ----
    Component.onCompleted: {
        refreshGrid()
        updateInstancePreview()
    }

    // ---- 网络响应 ----
    Connections {
        target: NetworkClient
        function onResponseReceived(action, data) {
            var isAddResp = (action === "ADD_ACTIVITY")
                         || (data.action === "ADD_ACTIVITY")
            if (!isAddResp) return

            publishBtn.enabled = true
            publishBtn.text = "确认发布活动"

            if (data.status === "ok" || data.code === 0) {
                errorText.text = ""
                resetForm()
                console.log("ADD_ACTIVITY 成功，表单已重置")
            } else {
                errorText.text = "发布失败: " + (data.message || "未知错误")
            }
        }
    }
}
