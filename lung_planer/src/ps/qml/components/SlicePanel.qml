import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: panel
    property var appWindow
    property string title: ""
    property string sourceUrl: ""
    property bool axial: false
    signal expandRequested()
    property bool expandable: false
    property string plane: "axial"
    property bool pageActive: false
    readonly property int currentIndex: plane === "coronal" ? ctImporter.coronalIndex
        : (plane === "sagittal" ? ctImporter.sagittalIndex : ctImporter.sliceIndex)
    property int currentSlot: -1
    readonly property var activeImage: currentSlot < 0 ? null : imageSlots.itemAt(currentSlot)
    readonly property bool imageReady: activeImage !== null && activeImage.status === Image.Ready
    property bool selected: !appWindow.active3D && appWindow.selectedPlane === panel.plane
    property real zoom: 1.0
    property real panX: 0
    property real panY: 0
    property var strokes: []
    property var draft: null
    function notifyImageReady() {
        if (pageActive && activeImage && activeImage.status === Image.Ready
                && activeImage.source.toString() === sourceUrl)
            benchmark.ctImageReady(plane, sourceUrl)
    }
    function refreshImages() {
        if (imageSlots.count !== 3) return
        var wanted = pageActive && sourceUrl
            ? [sourceUrl, ctImporter.slicePath(plane, currentIndex - 1),
               ctImporter.slicePath(plane, currentIndex + 1)] : []
        var nextSlot = -1
        for (var i = 0; i < wanted.length; ++i) {
            if (!wanted[i]) continue
            var found = -1
            for (var j = 0; j < 3; ++j) {
                if ((imageSlots.itemAt(j) as Image).source.toString() === wanted[i]) { found = j; break }
            }
            if (found < 0) {
                for (j = 0; j < 3; ++j) {
                    var candidate = (imageSlots.itemAt(j) as Image).source.toString()
                    if (wanted.indexOf(candidate) < 0) { found = j; break }
                }
                if (found >= 0) imageSlots.itemAt(found).source = wanted[i]
            }
            if (i === 0) nextSlot = found
        }
        for (i = 0; i < 3; ++i) {
            if (wanted.indexOf((imageSlots.itemAt(i) as Image).source.toString()) < 0)
                imageSlots.itemAt(i).source = ""
        }
        currentSlot = nextSlot
    }
    function reloadAnnotations() {
        draft = null
        if (!pageActive) return
        strokes = sourceUrl ? JSON.parse(annotations.read(sourceUrl)) : []
        ink.requestPaint()
    }
    function saveAnnotations() { annotations.save(sourceUrl, JSON.stringify(strokes)) }
    onSourceUrlChanged: {
        if (pageActive) benchmark.beginCtFrame(plane, sourceUrl)
        refreshImages(); reloadAnnotations(); Qt.callLater(notifyImageReady)
    }
    onCurrentIndexChanged: refreshImages()
    onVisibleChanged: { if (visible && pageActive) reloadAnnotations() }
    onCurrentSlotChanged: Qt.callLater(notifyImageReady)
    onPageActiveChanged: {
        if (pageActive) benchmark.beginCtFrame(plane, sourceUrl)
        refreshImages()
        if (pageActive) reloadAnnotations()
        Qt.callLater(notifyImageReady)
    }
    Component.onCompleted: {
        if (pageActive) benchmark.beginCtFrame(plane, sourceUrl)
        refreshImages()
        Qt.callLater(notifyImageReady)
    }
    Connections {
        target: annotations
        function onSourceChanged(source) {
            if (panel.pageActive && panel.visible && source === panel.sourceUrl) panel.reloadAnnotations()
        }
    }
    Connections {
        target: appWindow
        function onAnnotationCommand(command) {
            if (!panel.pageActive || !panel.visible || !panel.selected || !panel.activeImage
                    || panel.activeImage.status !== Image.Ready) return
            if (command === "undo") panel.strokes = panel.strokes.slice(0, -1)
            if (command === "clear") panel.strokes = []
            panel.saveAnnotations()
        }
    }
    color: Theme.viewport
    border.width: panel.selected ? 2 : 1
    border.color: panel.selected ? Theme.viewerAccent : Theme.viewerStroke
    Behavior on border.color { ColorAnimation { duration: Theme.durBase } }
    clip: true
    Item {
        id: imageViewport
        objectName: "ctImageViewport"
        x: (parent.width - width) / 2 + panel.panX
        y: 34 + (parent.height - 58 - height) / 2 + panel.panY
        width: Math.max(0, parent.width - 30)
        height: Math.max(0, parent.height - 66)
        scale: panel.zoom
        visible: panel.pageActive && panel.activeImage !== null
            && panel.activeImage.status === Image.Ready
        Repeater {
            id: imageSlots
            model: 3
            Image {
                objectName: "ctImageSlot"
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: true
                cache: false
                visible: panel.currentSlot === index
                onStatusChanged: {
                    if (status === Image.Ready) Qt.callLater(panel.notifyImageReady)
                }
            }
        }
        Canvas {
            id: ink
            x: (parent.width - width) / 2; y: (parent.height - height) / 2
            width: panel.activeImage ? panel.activeImage.paintedWidth : 0
            height: panel.activeImage ? panel.activeImage.paintedHeight : 0
            visible: panel.pageActive
            onWidthChanged: { if (panel.pageActive) requestPaint() }
            onHeightChanged: { if (panel.pageActive) requestPaint() }
            onPaint: {
                if (!panel.pageActive || !panel.visible) return
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var all = panel.draft ? panel.strokes.concat([panel.draft]) : panel.strokes
                for (var i = 0; i < all.length; ++i) {
                    var s = all[i], p = s.points
                    if (!p.length) continue
                    ctx.globalAlpha = s.alpha; ctx.strokeStyle = s.color; ctx.fillStyle = s.color
                    ctx.lineWidth = s.width * width; ctx.lineCap = "round"; ctx.lineJoin = "round"
                    ctx.beginPath()
                    if (p.length === 1) {
                        ctx.arc(p[0][0]*width, p[0][1]*height, ctx.lineWidth/2, 0, Math.PI*2)
                        ctx.fill()
                    } else {
                        ctx.moveTo(p[0][0]*width, p[0][1]*height)
                        for (var j = 1; j < p.length; ++j) ctx.lineTo(p[j][0]*width, p[j][1]*height)
                        ctx.stroke()
                    }
                }
                ctx.globalAlpha = 1
            }
        }
    }
    MouseArea {
        id: panArea
        anchors.fill: parent
        property real startX: 0
        property real startY: 0
        property real originX: 0
        property real originY: 0
        function imagePoint(mx, my) {
            var p = mapToItem(ink, mx, my)
            return [Math.max(0, Math.min(1, p.x / ink.width)), Math.max(0, Math.min(1, p.y / ink.height))]
        }
        onPressed: function(mouse) {
            appWindow.selectedPlane = panel.plane
            appWindow.active3D = false
            panel.forceActiveFocus()
            startX = mouse.x
            startY = mouse.y
            originX = panel.panX
            originY = panel.panY
            if (appWindow.annotationMode !== 0 && panel.activeImage
                    && panel.activeImage.status === Image.Ready) {
                var pos = mapToItem(ink, mouse.x, mouse.y)
                if (pos.x < 0 || pos.y < 0 || pos.x > ink.width || pos.y > ink.height) return
                panel.draft = {color: appWindow.annotationColor, alpha: appWindow.annotationMode === 2 ? 0.3 : 1,
                    width: appWindow.annotationWidth / (ink.width * panel.zoom), points: [imagePoint(mouse.x, mouse.y)]}
                if (panel.pageActive) ink.requestPaint()
            }
        }
        onPositionChanged: function(mouse) {
            if (pressed && panel.draft) {
                panel.draft.points.push(imagePoint(mouse.x, mouse.y))
                if (panel.pageActive) ink.requestPaint()
            } else if (pressed && appWindow.annotationMode === 0) {
                panel.panX = originX + mouse.x - startX
                panel.panY = originY + mouse.y - startY
            }
        }
        onReleased: {
            if (panel.draft) {
                panel.strokes = panel.strokes.concat([panel.draft])
                panel.draft = null
                panel.saveAnnotations()
            }
        }
        onCanceled: { panel.draft = null; if (panel.pageActive) ink.requestPaint() }
        onDoubleClicked: {
            if (appWindow.annotationMode !== 0) return
            if (panel.expandable) { panel.expandRequested(); return }
            panel.zoom = 1.0
            panel.panX = 0
            panel.panY = 0
        }
        onWheel: function(wheel) {
            if (pressed) { wheel.accepted = true; return }
            if (!panel.selected) {
                wheel.accepted = true
                return
            }
            if (wheel.modifiers & Qt.ControlModifier) {
                panel.zoom = Math.max(0.5, Math.min(4.0, panel.zoom + (wheel.angleDelta.y > 0 ? 0.1 : -0.1)))
                wheel.accepted = true
                return
            }
            if (wheel.angleDelta.y > 0) {
                if (panel.plane === "coronal") ctImporter.nextCoronal()
                else if (panel.plane === "sagittal") ctImporter.nextSagittal()
                else ctImporter.nextSlice()
            } else {
                if (panel.plane === "coronal") ctImporter.previousCoronal()
                else if (panel.plane === "sagittal") ctImporter.previousSagittal()
                else ctImporter.previousSlice()
            }
            wheel.accepted = true
        }
    }
    Text {
        anchors.centerIn: parent
        width: parent.width - 30
        text: panel.activeImage && panel.activeImage.status === Image.Error
            ? "图像加载失败"
            : (panel.sourceUrl.length > 0 ? "正在载入 CT 预览..." : "尚未导入 CT")
        color: panel.activeImage && panel.activeImage.status === Image.Error ? appWindow.viewerAlert : Theme.viewerMuted
        font.pixelSize: 14
        horizontalAlignment: Text.AlignHCenter
        visible: panel.pageActive && !imageViewport.visible
    }
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 1
        height: 30
        color: panel.selected ? Theme.viewerBarSelected : Theme.viewerBar
        Behavior on color { ColorAnimation { duration: Theme.durBase } }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 8
            Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: panel.plane === "axial" ? "#e58c77" : (panel.plane === "coronal" ? "#78b0e2" : "#9fc986") }
            Text { text: panel.title; color: Theme.viewerText; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
            Icon { name: "expand"; inverse: true; size: 13; visible: panel.expandable; opacity: panel.selected ? 0.9 : 0.5 }
        }
    }
    Text { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 10; text: "×" + panel.zoom.toFixed(1); color: Theme.viewerMuted; font.pixelSize: 12 }
    Text {
        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 10
        text: panel.plane === "axial" && ctImporter.sliceCount > 0 ? ("IM " + (ctImporter.sliceIndex + 1) + " / " + ctImporter.sliceCount)
            : (panel.plane === "coronal" && ctImporter.coronalCount > 0 ? ("MPR " + (ctImporter.coronalIndex + 1) + " / " + ctImporter.coronalCount)
            : (panel.plane === "sagittal" && ctImporter.sagittalCount > 0 ? ("MPR " + (ctImporter.sagittalIndex + 1) + " / " + ctImporter.sagittalCount) : ""))
        color: Theme.viewerMuted; font.pixelSize: 12
    }
}
