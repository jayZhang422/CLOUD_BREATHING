"""Item-based dialogs for EGLFS: never create another native/Widgets window."""
from pathlib import Path

from PySide6.QtCore import QObject, Property, Signal, Slot
from PySide6.QtGui import QColor


class UiDialogs(QObject):
    changed = Signal()
    requested = Signal()

    def __init__(self):
        super().__init__()
        self._kind = self._title = self._path = self._value = self._error = ""
        self._entries = []
        self._files = []
        self._callback = None
        self._overwrite = None

    kind = Property(str, lambda s: s._kind, notify=changed)
    title = Property(str, lambda s: s._title, notify=changed)
    path = Property(str, lambda s: s._path, notify=changed)
    value = Property(str, lambda s: s._value, notify=changed)
    error = Property(str, lambda s: s._error, notify=changed)
    entries = Property('QVariantList', lambda s: s._entries, notify=changed)
    files = Property('QVariantList', lambda s: s._files, notify=changed)

    def _open(self, kind, title, value, callback, error=""):
        self._kind, self._title, self._value = kind, title, value
        self._error, self._overwrite, self._callback = error, None, callback
        self.changed.emit()
        self.requested.emit()

    def directory(self, title, initial, callback):
        self.browse(initial)
        self._open("directory", title, "", callback, self._error)

    def save(self, title, initial, callback):
        target = Path(initial)
        self.browse(str(target.parent))
        self._open("save", title, target.name, callback, self._error)

    def open(self, title, initial, callback):
        target = Path(initial)
        self._kind = "open"
        self.browse(str(target.parent))
        self._open("open", title, target.name, callback, self._error)

    def color(self, title, initial, callback):
        self._open("color", title, initial, callback)

    @Slot(str, result=bool)
    def browse(self, path):
        try:
            folder = Path(path).expanduser().resolve(strict=True)
            if not folder.is_dir():
                raise ValueError("请选择文件夹")
            entries = sorted((p for p in folder.iterdir() if p.is_dir()), key=lambda p: p.name.casefold())
            self._entries = [{"name": p.name, "path": str(p)} for p in entries]
            self._files = ([{"name": p.name} for p in sorted(folder.iterdir(), key=lambda p: p.name.casefold())
                            if p.is_file() and p.suffix.lower() == '.json']
                           if self._kind == 'open' else [])
            self._path, self._error, self._overwrite = str(folder), "", None
        except (OSError, ValueError) as exc:
            self._error = "无法访问目录：" + str(exc)
            self.changed.emit()
            return False
        self.changed.emit()
        return True

    @Slot(str)
    def selectFile(self, name):
        if self._kind == 'open' and any(row['name'] == name for row in self._files):
            self._value = name
            self._error = ""
            self.changed.emit()

    @Slot()
    def up(self):
        self.browse(str(Path(self._path).parent))

    @Slot(str, result=bool)
    def accept(self, value):
        try:
            if self._callback is None or self._kind not in ("color", "directory", "save", "open"):
                raise ValueError("没有待确认的操作")
            if self._kind == "color":
                color = QColor(value)
                if not color.isValid():
                    raise ValueError("请输入有效颜色，例如 #72a9c3")
                result = color.name()
            else:
                folder = Path(self._path)
                if not folder.is_dir():
                    raise ValueError("文件夹不存在")
                result = str(folder)
                if self._kind == 'open':
                    if not value or Path(value).name != value or Path(value).suffix.lower() != '.json':
                        raise ValueError("请选择 JSON 规划文件")
                    target = folder / value
                    if not target.is_file():
                        raise ValueError("规划文件不存在")
                    result = str(target)
                elif self._kind == "save":
                    if not value or Path(value).name != value or value in (".", ".."):
                        raise ValueError("文件名不能包含目录")
                    target = folder / (value if value.lower().endswith('.json') else value + '.json')
                    if target.exists() and self._overwrite != target:
                        self._overwrite = target
                        raise ValueError("文件已存在；再次点击确认将覆盖该文件")
                    result = str(target)
            callback, self._callback = self._callback, None
            self._kind = ""
            self.changed.emit()
            if callback:
                callback(result)
            return True
        except (OSError, ValueError) as exc:
            self._error = str(exc)
            self.changed.emit()
            return False

    @Slot()
    def cancel(self):
        self._callback, self._kind, self._error = None, "", ""
        self._overwrite = None
        self.changed.emit()
