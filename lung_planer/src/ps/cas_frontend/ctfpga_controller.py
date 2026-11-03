"""Run the ctfpga CT -> STL pipeline from the reconstruction page."""
import json
import platform
from datetime import datetime
from pathlib import Path
from time import monotonic

from PySide6.QtCore import QObject, Property, QProcess, QTimer, Signal, Slot
from PySide6.QtWidgets import QFileDialog

STAGES = (("CT2BIN", "CT2BIN"), ("Send", "发送"), ("Reasoning", "推理"), ("Receive", "回读"),
          ("BIN2STL", "BIN2STL"), ("Smooth", "平滑"), ("Cut", "减面"))


class CtfpgaController(QObject):
    changed = Signal()

    def __init__(self, root, viewer, importer, dialogs=None):
        super().__init__()
        self.root, self.viewer, self.importer, self.dialogs = Path(root).resolve(), viewer, importer, dialogs
        self._dicom = ''
        self._busy = self._cancelled = False
        self._case = None
        self._status = ''
        self._buffer = ''
        self._log = None
        self._started = self._ended = 0.0
        self._stages = self._empty_stages()
        self.process = QProcess(self)
        self.process.setProcessChannelMode(QProcess.MergedChannels)
        self.process.readyReadStandardOutput.connect(self._read)
        self.process.finished.connect(self._finished)
        self.process.errorOccurred.connect(self._error)
        self._timer = QTimer(self)
        self._timer.setInterval(1000)
        self._timer.timeout.connect(self._poll)
        importer.changed.connect(self._importer_changed)

    @property
    def _binary(self):
        return self.root / 'ctfpga' / f'build-{platform.machine()}' / 'ctfpga'

    available = Property(bool, lambda s: s._binary.is_file(), constant=True)
    dicomDirectory = Property(str, lambda s: s._dicom, notify=changed)
    busy = Property(bool, lambda s: s._busy, notify=changed)
    status = Property(str, lambda s: s._status, notify=changed)
    stages = Property('QVariantList', lambda s: s._stages, notify=changed)
    elapsedText = Property(str, lambda s: s._elapsed_text(), notify=changed)

    @staticmethod
    def _empty_stages():
        return [{'key': key, 'label': label, 'status': 'Queue', 'detail': ''} for key, label in STAGES]

    def _elapsed_text(self):
        if not self._started:
            return ''
        seconds = int((monotonic() if self._busy else self._ended) - self._started)
        return f'{seconds // 60}:{seconds % 60:02d}'

    def _importer_changed(self):
        # Follow the CT that is open on the imaging page until the user picks another folder.
        source = self.importer.sourceDirectory
        if source and not self._busy and source != self._dicom:
            self._dicom = source
            self.changed.emit()

    def _choose(self, title, initial, callback):
        if self.dialogs:
            self.dialogs.directory(title, initial, callback)
        else:
            selected = QFileDialog.getExistingDirectory(None, title, initial)
            if selected:
                callback(selected)

    @Slot()
    def chooseDicom(self):
        if not self._busy:
            self._choose('选择 CT DICOM 文件夹', self._dicom or str(Path.home()), self._set_dicom)

    def _set_dicom(self, directory):
        path = Path(directory).expanduser().resolve()
        if path.is_dir():
            self._dicom = str(path)
            self._status = ''
            self.changed.emit()

    @Slot()
    def start(self):
        if not self._dicom:
            self._status = '请先选择 DICOM 文件夹。'
            self.changed.emit()
            return
        self._run(['--stage', 'all', '--data-dir', self._dicom])

    @Slot()
    def chooseExistingCase(self):
        """Offline mode: rebuild STL from a case that already holds prediction/."""
        if not self._busy:
            initial = self.root / 'data' / 'ctfpga-cases'
            self._choose('选择已有推理结果的病例目录', str(initial if initial.is_dir() else Path.home()), self._start_offline)

    def _start_offline(self, directory):
        source = Path(directory).expanduser().resolve()
        prediction, metadata = source / 'prediction', source / 'input' / 'metadata.json'
        if not (prediction / 'metadata.json').is_file() or not metadata.is_file():
            self._status = '该目录缺少 prediction/metadata.json 或 input/metadata.json。'
            self.changed.emit()
            return
        self._run(['--stage', 'all', '--prediction-dir', str(prediction), '--ct-metadata', str(metadata)])

    def _run(self, arguments):
        if self._busy or self.viewer.busy:
            return
        if not self._binary.is_file():
            self._status = 'ctfpga 未编译，请先运行 tools/build_ctfpga.sh。'
            self.changed.emit()
            return
        case = self.root / 'data' / 'ctfpga-cases' / datetime.now().strftime('%Y%m%d-%H%M%S')
        case.mkdir(parents=True, exist_ok=True)
        self._case = case
        self._log = (case / 'ctfpga.log').open('w', encoding='utf-8')
        self._busy, self._cancelled, self._buffer = True, False, ''
        self._stages = self._empty_stages()
        self._started = monotonic()
        self._status = '正在启动 ctfpga…'
        self.process.setWorkingDirectory(str(self.root))
        self.process.start('bash', [str(self.root / 'tools' / 'ctfpga.sh'), *arguments, '--case-dir', str(case)])
        self._timer.start()
        self.changed.emit()

    def _poll(self):
        try:
            table = json.loads((self._case / 'status.json').read_text(encoding='utf-8'))
        except (OSError, ValueError, TypeError):
            table = {}
        if table:
            self._stages = [{'key': key, 'label': label,
                             'status': str(table.get(key, {}).get('status', 'Queue')),
                             'detail': str(table.get(key, {}).get('detail', ''))}
                            for key, label in STAGES]
        self.changed.emit()

    def _read(self):
        text = bytes(self.process.readAllStandardOutput()).decode('utf-8', errors='replace')
        if self._log:
            self._log.write(text)
            self._log.flush()
        self._buffer = (self._buffer + text)[-12000:]
        lines = [line.strip() for line in self._buffer.splitlines() if line.strip()]
        if lines:
            self._status = lines[-1][:300]
            self.changed.emit()

    def _close_log(self):
        if self._log:
            self._log.close()
            self._log = None

    def _error(self, error):
        if error == QProcess.FailedToStart:
            self._timer.stop()
            self._ended = monotonic()
            self._busy = False
            self._status = 'ctfpga 无法启动，请检查 tools/ctfpga.sh。'
            self._close_log()
            self.changed.emit()

    def _finished(self, code, exit_status):
        self._read()
        self._timer.stop()
        self._poll()
        self._close_log()
        self._ended = monotonic()
        self._busy = False
        log = self._case / 'ctfpga.log'
        if self._cancelled:
            self._status = f'已取消；已完成的阶段保留在 {self._case}'
        elif code or exit_status != QProcess.NormalExit:
            failed = [line for line in self._buffer.splitlines() if line.startswith('[FAILED]')]
            detail = failed[-1][len('[FAILED]'):].strip() if failed else '进程异常退出'
            stage = next((s['label'] for s in self._stages if s['status'] == 'Failed'), '')
            self._status = f'{stage + " " if stage else ""}失败：{detail}。日志：{log}'
        else:
            cut = self._case / 'stl' / 'cut'
            # ctfpga writes cut/{airway,lobes,tumor,vessels}/*.stl.
            if any(cut.rglob('*.stl')):
                self._status = f'完成，用时 {self._elapsed_text()}，正在载入 {cut}'
                self.viewer.loadDirectory(str(cut))
            else:
                self._status = f'流程结束但 {cut} 中没有 STL。日志：{log}'
        self.changed.emit()

    @Slot()
    def cancel(self):
        if self._busy:
            self._cancelled = True
            self.process.kill()

    def shutdown(self):
        self.cancel()
        if self.process.state() != QProcess.NotRunning:
            self.process.waitForFinished(3000)
        self._close_log()
