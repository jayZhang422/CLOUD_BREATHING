import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: control
    property string label
    property string parameter
    property string suffix: ""
    property real minimum: 0
    property real maximum: 100
    property real step: 1
    property int decimals: 0
    property bool editable: false
    property real parameterValue: planner.parameters[control.parameter] === undefined
                                  ? (control.parameter === "wedgeAngle" ? 90 : 0)
                                  : Number(planner.parameters[control.parameter])
    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text {
            text: control.label
            color: Theme.muted
            font.pixelSize: Theme.fontLabel
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
        Text {
            visible: !control.editable
            text: control.parameterValue.toFixed(control.decimals) + control.suffix
            color: Theme.text
            font.pixelSize: Theme.fontLabel
            font.weight: Font.DemiBold
        }
        TextInput {
            id: numberInput
            objectName: "planParameterInput_" + control.parameter
            visible: control.editable
            Layout.preferredWidth: 65
            horizontalAlignment: TextInput.AlignRight
            color: Theme.text; font.pixelSize: Theme.fontLabel
            selectByMouse: true
            enabled: planner.ready && !planner.busy
            text: control.parameterValue.toFixed(control.decimals)
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            validator: DoubleValidator { bottom: control.minimum; top: control.maximum; decimals: control.decimals; locale: "C"; notation: DoubleValidator.StandardNotation }
            onEditingFinished: {
                if (acceptableInput) planner.setParameter(control.parameter, Number(text))
                text = control.parameterValue.toFixed(control.decimals)
            }
            Connections {
                target: planner
                function onParametersChanged() {
                    if (!numberInput.activeFocus) numberInput.text = control.parameterValue.toFixed(control.decimals)
                }
            }
        }
        Text { visible: control.editable; text: control.suffix.trim(); color: Theme.muted; font.pixelSize: Theme.fontLabel }
    }
    AppSlider {
        objectName: "planParameter_" + control.parameter
        Layout.fillWidth: true
        from: control.minimum
        to: control.maximum
        stepSize: control.step
        value: control.parameterValue
        enabled: planner.ready && !planner.busy
        onPressedChanged: {
            if (pressed) planner.beginParameterEdit(control.parameter)
            else planner.endParameterEdit(control.parameter)
        }
        onMoved: planner.setParameter(control.parameter, value)
    }
}
