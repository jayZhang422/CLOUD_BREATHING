import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import ".."

Item {
    id: registrationPage
    property var appWindow
    property real enter: 0

    NumberAnimation { id: enterAnim; target: registrationPage; property: "enter"; from: 0; to: 1; duration: 480; easing.type: Theme.easeOut }
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
        opacity: registrationPage.enter
        transform: Translate { y: (1 - registrationPage.enter) * 18 }

        RowLayout {
            visible: backdrop.brandWidth === 0
            Layout.fillWidth: true
            Layout.bottomMargin: 26
            spacing: 14
            BrandLogo { Layout.preferredWidth: 44; Layout.preferredHeight: 44 }
            Text { text: "云端呼吸"; color: appWindow.textPrimary; font.pixelSize: 24; font.weight: Font.DemiBold }
        }

        Text { text: "创建账号"; color: appWindow.textPrimary; font.pixelSize: 26; font.weight: Font.DemiBold; Layout.bottomMargin: 6 }
        Text { text: "账号仅保存在本机"; color: appWindow.textSecondary; font.pixelSize: 13; Layout.bottomMargin: 26 }

        Text { text: "账号"; color: appWindow.textSecondary; font.pixelSize: 12; Layout.bottomMargin: 8 }
        LineField {
            id: newAccount
            objectName: "registrationAccount"
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            placeholderText: "至少 3 个字符"
            onAccepted: newPassword.forceActiveFocus()
        }

        Text { text: "密码"; color: appWindow.textSecondary; font.pixelSize: 12; Layout.topMargin: 16; Layout.bottomMargin: 8 }
        LineField {
            id: newPassword
            objectName: "registrationPassword"
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            placeholderText: "至少 6 个字符"
            echoMode: TextInput.Password
            onAccepted: confirmPassword.forceActiveFocus()
        }

        Text { text: "确认密码"; color: appWindow.textSecondary; font.pixelSize: 12; Layout.topMargin: 16; Layout.bottomMargin: 8 }
        LineField {
            id: confirmPassword
            objectName: "registrationConfirmation"
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            placeholderText: "再次输入密码"
            echoMode: TextInput.Password
            onAccepted: session.registerAccount(newAccount.text, newPassword.text, text)
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(40, implicitHeight)
            text: session.registerError
            color: appWindow.alert
            font.pixelSize: 12
            wrapMode: Text.Wrap
            verticalAlignment: Text.AlignVCenter
            opacity: text.length > 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durBase } }
        }

        Button {
            id: registerButton
            objectName: "registrationSubmit"
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            text: "创建并进入工作站"
            onClicked: session.registerAccount(newAccount.text, newPassword.text, confirmPassword.text)
            scale: down ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeOut } }
            contentItem: Text { text: registerButton.text; color: Theme.sunForeground; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pixelSize: 14; font.weight: Font.DemiBold }
            background: Rectangle {
                radius: height / 2
                color: registerButton.down ? Qt.darker(Theme.sun, 1.1) : registerButton.hovered ? Theme.sunHover : Theme.sun
                border.width: registerButton.activeFocus ? 2 : 0
                border.color: Theme.navy
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
            }
        }

        Button {
            id: backToLoginButton
            objectName: "backToLogin"
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 36
            Layout.topMargin: 12
            text: "返回登录"
            onClicked: appWindow.authPage = 0
            contentItem: Text {
                text: backToLoginButton.text
                color: backToLoginButton.hovered || backToLoginButton.activeFocus ? appWindow.accent : appWindow.textSecondary
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pixelSize: 13
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
            }
            background: Rectangle { color: "transparent" }
        }
    }
}
