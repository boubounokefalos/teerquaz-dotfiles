import QtQuick

// − value + stepper. min/max/step default to font sizes (6–48 by 1).
// suffix is shown after the number ("ms", "/s", " min"); valueText overrides it.
Row {
    id: st
    property real value: 11
    property real min: 6
    property real max: 48
    property real step: 1
    property string suffix: ""
    property string valueText: ""
    property int textWidth: 36
    signal changed(real v)
    spacing: 4
    StepBtn { icon: "remove"; delta: -1; stepper: st; enabled: st.value > st.min }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: st.textWidth
        horizontalAlignment: Text.AlignHCenter
        text: st.valueText || (st.value + st.suffix)
        color: Theme.fg1
        font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
    }
    StepBtn { icon: "add"; delta: 1; stepper: st; enabled: st.value < st.max }
}
