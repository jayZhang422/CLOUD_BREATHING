import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import ".."

Item {
    id: loginPage
    property var appWindow
    property real enter: 0

    NumberAnimation { id: enterAnim; target: loginPage; property: "enter"; from: 0; to: 1; duration: 480; easing.type: Theme.easeOut }
    Component.onCompleted: enterAnim.start()
    onVisibleChanged: if (visible) enterAnim.restart()

    AuthBackdrop { id: backdrop; anchors.fill: parent }

    ColumnLayout {
        id: form
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: backdrop.brandWidth / 2
        anchors.verticalCenterOffset: -8
        width: Math.min(380, parent.width - backdrop.brandWidth - 64)
        height: implicitHeight
        spacing: 0
        opacity: loginPage.enter
        transform: Translate { y: (1 - loginPage.enter) * 18 }

        // Brand lockup only when the side panel is hidden (narrow windows)
        RowLayout {
            visible: backdrop.brandWidth === 0
            Layout.fillWidth: true
            Layout.bottomMargin: 28
            spacing: 14
            BrandLogo { Layout.preferredWidth: 44; Layout.preferredHeight: 44 }
            Text { text: "云端呼吸"; color: appWindow.textPrimary; font.pixelSize: 24; font.weight: Font.DemiBold }
        }

        Text { text: "登录工作站"; color: appWindow.textPrimary; font.pixelSize: 26; font.weight: Font.DemiBold; Layout.bottomMargin: 6 }
        Text { text: "使用本地账号进入"; color: appWindow.textSecondary; font.pixelSize: 13; Layout.bottomMargin: 28 }

        Text { text: "账号"; color: appWindow.textSecondary; font.pixelSize: 12; Layout.bottomMargin: 8 }
        LineField {
            id: account
            objectName: "loginAccount"
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            placeholderText: "输入账号"
            text: "cloud"
            onAccepted: password.forceActiveFocus()
        }

        Text { text: "密码"; color: appWindow.textSecondary; font.pixelSize: 12; Layout.topMargin: 18; Layout.bottomMargin: 8 }
        LineField {
            id: password
            objectName: "loginPassword"
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            placeholderText: "输入密码"
            text: "cloud2026"
            echoMode: passwordVisible.checked ? TextInput.Normal : TextInput.Password
            onAccepted: session.login(account.text, text)
        }

        AppCheckBox {
            id: passwordVisible
            text: "显示密码"
            Layout.topMargin: 10
            Layout.preferredHeight: 30
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(28, implicitHeight)
            text: session.loginError
            color: appWindow.alert
            font.pixelSize: 12
            wrapMode: Text.Wrap
            verticalAlignment: Text.AlignVCenter
            opacity: text.length > 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durBase } }
        }

        Button {
            id: loginButton
            objectName: "loginSubmit"
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            text: "进入工作站"
            onClicked: session.login(account.text, password.text)
            scale: down ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeOut } }
            contentItem: Text { text: loginButton.text; color: Theme.sunForeground; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pixelSize: 14; font.weight: Font.DemiBold }
            background: Rectangle {
                radius: height / 2
                color: loginButton.down ? Qt.darker(Theme.sun, 1.1) : loginButton.hovered ? Theme.sunHover : Theme.sun
                border.width: loginButton.activeFocus ? 2 : 0
                border.color: Theme.navy
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
            }
        }

        Button {
            id: registerLink
            objectName: "openRegistration"
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 36
            Layout.topMargin: 12
            text: "创建账号"
            onClicked: appWindow.authPage = 1
            contentItem: Text {
                text: registerLink.text
                color: registerLink.hovered || registerLink.activeFocus ? appWindow.accent : appWindow.textSecondary
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pixelSize: 13
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
            }
            background: Rectangle { color: "transparent" }
        }
    }
}
