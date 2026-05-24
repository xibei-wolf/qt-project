import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../js/EventRecurrenceLogic.js" as EventLogic

Item {
    id: root

    // ---- 核心状态控制 ----
    property int editingCellIndex: -1
    property bool isManager: mainWindow.isLoggedIn && mainWindow.currentUser.role_id <= 30
    property string currentSelectedClass: ""

    // 节次 → 时间范围映射（第1-2节=08:00~09:50, 第3-4节=10:10~12:00, ...）
    property var periodTimeMap: [
        { startH: 8,  startM: 0,  endH: 9,  endM: 50 },   // period 0: 第1-2节
        { startH: 10, startM: 10, endH: 12, endM: 0  },   // period 1: 第3-4节
        { startH: 14, startM: 10, endH: 16, endM: 0  },   // period 2: 第5-6节
        { startH: 16, startM: 10, endH: 18, endM: 0  },   // period 3: 第7-8节
        { startH: 18, startM: 30, endH: 20, endM: 10 },   // period 4: 第9-10节
        { startH: 19, startM: 30, endH: 21, endM: 10 }    // period 5: 第11-12节
    ]

    function periodTimeMask(periodIndex) {
        if (periodIndex < 0 || periodIndex >= periodTimeMap.length) return 0
        var t = periodTimeMap[periodIndex]
        return EventLogic.calculateTimeMask(t.startH, t.startM, t.endH, t.endM)
    }

    function periodTimeLabel(periodIndex) {
        if (periodIndex < 0 || periodIndex >= periodTimeMap.length) return ""
        var t = periodTimeMap[periodIndex]
        var sh = t.startH < 10 ? "0" + t.startH : t.startH
        var sm = t.startM < 10 ? "0" + t.startM : t.startM
        var eh = t.endH < 10 ? "0" + t.endH : t.endH
        var em = t.endM < 10 ? "0" + t.endM : t.endM
        return sh + ":" + sm + "-" + eh + ":" + em
    }

    onVisibleChanged: {
        if (visible && isManager && adminClassModel.count === 0 && NetworkClient.connected) {
            console.log("View visible, network active — pulling registered classes roster")
            NetworkClient.sendRequest("GET_REGISTERED_CLASSES", {})
        }
    }

    // ---- 班级下拉模型（管理端动态拉取已注册班级） ----
    ListModel {
        id: adminClassModel
    }

    ListModel {
        id: weekTypeModel
        Component.onCompleted: {
            append({ text: "每周",  val: 0 })
            append({ text: "单周",  val: 1 })
            append({ text: "双周",  val: 2 })
        }
    }

    // ---- 5天 × 6节 = 30 个网格核心数据源 ----
    ListModel {
        id: scheduleModel
        Component.onCompleted: initEmptyGrid()
    }

    function initEmptyGrid() {
        scheduleModel.clear()
        for (var period = 0; period < 6; ++period) {
            for (var day = 0; day < 5; ++day) {
                scheduleModel.append({
                    day: day,
                    period: period,
                    has_course: false,
                    course_name: "",
                    start_week: 1,
                    end_week: 16,
                    week_type: 0,
                    time_mask: periodTimeMask(period),
                    time_label: periodTimeLabel(period)
                })
            }
        }
    }

    // ================================================================
    // 数据核心控制引擎（拉取与平铺）
    // ================================================================
    function loadTargetSchedule() {
        initEmptyGrid()
        uploadFeedback.text = "正在同步时段位图数据..."
        uploadFeedback.color = "#F57C00"

        var targetClassName = ""
        if (isManager) {
            targetClassName = currentSelectedClass
            if (targetClassName === "") return
        } else {
            targetClassName = mainWindow.currentUser.class_name || ""
        }

        console.log("正在拉取课表规则，目标班级/用户空间:", targetClassName)
        NetworkClient.sendRequest("GET_CLASS_TEMPLATE", {
            "class_name": targetClassName
        })
    }

    function injectCoursesToGrid(courses) {
        if (!courses || !Array.isArray(courses)) return
        initEmptyGrid()

        for (var c = 0; c < courses.length; ++c) {
            var t = courses[c]
            var d = (t.day_of_week || 1) - 1
            var p = (t.period     || 1) - 1
            var cellIndex = p * 5 + d

            if (cellIndex >= 0 && cellIndex < scheduleModel.count) {
                scheduleModel.setProperty(cellIndex, "has_course",  true)
                scheduleModel.setProperty(cellIndex, "course_name", t.course_name || "")
                scheduleModel.setProperty(cellIndex, "start_week",  t.start_week  || 1)
                scheduleModel.setProperty(cellIndex, "end_week",    t.end_week    || 16)
                scheduleModel.setProperty(cellIndex, "week_type",   t.week_type   || 0)
            }
        }
        uploadFeedback.text = "⚡ 成功载入基线课表规则，共 " + courses.length + " 项。"
        uploadFeedback.color = "#1565C0"
    }

    Component.onCompleted: {
        if (!isManager) {
            loadTargetSchedule()
        } else if (NetworkClient.connected) {
            NetworkClient.sendRequest("GET_REGISTERED_CLASSES", {})
        }
    }

    // ================================================================
    // 视图排版层
    // ================================================================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // ---- 动态管理控制台（仅高权限可见） ----
        RowLayout {
            Layout.fillWidth: true
            visible: root.isManager
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                height: 48
                color: "#ECEFF1"
                radius: 6

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    spacing: 10

                    Text {
                        text: "🛠️ 班级公共课表管理面板 | 当前切换班级:"
                        font.bold: true
                        font.pixelSize: 12
                        color: "#37474F"
                    }

                    ComboBox {
                        id: classSelector
                        model: adminClassModel
                        textRole: "text"
                        Layout.preferredWidth: 200
                        onCurrentIndexChanged: {
                            var item = adminClassModel.get(currentIndex)
                            if (item) {
                                root.currentSelectedClass = item.name
                                root.loadTargetSchedule()
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // 一键清空/删除当前班级公共课表
                    Button {
                        text: "🗑 清空该班课表"
                        onClicked: {
                            root.initEmptyGrid()
                            uploadFeedback.text = "提示：已清空当前编辑区，需点击下方提交以封存至服务器。"
                            uploadFeedback.color = "#C62828"
                        }
                    }

                    Button {
                        text: "套用班级课表到全班 🚀"
                        enabled: classSelector.currentIndex >= 0
                        onClicked: {
                            var cls = classSelector.currentText
                            uploadFeedback.text = "正在将 " + cls + " 的课表模板批量下发至全班成员..."
                            uploadFeedback.color = "#F57C00"
                            NetworkClient.sendRequest("BATCH_APPLY_CLASS_TEMPLATE", {
                                "class_name": cls
                            })
                        }
                        background: Rectangle {
                            color: parent.enabled ? "#1565C0" : "#90A4AE"
                            radius: 4
                        }
                        contentItem: Text {
                            text: parent.text
                            color: "white"
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        // ---- 基础文案说明 ----
        Text {
            text: root.isManager ? "📌 正在设定【" + root.currentSelectedClass + "】班级的统一课表" : "📆 我的全学期个人课表管理"
            font.pixelSize: 18
            font.bold: true
            color: root.isManager ? "#E65100" : "#1B5E20"
        }

        Text {
            text: root.isManager
                  ? "管理员须知：在此处排定的课程将直接作为该班的公共专业课，全体班级成员导入时会自动继承。"
                  : "队员须知：系统已自动为你加载了你所在班级的基础公共课表。如果你有其他选修课或私事冲突，请直接在下方继续勾选并提交。"
            font.pixelSize: 12
            color: "#666666"
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        // ---------- 5 × 6 网格渲染区域 (保持原先优良的 Grid 表现) ----------
        RowLayout {
            spacing: 4
            // 左侧时间标签
            Column {
                spacing: 4
                Rectangle { width: 60; height: 32; color: "transparent" }
                Repeater {
                    model: [
                        "第1-2节\n" + periodTimeLabel(0),
                        "第3-4节\n" + periodTimeLabel(1),
                        "第5-6节\n" + periodTimeLabel(2),
                        "第7-8节\n" + periodTimeLabel(3),
                        "第9-10节\n" + periodTimeLabel(4),
                        "第11-12节\n" + periodTimeLabel(5)
                    ]
                    Rectangle {
                        width: 60; height: 44; color: "#ECEFF1"; radius: 4
                        Text { anchors.centerIn: parent; text: modelData; font.pixelSize: 9; horizontalAlignment: Text.AlignHCenter; color: "#546E7A" }
                    }
                }
            }
            // 右侧课表主体
            Column {
                spacing: 4
                Row {
                    spacing: 4
                    Repeater {
                        model: ["周一", "周二", "周三", "周四", "周五"]
                        Rectangle {
                            width: 85; height: 32; color: "#1565C0"; radius: 4
                            Text { anchors.centerIn: parent; text: modelData; color: "white"; font.bold: true; font.pixelSize: 12 }
                        }
                    }
                }
                Grid {
                    columns: 5; spacing: 4
                    Repeater {
                        model: scheduleModel
                        Rectangle {
                            width: 85; height: 44
                            color: model.has_course ? "#FFEBEE" : "#E8F5E9"
                            radius: 4
                            border.color: model.has_course ? "#FFCDD2" : "#C8E6C9"

                            RowLayout {
                                anchors.centerIn: parent; spacing: 1
                                CheckBox {
                                    checked: model.has_course
                                    onCheckedChanged: {
                                        scheduleModel.setProperty(index, "has_course", checked)
                                        if (!checked) {
                                            scheduleModel.setProperty(index, "course_name", "")
                                        }
                                    }
                                }
                                Text {
                                    text: model.has_course && model.course_name !== "" ? model.course_name : (model.has_course ? "(有课)" : "空闲")
                                    font.pixelSize: 10
                                    color: model.has_course ? "#C62828" : "#2E7D32"
                                    Layout.preferredWidth: 36
                                    elide: Text.ElideRight
                                }
                                Button {
                                    visible: model.has_course
                                    Layout.preferredWidth: 16; Layout.preferredHeight: 16
                                    flat: true
                                    text: "✏"
                                    onClicked: {
                                        editingCellIndex = index
                                        editCourseName.text = model.course_name || ""
                                        editStartWeek.value = model.start_week || 1
                                        editEndWeek.value = model.end_week || 16
                                        editWeekType.currentIndex = model.week_type || 0
                                        courseEditDialog.open()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- 操作反馈通知区 ----
        Text {
            id: uploadFeedback
            text: "就绪"
            font.pixelSize: 12
            color: "#455A64"
        }

        // ---- 提交打包核心区域 ----
        Button {
            text: root.isManager ? "💾 保存并发布当前班级基础课表" : "🚀 提交并封存我的个人课表"
            enabled: NetworkClient.connected
            Layout.fillWidth: true
            Layout.preferredHeight: 40

            onClicked: {
                var payload = compileCoursesPayload()
                var requestData = {
                    "user_id": mainWindow.currentUser.user_id,
                    "courses": payload
                }

                // 🟢 关键差异化打包：如果是管理层，加入 target_class 字段告诉后端写公共模板
                if (root.isManager) {
                    requestData["target_class"] = root.currentSelectedClass
                }

                console.log("[DEBUG WIRE] UPLOAD_SCHEDULE sending packet:", JSON.stringify(requestData))
                NetworkClient.sendRequest("UPLOAD_SCHEDULE", requestData)
            }

            background: Rectangle { color: parent.enabled ? "#2E7D32" : "#90A4AE"; radius: 4 }
            contentItem: Text { text: parent.text; color: "white"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        }
    }

    // ================================================================
    // 弹窗与网络中转区（保持原有解析机制）
    // ================================================================
    Dialog {
        id: courseEditDialog
        title: "编辑课程详细策略"
        modal: true; width: 320; height: 300
        ColumnLayout {
            anchors.fill: parent; spacing: 10
            Text {
                text: editingCellIndex >= 0
                      ? "时段: " + (scheduleModel.get(editingCellIndex).time_label || "")
                      : ""
                font.pixelSize: 12; color: "#E65100"; font.bold: true
            }
            RowLayout {
                Text { text: "课程名:"; Layout.preferredWidth: 50 }
                TextField { id: editCourseName; Layout.fillWidth: true }
            }
            RowLayout {
                Text { text: "起止周:"; Layout.preferredWidth: 50 }
                SpinBox { id: editStartWeek; from: 1; to: 16 }
                Text { text: "至" }
                SpinBox { id: editEndWeek; from: 1; to: 16 }
            }
            RowLayout {
                Text { text: "周期类型:"; Layout.preferredWidth: 50 }
                ComboBox { id: editWeekType; model: weekTypeModel; textRole: "text"; Layout.fillWidth: true }
            }
            Button {
                text: "应用到网格"
                Layout.fillWidth: true
                onClicked: {
                    if (editingCellIndex >= 0) {
                        scheduleModel.setProperty(editingCellIndex, "course_name", editCourseName.text.trim())
                        scheduleModel.setProperty(editingCellIndex, "start_week", editStartWeek.value)
                        scheduleModel.setProperty(editingCellIndex, "end_week", editEndWeek.value)
                        scheduleModel.setProperty(editingCellIndex, "week_type", weekTypeModel.get(editWeekType.currentIndex).val)
                    }
                    courseEditDialog.close()
                }
            }
        }
    }

    function compileCoursesPayload() {
        var arr = []
        for (var i = 0; i < scheduleModel.count; ++i) {
            var cell = scheduleModel.get(i)
            if (!cell.has_course) continue
            var t = periodTimeMap[cell.period] || periodTimeMap[0]
            var mask = EventLogic.calculateTimeMask(t.startH, t.startM, t.endH, t.endM)
            var st = (t.startH < 10 ? "0" + t.startH : t.startH) + ":" + (t.startM < 10 ? "0" + t.startM : t.startM) + ":00"
            var et = (t.endH < 10 ? "0" + t.endH : t.endH) + ":" + (t.endM < 10 ? "0" + t.endM : t.endM) + ":00"
            arr.push({
                "course_name": cell.course_name.trim() === "" ? "有课" : cell.course_name,
                "day_of_week": cell.day + 1,
                "period": cell.period + 1,
                "start_week": cell.start_week,
                "end_week": cell.end_week,
                "week_type": cell.week_type,
                "time_mask":  mask,
                "start_time": st,
                "end_time":   et
            })
        }
        return arr
    }

    Connections {
        target: NetworkClient

        function onConnectedChanged(connected) {
            if (connected && root.isManager && adminClassModel.count === 0) {
                console.log("Network tunnel established, querying registered classes roster")
                NetworkClient.sendRequest("GET_REGISTERED_CLASSES", {})
            }
        }

        function onResponseReceived(action, data) {
            if (action === "GET_CLASS_TEMPLATE" || data.action === "GET_CLASS_TEMPLATE") {
                if (data.status === "ok" && data.data && data.data.courses) {
                    root.injectCoursesToGrid(data.data.courses)
                } else {
                    root.initEmptyGrid()
                    uploadFeedback.text = "暂无班级基线模板数据，当前为白纸看板。"
                    uploadFeedback.color = "#78909C"
                }
            }
            if (action === "GET_REGISTERED_CLASSES" || data.action === "GET_REGISTERED_CLASSES") {
                if (data.status === "ok" && data.data && data.data.classes) {
                    var classes = data.data.classes
                    adminClassModel.clear()
                    for (var i = 0; i < classes.length; i++) {
                        adminClassModel.append({ text: classes[i], name: classes[i] })
                    }
                    if (adminClassModel.count > 0) {
                        classSelector.currentIndex = 0
                        root.currentSelectedClass = adminClassModel.get(0).name
                    }
                    uploadFeedback.text = "已加载 " + classes.length + " 个已注册班级"
                    uploadFeedback.color = "#1565C0"
                } else {
                    uploadFeedback.text = "拉取班级列表失败: " + (data.message || "未知错误")
                    uploadFeedback.color = "#C62828"
                }
            }
            if (action === "UPLOAD_SCHEDULE" || data.action === "UPLOAD_SCHEDULE") {
                if (data.status === "ok") {
                    uploadFeedback.text = "🟢 数据同步封存成功！策略已在全球集群实时生效。"
                    uploadFeedback.color = "#2E7D32"
                } else {
                    uploadFeedback.text = "❌ 存储出错: " + data.message
                    uploadFeedback.color = "#C62828"
                }
            }
            if (action === "BATCH_APPLY_CLASS_TEMPLATE" || data.action === "BATCH_APPLY_CLASS_TEMPLATE") {
                if (data.status === "ok" || data.code === 0) {
                    var synced = data.data ? (data.data.affected_rows || data.data.affected_count || 0) : 0
                    uploadFeedback.text = "🟢 课表模板已成功批量下发！共同步 " + synced + " 名同学的课表矩阵。"
                    uploadFeedback.color = "#2E7D32"
                } else {
                    uploadFeedback.text = "❌ 批量下发失败: " + (data.message || "未知错误")
                    uploadFeedback.color = "#C62828"
                }
            }
        }
    }
}
