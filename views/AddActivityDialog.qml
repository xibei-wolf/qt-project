import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================================
// AddActivityDialog.qml — 发布新活动弹窗（队长/老师专用）
//
// 功能：
//   1. 表单输入：活动名称、地点、简介、活动周数
//   2. 5×6 课表矩阵 → 自动计算 time_mask（day*6+period 编码，30-bit）
//   3. 发送 ADD_ACTIVITY 请求，organizer_id 取自 mainWindow.currentUser.user_id
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

    // ---- 5天 × 6节 时段选择模型（30-bit mask） ----
    ListModel {
        id: timeGridModel
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

    // ---- 计算位图掩码 ----
    function computeTimeMask() {
        var mask = 0
        for (var i = 0; i < timeGridModel.count; ++i) {
            var item = timeGridModel.get(i)
            if (item.checked) {
                mask |= (1 << item.bitIndex)
            }
        }
        return mask >>> 0
    }

    // ---- 重置表单 ----
    function resetForm() {
        titleField.text = ""
        locationField.text = ""
        descField.text = ""
        weekSpin.value = 1
        for (var i = 0; i < timeGridModel.count; ++i) {
            timeGridModel.setProperty(i, "checked", false)
        }
        publishBtn.enabled = true
        publishBtn.text = "确认发布活动"
        errorText.text = ""
        maskPreview.text = "0x00000000"
        maskPreviewDec.text = "(0)"
    }

    // ---- 执行发布 ----
    function doPublish() {
        var title = titleField.text.trim()
        if (title === "") {
            errorText.text = "请输入活动名称"
            return
        }
        if (locationField.text.trim() === "") {
            errorText.text = "请输入活动地点"
            return
        }

        var mask = computeTimeMask()
        if (mask === 0) {
            errorText.text = "请至少勾选一个活动时段"
            return
        }

        publishBtn.enabled = false
        publishBtn.text = "发布中…"
        errorText.text = ""

        NetworkClient.sendRequest("ADD_ACTIVITY", {
            "title":         title,
            "description":   descField.text.trim(),
            "location":      locationField.text.trim(),
            "activity_week": weekSpin.value,
            "time_mask":     mask,
            "organizer_id":  mainWindow.currentUser.user_id,
            "department_id": mainWindow.currentUser.department_id || 1
        })
    }

    // ================================================================
    // 弹窗内容
    // ================================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // ---- 活动名称 ----
        RowLayout {
            spacing: 8
            Text {
                text: "名称："
                font.pixelSize: 13
                Layout.preferredWidth: 50
            }
            TextField {
                id: titleField
                Layout.fillWidth: true
                placeholderText: "例：周三第3-4节 支教活动"
                font.pixelSize: 13
            }
        }

        // ---- 活动地点 ----
        RowLayout {
            spacing: 8
            Text {
                text: "地点："
                font.pixelSize: 13
                Layout.preferredWidth: 50
            }
            TextField {
                id: locationField
                Layout.fillWidth: true
                placeholderText: "例：云教室"
                font.pixelSize: 13
            }
        }

        // ---- 活动周数 ----
        RowLayout {
            spacing: 8
            Text {
                text: "周数："
                font.pixelSize: 13
                Layout.preferredWidth: 50
            }
            SpinBox {
                id: weekSpin
                from: 1
                to: 20
                value: 1
                editable: true
                Layout.preferredWidth: 100
            }
            Text {
                text: "（1-20 周）"
                font.pixelSize: 11
                color: "#888888"
            }
        }

        // ---- 活动简介 ----
        RowLayout {
            spacing: 8
            Text {
                text: "简介："
                font.pixelSize: 13
                Layout.preferredWidth: 50
            }
            TextField {
                id: descField
                Layout.fillWidth: true
                placeholderText: "活动简介（可选）"
                font.pixelSize: 13
            }
        }

        // ---- 分隔线 ----
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#E0E0E0"
        }

        // ---- 时段选择区域标题 ----
        Text {
            text: "请勾选本活动占用的时段（必选）："
            font.pixelSize: 13
            font.bold: true
            color: "#E65100"
        }

        // ---- 5×6 课表矩阵（紧凑版）----
        RowLayout {
            spacing: 0

            // 左侧：节次标签
            Column {
                spacing: 2
                Rectangle { width: 54; height: 24; color: "transparent" }
                Repeater {
                    model: [
                        "第1节\n(08:00)",
                        "第2节\n(10:10)",
                        "中午档\n(12:00)",
                        "第3节\n(14:10)",
                        "第4节\n(16:10)",
                        "傍晚档\n(18:00)"
                    ]
                    Rectangle {
                        width: 54; height: 38
                        color: "#FFF3E0"
                        radius: 2
                        border { color: "#FFB74D"; width: 0.5 }
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 9
                            font.bold: true
                            color: "#E65100"
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }

            // 右侧：表头 + 网格
            Column {
                spacing: 2

                // 横向表头
                Row {
                    spacing: 2
                    Repeater {
                        model: ["周一","周二","周三","周四","周五"]
                        Rectangle {
                            width: 64; height: 24
                            color: "#1976D2"
                            radius: 2
                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                color: "white"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }
                }

                // CheckBox 网格
                Grid {
                    columns: 5
                    spacing: 2
                    Repeater {
                        model: timeGridModel
                        Rectangle {
                            width: 64; height: 38
                            color: model.checked ? "#FFCDD2" : "#E8F5E9"
                            radius: 2
                            border {
                                color: model.checked ? "#E57373" : "#A5D6A7"
                                width: 0.5
                            }

                            CheckBox {
                                anchors.centerIn: parent
                                text: "占用时段"
                                font.pixelSize: 10
                                checked: model.checked
                                onCheckedChanged: {
                                    timeGridModel.setProperty(index, "checked", checked)
                                    updateMaskPreview()
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- 实时掩码预览 ----
        RowLayout {
            spacing: 6
            Text {
                text: "当前 time_mask:"
                font.pixelSize: 11
                color: "#555555"
            }
            Text {
                id: maskPreview
                text: "0x00000000"
                font.pixelSize: 13
                font.bold: true
                font.family: "Courier New"
                color: "#1565C0"
            }
            Text {
                id: maskPreviewDec
                text: "(0)"
                font.pixelSize: 11
                color: "#888888"
                font.family: "Courier New"
            }
        }

        function updateMaskPreview() {
            var mask = computeTimeMask()
            maskPreview.text = "0x" + ("00000000" + mask.toString(16).toUpperCase()).slice(-8)
            maskPreviewDec.text = "(" + mask + ")"
        }

        // ---- 错误提示 ----
        Text {
            id: errorText
            font.pixelSize: 12
            color: "#C62828"
            visible: text !== ""
        }

        // ---- 发布按钮 ----
        Button {
            id: publishBtn
            text: "确认发布活动"
            Layout.fillWidth: true
            Layout.preferredHeight: 42

            onClicked: doPublish()

            background: Rectangle {
                color: publishBtn.enabled ? "#1565C0" : "#BDBDBD"
                radius: 4
            }
            contentItem: Text {
                text: publishBtn.text
                color: "white"
                font.pixelSize: 14
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // ---- 网络响应监听（发布成功后自动重置表单） ----
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
