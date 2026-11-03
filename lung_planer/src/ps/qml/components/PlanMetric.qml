import QtQuick
import QtQuick.Layouts
import ".."

// One quantitative result. Large card for key metrics, one-line row when compact.
// verdict: "" (neutral) | "ok" | "bad" colours the value and the left marker.
Rectangle {
    id: metricRow
    property string label
    property string metric
    property string unit: ""
    property int decimals: 1
    property bool slow: true
    property bool compact: false
    property string verdict: ""
    property string hint: ""
    // Explicit value (e.g. a lobectomy plan); NaN means read planner.result[metric].
    property real value: NaN
    readonly property bool overridden: !isNaN(metricRow.value)
    readonly property bool hasValue: overridden || planner.hasPlan && planner.geometryCurrent
        && !((metricRow.slow || planner.executionBackend === "pl") && planner.metricsPending)
        && planner.result[metricRow.metric] !== undefined && planner.result[metricRow.metric] !== null
    readonly property string valueText: !hasValue ? "--"
        : Number(overridden ? metricRow.value : planner.result[metricRow.metric]).toFixed(metricRow.decimals)
    readonly property color stateColor: !hasValue || verdict === "" ? Theme.text : (verdict === "ok" ? Theme.success : Theme.error)
    objectName: "planMetric_" + metric
    implicitHeight: compact ? 32 : 76
    radius: Theme.panelRadius
    color: compact ? "transparent" : Theme.panelRaised

    // Left marker: grows from the centre when a verdict arrives.
    Rectangle {
        visible: !metricRow.compact
        width: 3; radius: 1.5
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 0
        height: (parent.height - 20) * (!metricRow.hasValue || metricRow.verdict === "" ? 0.45 : 1)
        color: !metricRow.hasValue || metricRow.verdict === "" ? Theme.stroke : metricRow.stateColor
        Behavior on height { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeOut } }
        Behavior on color { ColorAnimation { duration: Theme.durSlow } }
    }

    // Large card
    ColumnLayout {
        visible: !metricRow.compact
        anchors.fill: parent
        anchors.leftMargin: 16; anchors.rightMargin: 12; anchors.topMargin: 10; anchors.bottomMargin: 10
        spacing: 2
        Text { text: metricRow.label; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true; elide: Text.ElideRight }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
                text: metricRow.valueText
                color: metricRow.stateColor
                Layout.fillWidth: true; Layout.minimumWidth: 0
                font.pixelSize: Theme.fontMetric
                minimumPixelSize: 14
                fontSizeMode: Text.HorizontalFit
                elide: Text.ElideRight
                font.weight: Font.DemiBold
                Behavior on color { ColorAnimation { duration: Theme.durSlow } }
                // The number "settles" when a fresh value arrives.
                onTextChanged: if (metricRow.hasValue) settle.restart()
                SequentialAnimation {
                    id: settle
                    NumberAnimation { target: metricRow; property: "valueShift"; from: 5; to: 0; duration: Theme.durSlow; easing.type: Theme.easeOut }
                }
                transform: Translate { y: metricRow.valueShift }
            }
            Text { text: metricRow.unit.trim(); color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.alignment: Qt.AlignBaseline }
        }
        Text { visible: metricRow.hint.length > 0; text: metricRow.hint; color: Theme.faint; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true; elide: Text.ElideRight }
    }
    property real valueShift: 0

    // Compact row
    RowLayout {
        visible: metricRow.compact
        anchors.fill: parent
        anchors.leftMargin: 2; anchors.rightMargin: 2
        spacing: 8
        Text { text: metricRow.label; color: Theme.muted; font.pixelSize: Theme.fontLabel; Layout.fillWidth: true; elide: Text.ElideRight }
        Text { text: metricRow.valueText; color: metricRow.stateColor; font.pixelSize: Theme.fontBody; font.weight: Font.DemiBold }
        Text { text: metricRow.unit.trim(); color: Theme.faint; font.pixelSize: Theme.fontCaption; Layout.preferredWidth: 30 }
    }
    Rectangle {
        visible: metricRow.compact
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 1; color: Theme.strokeSoft
    }
}
