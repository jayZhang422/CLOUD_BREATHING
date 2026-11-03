"""无第三方依赖的 Vivado 风格字符状态表。"""
from contextlib import contextmanager
from datetime import datetime
import os
from pathlib import Path
import sys
import unicodedata
from threading import Event, RLock, Thread
from time import monotonic

from .files import write_json

STAGES = ("CT2BIN", "Send", "Reasoning", "Receive", "BIN2STL", "Smooth", "Cut")


def cell(text, width):
    result, used = "", 0
    for char in str(text).replace("\n", " ").replace("\r", " "):
        size = 2 if unicodedata.east_asian_width(char) in ("W", "F") else 1
        if used + size > width:
            break
        result += char
        used += size
    return result + " " * (width-used)


class StatusTable:
    def __init__(self, report, live=None, stream=None):
        self.report, self.stream = Path(report), stream or sys.stdout
        self.live = self.stream.isatty() if live is None else live
        if self.live and os.name == "nt":
            import ctypes
            handle = ctypes.windll.kernel32.GetStdHandle(-11)
            mode = ctypes.c_ulong()
            if not ctypes.windll.kernel32.GetConsoleMode(handle, ctypes.byref(mode)) or not ctypes.windll.kernel32.SetConsoleMode(handle, mode.value | 4):
                self.live = False
        self.rows = {s:dict(status="Queue", start="--", elapsed_seconds=0., detail="", since=None) for s in STAGES}
        self.lock, self.stop = RLock(), Event()
        self.thread = None
        self.lines = 0
        self.last_detail_save = self.last_plain_detail = 0.

    def __enter__(self):
        self.draw()
        if self.live:
            self.thread = Thread(target=self._refresh, daemon=True)
            self.thread.start()
        return self

    def _refresh(self):
        while not self.stop.wait(.5):
            self.draw()

    def snapshot(self):
        now = monotonic()
        return {name:{**{k:v for k,v in row.items() if k != "since"},
                     "elapsed_seconds":row["elapsed_seconds"] + (now-row["since"] if row["since"] is not None else 0.)}
                for name,row in self.rows.items()}

    def set(self, name, status, detail=""):
        with self.lock:
            row = self.rows[name]
            if row["since"] is not None:
                row["elapsed_seconds"] += monotonic()-row["since"]
            if status == "ing":
                if row["start"] == "--":
                    row["start"] = datetime.now().astimezone().isoformat(timespec="seconds")
                row["since"] = monotonic()
            else:
                row["since"] = None
            row.update(status=status, detail=str(detail))
            self.draw()
            write_json(self.report, self.snapshot())

    def detail(self, name, text):
        with self.lock:
            self.rows[name]["detail"] = str(text)
            now = monotonic()
            if now-self.last_detail_save >= 1.:
                write_json(self.report, self.snapshot())
                self.last_detail_save = now
            if not self.live and now-self.last_plain_detail >= 5.:
                elapsed = self.snapshot()[name]['elapsed_seconds']
                self.stream.write(f"[{name}] {elapsed:.1f}s | {text}\n")
                self.stream.flush()
                self.last_plain_detail = now
        if self.live:
            self.draw()

    def draw(self):
        with self.lock:
            rows = self.snapshot()
            rule = "+------------+-----------+----------+-------------+--------------------------------------------------+"
            lines = [rule, "| Name       | Status    | Start    | Elapsed     | Detail                                           |", rule]
            for name,row in rows.items():
                start = row["start"][11:19] if row["start"] != "--" else "--"
                seconds = int(row["elapsed_seconds"])
                elapsed = f"{seconds//3600:02}:{seconds//60%60:02}:{seconds%60:02}"
                detail = cell(row["detail"],48)
                lines.append(f"| {name:<10} | {row['status']:<9} | {start:<8} | {elapsed:>11} | {detail} |")
            lines.append(rule)
            if self.live and self.lines:
                self.stream.write(f"\x1b[{self.lines}F")
            self.stream.write("\n".join(lines) + "\n")
            self.stream.flush()
            self.lines = len(lines)

    @contextmanager
    def stage(self, name):
        self.set(name, "ing")
        try:
            yield lambda text: self.detail(name, text)
        except BaseException as exc:
            self.set(name, "Failed", str(exc))
            raise
        else:
            self.set(name, "Done", self.rows[name]["detail"])

    def __exit__(self, *exc):
        self.stop.set()
        if self.thread:
            self.thread.join()
        with self.lock:
            for row in self.rows.values():
                if row["status"] == "Queue":
                    row.update(status="Blocked" if exc[0] else "Skipped")
            write_json(self.report, self.snapshot())
            self.draw()
