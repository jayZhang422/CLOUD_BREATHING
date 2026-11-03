import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: bar
    property var appWindow
    property string contextLabel: "当前检查"
    implicitHeight: 52
    color: Theme.toolbar
    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18; spacing: 12
        Rectangle {
            Layout.preferredWidth: 30; Layout.preferredHeight: 30; radius: 15
            color: Theme.accentDim
            Icon { anchors.centerIn: parent; name: "user"; size: 15 }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 1
            Text { text: bar.appWindow ? bar.appWindow.currentPatientTitle : (ctImporter.patientText.length > 0 ? ctImporter.patientText : "未载入患者"); color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
            Text { text: bar.appWindow && bar.appWindow.hidePatientInfo ? (ctImporter.sliceCount > 0 ? "CT" : "等待影像序列") : ([ctImporter.institutionText, ctImporter.studyText].filter(function(v) { return v && v.length > 0 }).join("  ·  ") || "等待影像序列"); color: Theme.muted; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
        }
        Text { text: ctImporter.sliceCount > 0 ? (ctImporter.sliceCount + " 张切片") : "无序列"; color: Theme.muted; font.pixelSize: 12 }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.strokeSoft }
}
