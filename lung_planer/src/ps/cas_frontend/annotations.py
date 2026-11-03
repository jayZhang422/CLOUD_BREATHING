"""Non-destructive, image-coordinate CT annotation drafts and PNG exports."""
import hashlib
import json
from pathlib import Path
from PySide6.QtCore import QObject, Signal, Slot, Property, QUrl, Qt
from PySide6.QtGui import QImage, QPainter, QPen, QColor, QPainterPath


class AnnotationStore(QObject):
    changed = Signal()
    sourceChanged = Signal(str)
    statusChanged = Signal()

    def __init__(self, project):
        super().__init__()
        self.directory = Path(project) / "data" / "annotations"
        self._status = "笔迹自动暂存，不修改原始 CT"

    @Property(str, notify=statusChanged)
    def status(self):
        return self._status

    def _key(self, source):
        return hashlib.sha256(source.encode()).hexdigest()

    @Slot(str, result=str)
    def read(self, source):
        try:
            return json.dumps(json.loads((self.directory / (self._key(source) + ".json")).read_text(encoding="utf-8"))["strokes"])
        except (OSError, ValueError, KeyError):
            return "[]"

    @Slot(str, str)
    def save(self, source, serialized):
        try:
            image = QImage(QUrl(source).toLocalFile())
            if image.isNull():
                raise ValueError("当前切片不可读")
            strokes = json.loads(serialized)
            image = image.convertToFormat(QImage.Format_ARGB32)
            painter = QPainter(image)
            painter.setRenderHint(QPainter.Antialiasing)
            try:
                for stroke in strokes:
                    points = stroke["points"]
                    if not points:
                        continue
                    color = QColor(stroke["color"])
                    color.setAlphaF(stroke["alpha"])
                    painter.setPen(QPen(color, stroke["width"] * image.width(), Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
                    path = QPainterPath()
                    path.moveTo(points[0][0] * image.width(), points[0][1] * image.height())
                    for x, y in points[1:]:
                        path.lineTo(x * image.width(), y * image.height())
                    if len(points) == 1:
                        painter.drawPoint(path.currentPosition())
                    else:
                        painter.drawPath(path)
            finally:
                painter.end()
            self.directory.mkdir(parents=True, exist_ok=True)
            key = self._key(source)
            if not image.save(str(self.directory / (key + ".png"))):
                raise OSError("PNG 保存失败")
            record = {"source": source, "strokes": strokes, "coordinateSystem": "normalized-image"}
            (self.directory / (key + ".json")).write_text(json.dumps(record, ensure_ascii=False), encoding="utf-8")
            self._status = "已暂存 PNG 和笔迹：data/annotations"
            self.changed.emit()
            self.sourceChanged.emit(source)
        except (OSError, ValueError, KeyError, TypeError) as error:
            self._status = "标注保存失败：" + str(error)
        self.statusChanged.emit()
