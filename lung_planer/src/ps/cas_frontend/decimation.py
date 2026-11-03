"""Cancelable, isolated organ simplification for the case queue."""
import json
import os
import sys
from datetime import datetime
from pathlib import Path
from uuid import uuid4

from PySide6.QtCore import QObject, Property, QProcess, Signal, Slot
from PySide6.QtWidgets import QFileDialog


class DecimationController(QObject):
    changed = Signal()

    def __init__(self, root, viewer, dialogs=None):
        super().__init__()
        self.root, self.viewer, self.dialogs = Path(root).resolve(), viewer, dialogs
        self._source = self._result = self._original = ''
        self._status = '选择同一患者的 STL 文件夹；血管、肿瘤优先保留细节。'
        self._busy = False
        self._cancelled = False
        self._output = None
        self._buffer = ''
        self.process = QProcess(self)
        self.process.setProcessChannelMode(QProcess.MergedChannels)
        self.process.readyReadStandardOutput.connect(self._read)
        self.process.finished.connect(self._finished)
        self.process.errorOccurred.connect(self._error)
        self._log = None

    source = Property(str, lambda s: s._source, notify=changed)
    result = Property(str, lambda s: s._result, notify=changed)
    status = Property(str, lambda s: s._status, notify=changed)
    busy = Property(bool, lambda s: s._busy, notify=changed)

    @Slot()
    def chooseDirectory(self):
        if self._busy:
            return
        if self.dialogs:
            self.dialogs.directory('选择同一患者的 STL 文件夹', self._source or str(Path.home()), self.selectDirectory)
        else:
            selected = QFileDialog.getExistingDirectory(None, '选择同一患者的 STL 文件夹', self._source)
            if selected:
                self.selectDirectory(selected)

    @Slot(str)
    def selectDirectory(self, directory):
        if self._busy:
            return
        path = Path(directory).resolve()
        if not path.is_dir():
            self._status = '请选择有效的 STL 文件夹。'
        else:
            self._source = str(path)
            self._result = self._original = ''
            self._status = '已选择 STL 文件夹。可直接载入，或先执行分器官减面。'
        self.changed.emit()

    @Slot(int)
    def start(self, faces):
        if self._busy or self.viewer.busy:
            return
        if not self._source or faces < 1000 or faces % 2:
            self._status = '请选择文件夹；目标面数须为不小于 1000 的偶数。'
            self.changed.emit()
            return
        output = self.root / 'data' / 'stl-reductions' / (datetime.now().strftime('%Y%m%d-%H%M%S-') + uuid4().hex[:8])
        if output.is_relative_to(Path(self._source).resolve()):
            self._status = '输入不能包含工程的减面输出目录，请选择具体病例文件夹。'
            self.changed.emit()
            return
        output.parent.mkdir(parents=True, exist_ok=True)
        self._output = output
        self._log = output.with_suffix('.log').open('w', encoding='utf-8')
        self._result = self._original = ''
        self._busy, self._cancelled, self._buffer = True, False, ''
        self._status = '正在复制原始数据、分配器官预算并执行拓扑保留减面…'
        executable = os.environ.get('CLOUD_BREATHING_DECIMATION_PYTHON', sys.executable)
        self.process.setWorkingDirectory(str(self.root))
        self.process.start(executable, ['-u', str(self.root / 'tools' / 'decimate_organs.py'),
                           '--input', self._source, '--output', str(output), '--faces', str(faces)])
        self.changed.emit()

    def _read(self):
        text = bytes(self.process.readAllStandardOutput()).decode('utf-8', errors='replace')
        if self._log:
            self._log.write(text)
            self._log.flush()
        self._buffer = (self._buffer + text)[-12000:]
        lines = [line.strip() for line in self._buffer.splitlines() if line.strip()]
        if lines:
            self._status = lines[-1][:500]
            self.changed.emit()

    def _close_log(self):
        if self._log:
            self._log.close()
            self._log = None

    def _error(self, error):
        if error == QProcess.FailedToStart:
            self._busy = False
            self._status = '减面 Python 环境无法启动，请检查 CLOUD_BREATHING_DECIMATION_PYTHON。'
            self._close_log()
            self.changed.emit()

    def _finished(self, code, exit_status):
        self._read()
        self._close_log()
        self._busy = False
        if self._cancelled:
            self._status = '已取消减面；原始文件未修改，未完成结果不会载入。'
        elif code or exit_status != QProcess.NormalExit:
            detail = self._buffer.strip().splitlines()[-1] if self._buffer.strip() else '进程异常退出'
            self._status = f'减面失败：{detail}。日志：{self._output.with_suffix(".log")}'
        else:
            try:
                report = json.loads((self._output / 'report.json').read_text(encoding='utf-8'))
                if not (self._output / 'stl_150k' / 'display_source.json').exists():
                    raise ValueError('缺少校验清单')
                self._result = str(self._output / 'stl_150k')
                self._original = str(self._output / 'original_stl')
                self._status = f'完成：{report["source_faces"]:,} → {report["output_faces"]:,} 面。载入后显示、规划和中心线统一使用减面模型。'
            except Exception as exc:
                self._status = f'结果校验失败：{exc}'
        self.changed.emit()

    @Slot()
    def cancel(self):
        if self._busy:
            self._cancelled = True
            self.process.kill()

    @Slot(bool)
    def load(self, reduced):
        if self._busy or self.viewer.busy:
            return
        directory = self._result if reduced else (self._original or self._source)
        if directory:
            self.viewer.loadDirectory(directory)

    def shutdown(self):
        self.cancel()
        if self.process.state() != QProcess.NotRunning:
            self.process.waitForFinished(3000)
        self._close_log()
