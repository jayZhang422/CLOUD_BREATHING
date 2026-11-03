import QtQuick
import QtQuick3D

// Same unlit, two-sided alpha-blended shell; move its constant color transfer
// out of the fragment shader. Geometry and transparent sorting remain Qt's.
CustomMaterial {
    property color surfaceColor: "white"
    property real surfaceOpacity: 1
    shadingMode: CustomMaterial.Unshaded
    cullMode: Material.NoCulling
    sourceBlend: CustomMaterial.SrcAlpha
    destinationBlend: CustomMaterial.OneMinusSrcAlpha
    vertexShader: "../shaders/flat_unlit.vert"
    fragmentShader: "../shaders/flat_unlit.frag"
}
