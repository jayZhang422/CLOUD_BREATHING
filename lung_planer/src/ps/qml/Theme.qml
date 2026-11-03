pragma Singleton
import QtQuick

// Teal shell + white card theme. Soft sky window, teal frame and sidebar,
// white content card, navy text, with sunny yellow and blush pink used
// sparingly as accents. Image and 3D viewports stay black (viewer* tokens).
// Property names from earlier versions are kept so every page keeps working.
QtObject {
    readonly property bool dark: false

    // Window and shell
    readonly property color sky: "#dff3f8"
    readonly property color shell: "#12827a"
    readonly property color shellDeep: "#0e6a64"
    readonly property color shellText: "#ffffff"
    readonly property color navy: "#14264a"

    // Surfaces (inside the white card)
    readonly property color background: "#ffffff"
    readonly property color toolbar: "#f4fafc"
    readonly property color panel: "#f1f8fb"
    readonly property color panelRaised: "#e3f1f6"
    readonly property color input: "#ffffff"
    readonly property color viewport: "#000000"
    readonly property color stroke: "#c7dde5"
    readonly property color strokeSoft: "#dcebf0"

    // Text (all >= 4.5:1 on panel and white)
    readonly property color text: "#14264a"
    readonly property color muted: "#4b5f7d"
    readonly property color faint: "#566884"

    // Accent: shell teal. White text on it passes 4.5:1.
    readonly property color accent: "#0f7f78"
    readonly property color accentDim: "#d3efec"
    readonly property color accentForeground: "#ffffff"
    readonly property color accentGlow: "#7fc6c0"

    // Sunny yellow (hero actions) and blush pink (soft highlights)
    readonly property color sun: "#ffd45c"
    readonly property color sunHover: "#ffc933"
    readonly property color sunForeground: "#14264a"
    readonly property color blush: "#f9c5d1"
    readonly property color sunDim: "#fff3cf"

    // Black image viewports (dark, independent of the light chrome)
    readonly property color viewerText: "#eaf0f8"
    readonly property color viewerMuted: "#9fadc0"
    readonly property color viewerAccent: "#5fd0c6"
    readonly property color viewerBar: "#0c1118"
    readonly property color viewerBarSelected: "#0f2a2c"
    readonly property color viewerField: "#18212d"
    readonly property color viewerStroke: "#2a3646"
    readonly property color viewerControl: "#212d3c"
    readonly property color viewerError: "#ffb4ab"

    // Patient queue shares the card surfaces
    readonly property color queueBackground: "#ffffff"
    readonly property color queueRow: "#f7fbfd"
    readonly property color queueHover: "#eaf5f8"
    readonly property color queueSelected: "#d3efec"
    readonly property color queueText: "#14264a"
    readonly property color queueMuted: "#4b5f7d"
    readonly property color queueAccent: "#0f7f78"
    readonly property color queueHeader: "#e8f4f7"

    // Semantic status colours (text on the matching Dim fill >= 4.5:1)
    readonly property color success: "#12794a"
    readonly property color successDim: "#d9f2e3"
    readonly property color warning: "#8a5a00"
    readonly property color warningDim: "#fff0c9"
    readonly property color error: "#c0352b"
    readonly property color errorDim: "#fde2df"

    // Type scale (never below 12 px)
    readonly property int fontCaption: 12
    readonly property int fontLabel: 13
    readonly property int fontBody: 14
    readonly property int fontTitle: 17
    readonly property int fontHeading: 26
    readonly property int fontMetric: 28

    // Spacing
    readonly property int space4: 4
    readonly property int space8: 8
    readonly property int space12: 12
    readonly property int space16: 16
    readonly property int space24: 24

    // Layout
    readonly property int toolbarHeight: 56
    readonly property int subToolbarHeight: 44
    readonly property int footerHeight: 26
    readonly property int controlHeight: 36
    readonly property int fieldHeight: 40
    readonly property int gutter: 8
    readonly property int radius: 10
    readonly property int panelRadius: 16
    readonly property int authRadius: 20

    // Shell geometry
    readonly property int sidebarWidth: 188
    readonly property int sidebarCompactWidth: 76
    readonly property int shellMargin: 10
    readonly property int shellRadius: 28
    readonly property int cardRadius: 22
    readonly property int headerHeight: 56
    readonly property int cardInset: 8

    // Motion. Short and ease-out: feedback should feel instant, structure
    // changes (fold, page switch) a little slower.
    readonly property int durFast: 120
    readonly property int durBase: 200
    readonly property int durSlow: 320
    readonly property int easeOut: Easing.OutCubic
    readonly property int easeInOut: Easing.InOutCubic
}
