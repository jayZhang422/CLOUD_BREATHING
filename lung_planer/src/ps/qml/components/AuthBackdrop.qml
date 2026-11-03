import QtQuick
import ".."

// Shared backdrop for login and registration: soft sky window, a rounded teal
// brand panel on the left (rings breathe slowly) and the form on a white card
// on the right. brandWidth tells the page how far to shift its form.
Item {
    id: backdrop
    readonly property real brandWidth: width >= 1000 ? Math.min(520, width * 0.42) : 0
    readonly property int pad: 14

    Rectangle { anchors.fill: parent; color: Theme.sky }

    // White card behind the form
    Rectangle {
        anchors.fill: parent
        anchors.margins: backdrop.pad
        radius: Theme.shellRadius
        color: Theme.background
    }

    Rectangle {
        id: brand
        x: backdrop.pad; y: backdrop.pad
        width: backdrop.brandWidth > 0 ? backdrop.brandWidth - backdrop.pad : 0
        height: parent.height - 2 * backdrop.pad
        visible: width > 0
        radius: Theme.shellRadius
        color: Theme.shell

        Item {
            id: rings
            width: 320; height: 320
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.5 - 190

            Repeater {
                model: 3
                Rectangle {
                    id: ring
                    required property int index
                    anchors.centerIn: parent
                    width: 320; height: 320; radius: 160
                    color: "transparent"
                    border.width: 2
                    border.color: "#ffffff"
                    opacity: 0
                    scale: 0.45
                    SequentialAnimation {
                        running: backdrop.visible && brand.visible
                        loops: Animation.Infinite
                        PauseAnimation { duration: ring.index * 1600 }
                        ParallelAnimation {
                            NumberAnimation { target: ring; property: "scale"; from: 0.45; to: 1.0; duration: 4800; easing.type: Easing.OutQuad }
                            SequentialAnimation {
                                NumberAnimation { target: ring; property: "opacity"; from: 0; to: 0.3; duration: 1200 }
                                NumberAnimation { target: ring; property: "opacity"; to: 0; duration: 3600 }
                            }
                        }
                    }
                }
            }
            // Soft pastel shapes around the mark
            Rectangle { width: 120; height: 120; radius: 60; color: Theme.shellDeep; anchors.centerIn: parent }
            Rectangle { width: 44; height: 44; radius: 22; color: Theme.blush; x: parent.width / 2 + 38; y: parent.height / 2 - 82 }
            Rectangle { width: 22; height: 22; radius: 11; color: Theme.sun; x: parent.width / 2 - 78; y: parent.height / 2 + 46 }
            BrandLogo { anchors.centerIn: parent; width: 76; height: 76 }
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: rings.y + rings.height + 4
            spacing: 8
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "云端呼吸"; color: Theme.shellText; font.pixelSize: 30; font.weight: Font.DemiBold }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "医学影像工作站"; color: Theme.shellText; font.pixelSize: Theme.fontBody }
        }
    }
}
