import QtQuick

Item {
    id: logo
    implicitWidth: 40
    implicitHeight: 40
    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("../assets/cloud-breathing-mark.svg")
        sourceSize.width: Math.max(64, width * 2)
        sourceSize.height: Math.max(64, height * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
}
