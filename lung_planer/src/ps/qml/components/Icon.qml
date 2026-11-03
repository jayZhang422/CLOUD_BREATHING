import QtQuick
import ".."

Item {
    id: icon
    property string name: ""
    property color iconColor: Theme.text
    // inverse: always use the light glyph (for permanently black viewports).
    property bool inverse: false
    // onAccent: icon sits on a filled accent surface (opposite contrast).
    property bool onAccent: false
    property int size: 16
    readonly property bool lightGlyph: inverse || (onAccent ? !Theme.dark : Theme.dark)
    implicitWidth: size
    implicitHeight: size
    opacity: enabled ? 1 : 0.4
    Image {
        anchors.fill: parent
        source: icon.name.length > 0 ? "../assets/icons/" + (icon.lightGlyph ? "" : "dark/") + icon.name + ".svg" : ""
        sourceSize.width: icon.size * 2
        sourceSize.height: icon.size * 2
        fillMode: Image.PreserveAspectFit
    }
}
