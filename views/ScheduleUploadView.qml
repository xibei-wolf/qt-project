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
    property string currentMode: "private"   // "private" = 个人课表, "public" = 班级公共课表

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
        // 视图显示时不再主动发包；所有数据由 userDataReady / classSelector / 保存成功 三路驱动
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
        console.log("VERIFY initEmptyGrid BEFORE — scheduleModel.count:", scheduleModel.count)
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
        console.log("VERIFY initEmptyGrid AFTER — scheduleModel.count:", scheduleModel.count)
    }

    // ================================================================
    // 数据核心控制引擎（拉取与平铺）
    // ================================================================
    // 防重入锁：阻止并发信号触发重复发包
    property bool isLoading: false

    function loadTargetSchedule() {
        // 防重入锁：避免并发信号同时触发造成重复发包
        if (isLoading) {
            console.log("DEBUG: loadTargetSchedule skipped — already loading")
            return
        }

        var targetClassName = ""
        var isPublicFlag = false

        if (isManager && currentMode === "public") {
            targetClassName = String(currentSelectedClass).trim()
            isPublicFlag = true
            if (targetClassName === "") {
                uploadFeedback.text = "请先在左侧下拉框中选择目标班级"
                uploadFeedback.color = "#C62828"
                return
            }
        } else {
            targetClassName = String(mainWindow.currentUser.class_name || "").trim()
            isPublicFlag = false

            // 严苛参数校验：class_name 为空直接拒绝，不重试
            if (targetClassName === "") {
                console.error("Critical: loadTargetSchedule 触发时 class_name 为空，拒绝请求！")
                uploadFeedback.text = "班级信息未同步，请重新登录"
                uploadFeedback.color = "#C62828"
                return
            }
        }

        isLoading = true
        initEmptyGrid()

        uploadFeedback.text = "正在同步时段位图数据..."
        uploadFeedback.color = "#F57C00"

        console.log("DEBUG: TargetSchedule loadTargetSchedule sending GET_CLASS_TEMPLATE — targetClassName=[" + targetClassName + "] isPublic=" + isPublicFlag + " currentMode=" + currentMode)
        NetworkClient.sendRequest("GET_CLASS_TEMPLATE", {
            "class_name": targetClassName,
            "user_id": mainWindow.currentUser.user_id,
            "is_public": isPublicFlag
        })
    }

    function injectCoursesToGrid(courses) {
        console.log("VERIFY injectCoursesToGrid ENTER — courses.length:", courses ? courses.length : 0, "scheduleModel.count BEFORE init:", scheduleModel.count)

        if (!courses || !Array.isArray(courses)) {
            uploadFeedback.text = "当前班级无课表，请在下方手动排课"
            uploadFeedback.color = "#C62828"
            return
        }

        initEmptyGrid()
        console.log("VERIFY injectCoursesToGrid AFTER initEmptyGrid — scheduleModel.count:", scheduleModel.count)

        var injectedCount = 0
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
                if (t.time_mask !== undefined) {
                    scheduleModel.setProperty(cellIndex, "time_mask", t.time_mask)
                }
                injectedCount++
            }
        }

        console.log("VERIFY injectCoursesToGrid DONE — injectedCount:", injectedCount, "scheduleModel.count:", scheduleModel.count)

        if (courses.length === 0) {
            uploadFeedback.text = "当前班级无课表，请在下方手动排课"
            uploadFeedback.color = "#C62828"
            console.log("DEBUG: GET_CLASS_TEMPLATE returned empty courses array — 当前班级无课表")
        } else {
            uploadFeedback.text = "⚡ 成功载入课表规则，共 " + courses.length + " 项。"
            uploadFeedback.color = "#1565C0"
            console.log("DEBUG: Injecting", courses.length, "courses to grid — 数据已传达至 UI 层")
        }
    }

    Component.onCompleted: {
        // 组件实例化不作为数据加载触发点。
        // 所有课表加载请求仅由以下三个场景触发：
        //   1. mainWindow.userDataReady 信号（登录成功后 currentUser 已完整填充）
        //   2. classSelector.currentIndex 手动切换（仅在 currentMode === "public" 时）
        //   3. UPLOAD_SCHEDULE 保存成功后自动重载
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
                                root.currentSelectedClass = String(item.name).trim()
                                if (root.currentMode === "public") {
                                    root.loadTargetSchedule()
                                }
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

                    Rectangle {
                        width: 180
                        height: 32
                        radius: 4
                        color: classSelector.currentIndex >= 0 ? "#1565C0" : "#90A4AE"
                        Text {
                            anchors.centerIn: parent
                            text: "套用班级课表到全班 🚀"
                            color: "white"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: classSelector.currentIndex >= 0
                            onClicked: {
                                var cls = String(classSelector.currentText).trim();
                                console.log("DEBUG: Sending BATCH_APPLY with class_name: [" + cls + "] length:", cls.length);
                                uploadFeedback.text = "正在将 " + cls + " 的课表模板批量下发至全班成员..."
                                uploadFeedback.color = "#F57C00"
                                NetworkClient.sendRequest("BATCH_APPLY_CLASS_TEMPLATE", {
                                    "class_name": cls
                                })
                            }
                        }
                    }
                }
            }
        }

        // ---- 课表模式切换（仅管理层可见） ----
        RowLayout {
            Layout.fillWidth: true
            visible: root.isManager
            spacing: 16

            Text {
                text: "📌 课表模式:"
                font.pixelSize: 13
                font.bold: true
                color: "#E65100"
            }

            RadioButton {
                text: "👤 个人课表"
                checked: root.currentMode === "private"
                onCheckedChanged: {
                    if (checked) {
                        root.currentMode = "private"
                        root.loadTargetSchedule()
                    }
                }
            }

            RadioButton {
                text: "🏫 班级公共课表"
                checked: root.currentMode === "public"
                onCheckedChanged: {
                    if (checked) {
                        root.currentMode = "public"
                        root.loadTargetSchedule()
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        // ---- 基础文案说明 ----
        Text {
            text: {
                var cn = String(mainWindow.currentUser.class_name || "").trim()
                if (!mainWindow.isLoggedIn) return "🏫 所属班级: 请先登录"
                if (cn === "") return "🏫 所属班级: 班级信息获取中…"
                return "🏫 所属班级: " + cn
            }
            font.pixelSize: 13
            font.bold: true
            color: {
                var cn = String(mainWindow.currentUser.class_name || "").trim()
                if (!mainWindow.isLoggedIn || cn === "") return "#C62828"
                return "#1565C0"
            }
            Layout.fillWidth: true
        }

        Text {
            text: root.isManager
                  ? (root.currentMode === "public"
                     ? "📌 正在设定【" + String(root.currentSelectedClass).trim() + "】班级公共课表"
                     : "📅 我的个人课表管理")
                  : "📆 我的全学期个人课表管理"
            font.pixelSize: 18
            font.bold: true
            color: root.isManager
                   ? (root.currentMode === "public" ? "#E65100" : "#1565C0")
                   : "#1B5E20"
        }

        Text {
            text: {
                if (!root.isManager)
                    return "队员须知：系统已自动为你加载了你所在班级的基础公共课表。如果你有其他选修课或私事冲突，请直接在下方继续勾选并提交。"
                if (root.currentMode === "public")
                    return "管理员须知：在此处排定的课程将作为该班的公共专业课，全体班级成员导入时会自动继承。"
                return "管理员须知：你正在编辑个人课表。如需编辑班级公共课表，请在上方切换到「🏫 班级公共课表」模式。"
            }
            font.pixelSize: 12
            color: "#666666"
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        // ---------- 5 × 6 网格渲染区域 (保持原先优良的 Grid 表现) ----------
        RowLayout {
            spacing: 6
            // 左侧时间标签
            Column {
                spacing: 6
                Rectangle { width: 70; height: 34; color: "transparent" }
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
                        width: 70; height: 46; color: "#ECEFF1"; radius: 4
                        border.color: "#CFD8DC"
                        Text { 
                            anchors.centerIn: parent 
                            text: modelData 
                            font.pixelSize: 10 
                            horizontalAlignment: Text.AlignHCenter 
                            verticalAlignment: Text.AlignVCenter
                            color: "#546E7A"
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
            // 右侧课表主体
            Column {
                spacing: 6
                Row {
                    spacing: 6
                    Repeater {
                        model: ["周一", "周二", "周三", "周四", "周五"]
                        Rectangle {
                            width: 95; height: 34; color: "#1565C0"; radius: 4
                            Text { anchors.centerIn: parent; text: modelData; color: "white"; font.bold: true; font.pixelSize: 13 }
                        }
                    }
                }
                Grid {
                    columns: 5; spacing: 6
                    Repeater {
                        model: scheduleModel
                        Rectangle {
                            width: 95; height: 46
                            color: model.has_course ? "#FFEBEE" : "#E8F5E9"
                            radius: 4
                            border.color: model.has_course ? "#FFCDD2" : "#C8E6C9"
                            border.width: 1

                            // 有课时点击格子任意位置即可编辑
                            MouseArea {
                                anchors.fill: parent
                                enabled: model.has_course
                                onClicked: {
                                    editingCellIndex = index
                                    var cell = scheduleModel.get(index)
                                    editCourseName.text = cell.course_name || ""
                                    editStartWeek.value = cell.start_week || 1
                                    editEndWeek.value = cell.end_week || 16
                                    editWeekType.currentIndex = cell.week_type || 0
                                    courseEditDialog.open()
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                anchors.topMargin: 2
                                anchors.bottomMargin: 2
                                spacing: 4
                                CheckBox {
                                    checked: model.has_course
                                    Layout.preferredWidth: 22
                                    Layout.preferredHeight: 22
                                    onCheckedChanged: {
                                        scheduleModel.setProperty(index, "has_course", checked)
                                        if (!checked) {
                                            scheduleModel.setProperty(index, "course_name", "")
                                        }
                                    }
                                }
                                Text {
                                    text: model.has_course && model.course_name !== "" ? model.course_name : (model.has_course ? "有课 ✏" : "空闲")
                                    font.pixelSize: 11
                                    color: model.has_course ? "#C62828" : "#2E7D32"
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignLeft
                                    verticalAlignment: Text.AlignVCenter
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
        Rectangle {
            id: submitBtn
            property bool enabled: {
                if (!NetworkClient.connected) return false
                if (root.isManager && root.currentMode === "public" && String(root.currentSelectedClass).trim() === "")
                    return false
                return true
            }
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: 6
            color: submitBtn.enabled ? "#2E7D32" : "#90A4AE"

            Text {
                anchors.centerIn: parent
                text: root.isManager
                      ? (root.currentMode === "public"
                         ? "💾 保存并发布班级公共课表"
                         : "💾 保存我的个人课表")
                      : "🚀 提交并封存我的个人课表"
                color: "white"
                font.bold: true
                font.pixelSize: 14
            }

            MouseArea {
                anchors.fill: parent
                enabled: submitBtn.enabled
                onClicked: {
                    var payload = compileCoursesPayload()
                    var requestData = {
                        "user_id":    mainWindow.currentUser.user_id,
                        "courses":    payload,
                        "is_public":  (root.isManager && root.currentMode === "public")
                    }
                    if (root.isManager && root.currentMode === "public") {
                        requestData["target_class"] = String(root.currentSelectedClass).trim()
                    }
                    console.log("[DEBUG WIRE] UPLOAD_SCHEDULE sending packet:", JSON.stringify(requestData))
                    NetworkClient.sendRequest("UPLOAD_SCHEDULE", requestData)
                }
            }
        }
    }

    // ================================================================
    // 弹窗与网络中转区（保持原有解析机制）
    // ================================================================
    Dialog {
        id: courseEditDialog
        title: "编辑课程详细策略"
        modal: true; width: 500; height: 300
        ColumnLayout {
            anchors.fill: parent; spacing: 10
            anchors.margins: 14

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

    // ================================================================
    // 唯一数据加载驱动入口：mainWindow.userDataReady 信号
    // 登录成功后 currentUser（含 class_name）已完整填充，此时加载课表
    // ================================================================
    Connections {
        target: mainWindow

        function onUserDataReady() {
            console.log("DEBUG: TargetSchedule userDataReady received — class_name=[" + String(mainWindow.currentUser.class_name || "").trim() + "]")
            root.loadTargetSchedule()

            // 管理员同步拉取班级下拉列表
            if (root.isManager && adminClassModel.count === 0 && NetworkClient.connected) {
                NetworkClient.sendRequest("GET_REGISTERED_CLASSES", {})
            }
        }
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
                root.isLoading = false  // 释放防重入锁

                if (data.status === "ok" && data.data && data.data.courses) {
                    var courses = data.data.courses
                    if (courses.length === 0) {
                        root.initEmptyGrid()
                        uploadFeedback.text = "当前暂无课表记录，请点击下方进行排课"
                        uploadFeedback.color = "#78909C"
                        console.log("DEBUG: GET_CLASS_TEMPLATE returned empty courses array")
                    } else {
                        root.injectCoursesToGrid(courses)
                    }
                } else {
                    root.initEmptyGrid()
                    uploadFeedback.text = "当前暂无课表记录，请点击下方进行排课"
                    uploadFeedback.color = "#78909C"
                    console.log("DEBUG: GET_CLASS_TEMPLATE failed or no data — " + (data.message || "no message"))
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
                        root.currentSelectedClass = String(adminClassModel.get(0).name).trim()
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
                    uploadFeedback.text = "🟢 数据同步封存成功！"
                    uploadFeedback.color = "#2E7D32"
                    // 不再回读后端 GET_CLASS_TEMPLATE（后端该接口返回空数组，会清空网格）
                    // 当前 scheduleModel 即为刚保存的数据，直接保留
                } else {
                    uploadFeedback.text = "❌ 存储出错: " + (data.message || "未知错误")
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
