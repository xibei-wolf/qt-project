import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Window {
    id: mainWindow
    width: 1200
    height: 800
    visible: true
    title: "青云志愿服务队管理系统"
    color: "#F5F7FA"

    // ============================================================================
    // 固化的服务器连接常量（只读，不暴露输入控件）
    // ============================================================================
    readonly property string kServerIp:   "192.168.79.128"
    readonly property int    kServerPort: 9000

    // ============================================================================
    // 全局状态
    // ============================================================================
    property bool isLoggedIn: false
    property var currentUser: ({
        user_id: 0,
        student_id: "",
        name: "",
        role_id: 0,
        department_id: 0,
        class_name: ""
    })
    property bool isRole40: currentUser.role_id === 40

    // ============================================================================
    // 登录状态机
    // ============================================================================
    property string loginStudentId: ""
    property string loginPassword: ""
    property string loginErrorText: ""
    property bool   loginLoading: false
    property bool   loginConnecting: false
    property string connStatusText: "未连接"
    property string connStatusColor: "#9E9E9E"

    // ============================================================================
    // 角色中文映射
    // ============================================================================
    function roleLabel(rid) {
        switch (rid) {
            case 10: return "带队老师"
            case 20: return "队长"
            case 30: return "部长"
            case 40: return "普通队员"
            default: return "未知"
        }
    }

    // ============================================================================
    // doLogin — 一键自动连接 + 认证（防重复发包死锁保护）
    // ============================================================================
    function doLogin() {
        if (loginLoading) return

        var sid = loginStudentId.trim()
        var pwd = loginPassword
        if (sid === "" || pwd === "") return

        loginLoading = true
        loginErrorText = ""

        if (NetworkClient.connected) {
            loginConnecting = false
            connStatusText = "正在登录验证…"
            connStatusColor = "#F57C00"
            NetworkClient.sendRequest("LOGIN", {
                "student_id": sid,
                "password":    pwd
            })
        } else {
            loginConnecting = true
            loginErrorText = "正在建立安全连接…"
            connStatusText = "正在建立安全连接…"
            connStatusColor = "#F57C00"
            NetworkClient.connectToServer(kServerIp, kServerPort)
        }
    }

    // ============================================================================
    // doLogout — 物理级全线清盘，绝杀切换账号死锁
    // ============================================================================
    function doLogout() {
        // 先掐断网络，阻止任何在途回包触发状态变更
        NetworkClient.disconnectFromServer()

        // 重置所有登录状态字
        mainWindow.isLoggedIn = false
        mainWindow.currentUser = ({
            user_id: 0,
            student_id: "",
            name: "",
            role_id: 0,
            department_id: 0,
            class_name: ""
        })
        mainWindow.loginStudentId = ""
        mainWindow.loginPassword = ""
        mainWindow.loginErrorText = ""
        mainWindow.loginLoading = false
        mainWindow.loginConnecting = false

        // 硬清空输入框组件真实显示文本，击碎属性绑定僵死
        loginStudentIdField.text = ""
        loginPasswordField.text = ""

        mainWindow.connStatusText = "未连接"
        mainWindow.connStatusColor = "#9E9E9E"
        tabBar.currentIndex = 0
    }

    // ============================================================================
    // 全局信号拦截 — 自动登录通道核心
    // ============================================================================
    Connections {
        target: NetworkClient

        function onConnectedChanged(connected) {
            if (connected) {
                connStatusText = "服务器已连接"
                connStatusColor = "#2E7D32"

                // TCP 握手刚完成且处于登录流程 → 自动顺延发送 LOGIN
                if (loginConnecting && !mainWindow.isLoggedIn) {
                    loginConnecting = false
                    connStatusText = "正在登录验证…"
                    connStatusColor = "#F57C00"
                    NetworkClient.sendRequest("LOGIN", {
                        "student_id": loginStudentId.trim(),
                        "password":    loginPassword
                    })
                }
            } else {
                connStatusText = "未连接"
                connStatusColor = "#9E9E9E"
                if (mainWindow.isLoggedIn) {
                    mainWindow.isLoggedIn = false
                    mainWindow.currentUser = ({
                        user_id: 0,
                        student_id: "",
                        name: "",
                        role_id: 0,
                        department_id: 0,
                        class_name: ""
                    })
                    mainWindow.loginLoading = false
                    mainWindow.loginConnecting = false
                    tabBar.currentIndex = 0
                }
                if (loginLoading) {
                    loginLoading = false
                    loginConnecting = false
                    loginErrorText = "连接失败，请检查服务器是否在线"
                }
            }
        }

        function onConnectionError(errorString) {
            connStatusText = "错误: " + errorString
            connStatusColor = "#C62828"
            loginLoading = false
            loginConnecting = false
            loginErrorText = errorString
        }

        function onResponseReceived(action, data) {
            debugConsole.append("[" + new Date().toLocaleTimeString() + "] Action: " + action + "\n" + JSON.stringify(data, null, 4) + "\n----------------------------------------");

            if (action === "LOGIN" || data.action === "LOGIN") {
                loginLoading = false
                loginConnecting = false

                if (data.status === "ok" || data.code === 0) {
                    var ud = data.data
                    if (ud) {
                        mainWindow.currentUser = {
                            user_id:       ud.user_id       || ud.id || 0,
                            student_id:    ud.student_id    || loginStudentId,
                            name:          ud.name          || "",
                            role_id:       ud.role_id       || 40,
                            department_id: ud.department_id || 0,
                            class_name:    ud.class_name    || ""
                        }
                        mainWindow.isLoggedIn = true
                        mainWindow.loginErrorText = ""
                        mainWindow.loginPassword = ""
                        connStatusText = "已连接 · 已认证"
                        connStatusColor = "#2E7D32"

                        // 角色分流导航
                        if (mainWindow.isRole40) {
                            tabBar.currentIndex = 3  // 课表上传
                        } else {
                            tabBar.currentIndex = 0  // 活动管理
                        }
                    }
                } else {
                    mainWindow.loginErrorText = "登录失败: " + (data.message || "用户名或密码错误")
                    connStatusText = "服务器已连接"
                    connStatusColor = "#2E7D32"
                }
            }
        }
    }

    // ============================================================================
    // 主布局
    // ============================================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ================================================================
        // 顶部状态栏（只读，不可操作）
        // ================================================================
        Rectangle {
            Layout.fillWidth: true
            height: 44
            color: "#FFFFFF"
            border { color: "#E0E0E0"; width: 1 }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 10

                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: loginConnecting ? "#FFC107"
                         : NetworkClient.connected ? "#4CAF50" : "#BDBDBD"
                }

                Text {
                    text: connStatusText
                    font.pixelSize: 12
                    color: connStatusColor
                }

                Rectangle { width: 1; height: 20; color: "#E0E0E0" }

                Text {
                    text: "服务器 " + kServerIp + ":" + kServerPort
                    font.pixelSize: 11
                    color: "#9E9E9E"
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: isLoggedIn
                          ? roleLabel(currentUser.role_id) + " · " + currentUser.name + " (" + currentUser.student_id + ")"
                          : ""
                    font.pixelSize: 12
                    font.bold: true
                    color: "#1565C0"
                    visible: isLoggedIn
                }

                Rectangle {
                    width: 1; height: 20; color: "#E0E0E0"
                    visible: isLoggedIn
                }

                Button {
                    text: "退出登录"
                    visible: isLoggedIn
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 28
                    onClicked: doLogout()
                    background: Rectangle { color: "#757575"; radius: 4 }
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

        // ================================================================
        // 登录面板
        // ================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !isLoggedIn

            Rectangle {
                anchors.centerIn: parent
                width: 400
                height: loginForm.height + 48
                radius: 8
                color: "#FFFFFF"
                border { color: "#E0E0E0"; width: 1 }

                ColumnLayout {
                    id: loginForm
                    anchors.centerIn: parent
                    width: 320
                    spacing: 12

                    Item { Layout.preferredHeight: 8 }

                    Text {
                        text: "青雲志愿服务队管理系统"
                        font.pixelSize: 20
                        font.bold: true
                        color: "#1565C0"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "请输入学号和密码登录"
                        font.pixelSize: 12
                        color: "#888888"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Rectangle { Layout.preferredHeight: 4; Layout.fillWidth: true; color: "transparent" }

                    TextField {
                        id: loginStudentIdField
                        Layout.fillWidth: true
                        font.pixelSize: 14
                        placeholderText: "学号"
                        enabled: !loginLoading
                        background: Rectangle {
                            radius: 4
                            border { color: "#BDBDBD"; width: 1 }
                            color: "#FAFAFA"
                            implicitHeight: 42
                        }
                        onTextChanged: loginStudentId = text
                    }

                    TextField {
                        id: loginPasswordField
                        Layout.fillWidth: true
                        font.pixelSize: 14
                        placeholderText: "密码"
                        echoMode: TextInput.Password
                        enabled: !loginLoading
                        background: Rectangle {
                            radius: 4
                            border { color: "#BDBDBD"; width: 1 }
                            color: "#FAFAFA"
                            implicitHeight: 42
                        }
                        onTextChanged: loginPassword = text
                        onAccepted: doLogin()
                    }

                    Text {
                        text: loginErrorText
                        font.pixelSize: 12
                        color: "#C62828"
                        visible: loginErrorText !== ""
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }

                    Button {
                        id: loginBtn
                        text: loginLoading
                              ? (loginConnecting ? "连接中…" : "登录中…")
                              : "登  录"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        enabled: !loginLoading
                                 && loginStudentId.trim() !== ""
                                 && loginPassword.trim() !== ""

                        onClicked: doLogin()

                        background: Rectangle {
                            color: loginBtn.enabled ? "#1565C0" : "#BDBDBD"
                            radius: 4
                        }
                        contentItem: Text {
                            text: loginBtn.text
                            color: "white"
                            font.pixelSize: 15
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Item { Layout.preferredHeight: 8 }
                }
            }
        }

        // ================================================================
        // 标签栏 + 内容区（登录后显示）
        // ================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: isLoggedIn

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                TabBar {
                    id: tabBar
                    Layout.fillWidth: true

                    TabButton {
                        text: "⚙️ 活动管理"
                        width: implicitWidth + 20
                        contentItem: Text {
                            text: parent.text
                            font.pixelSize: 13
                            font.bold: parent.checked
                            color: parent.checked ? "#1565C0" : "#757575"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: parent.checked ? "#E3F2FD" : "#FFFFFF"
                            border {
                                color: parent.checked ? "#1565C0" : "#E0E0E0"
                                width: parent.checked ? 2 : 1
                            }
                        }
                    }

                    TabButton {
                        text: "👥 成员管理"
                        width: implicitWidth + 20
                        contentItem: Text {
                            text: parent.text
                            font.pixelSize: 13
                            font.bold: parent.checked
                            color: parent.checked ? "#1565C0" : "#757575"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: parent.checked ? "#E3F2FD" : "#FFFFFF"
                            border {
                                color: parent.checked ? "#1565C0" : "#E0E0E0"
                                width: parent.checked ? 2 : 1
                            }
                        }
                    }

                    TabButton {
                        text: isRole40 ? "📋 活动互动" : "📋 活动排班"
                        width: implicitWidth + 20
                        contentItem: Text {
                            text: parent.text
                            font.pixelSize: 13
                            font.bold: parent.checked
                            color: parent.checked ? "#1565C0" : "#757575"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: parent.checked ? "#E3F2FD" : "#FFFFFF"
                            border {
                                color: parent.checked ? "#1565C0" : "#E0E0E0"
                                width: parent.checked ? 2 : 1
                            }
                        }
                    }

                    TabButton {
                        text: "📅 课表上传"
                        width: implicitWidth + 20
                        contentItem: Text {
                            text: parent.text
                            font.pixelSize: 13
                            font.bold: parent.checked
                            color: parent.checked ? "#1565C0" : "#757575"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: parent.checked ? "#E3F2FD" : "#FFFFFF"
                            border {
                                color: parent.checked ? "#1565C0" : "#E0E0E0"
                                width: parent.checked ? 2 : 1
                            }
                        }
                    }

                    TabButton {
                        text: "🛠️ 调试控制台"
                        width: implicitWidth + 20
                        contentItem: Text {
                            text: parent.text
                            font.pixelSize: 13
                            font.bold: parent.checked
                            color: parent.checked ? "#1565C0" : "#757575"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: parent.checked ? "#E3F2FD" : "#FFFFFF"
                            border {
                                color: parent.checked ? "#1565C0" : "#E0E0E0"
                                width: parent.checked ? 2 : 1
                            }
                        }
                    }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: tabBar.currentIndex

                    ActivityManagementView {}
                    MemberManagementView {}
                    ActivityDispatchView {}
                    ScheduleUploadView {}

                    // 调试控制台
                    Rectangle {
                        color: "#1E1E1E"
                        Flickable {
                            id: debugFlick
                            anchors.fill: parent
                            anchors.margins: 8
                            clip: true
                            TextArea.flickable: TextArea {
                                id: debugConsole
                                color: "#D4D4D4"
                                font.pixelSize: 11
                                font.family: "Consolas"
                                readOnly: true
                                wrapMode: Text.Wrap
                                background: Rectangle { color: "transparent" }
                            }
                            ScrollBar.vertical: ScrollBar {}
                        }
                    }
                }
            }
        }
    }
}
