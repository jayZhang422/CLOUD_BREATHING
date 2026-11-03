#!/bin/bash
# Record the board display (KMS scanout) to data/recordings/*.mp4.
#   bash tools/screen_record.sh start [fps] [size]   default 10 fps, 1920:1080
#   bash tools/screen_record.sh stop
#   bash tools/screen_record.sh status
# Encoding uses the CPU (libx264 ultrafast, about one core at 10 fps), so
# planning timings measured while recording run somewhat slower.
# Frames go to a Matroska file first (readable even if recording is cut off),
# and stop remuxes it to MP4 without re-encoding.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/data/recordings"
PID_FILE="$OUT_DIR/.recording.pid"
NAME_FILE="$OUT_DIR/.recording.file"
mkdir -p "$OUT_DIR"

running() { [ -s "$PID_FILE" ] && sudo -n kill -0 "$(cat "$PID_FILE")" 2>/dev/null; }

case "${1:-}" in
  start)
    if running; then echo "已在录屏：$(cat "$NAME_FILE")"; exit 0; fi
    fps="${2:-10}"; size="${3:-1920:1080}"
    base="$OUT_DIR/screen-$(date +%Y%m%d-%H%M%S)"
    echo "$base" > "$NAME_FILE"
    sudo -n setsid ffmpeg -nostdin -hide_banner -loglevel error -y -device /dev/dri/card0 -f kmsgrab \
      -format bgra -framerate "$fps" -i - -vf "hwdownload,format=bgra,scale=$size" \
      -c:v libx264 -preset ultrafast -tune zerolatency -crf 26 -pix_fmt yuv420p \
      "$base.mkv" > "$OUT_DIR/.recording.log" 2>&1 < /dev/null &
    sleep 2
    pgrep -n -x ffmpeg > "$PID_FILE" || true
    if running; then echo "开始录屏：$base.mp4"; else echo "录屏启动失败："; cat "$OUT_DIR/.recording.log"; exit 1; fi
    ;;
  stop)
    if ! running; then echo "当前没有录屏"; exit 0; fi
    pid="$(cat "$PID_FILE")"
    sudo -n kill -INT "$pid"
    for _ in $(seq 40); do sudo -n kill -0 "$pid" 2>/dev/null || break; sleep .5; done
    rm -f "$PID_FILE"
    base="$(cat "$NAME_FILE")"
    sudo -n chown "$(id -u):$(id -g)" "$base.mkv" 2>/dev/null || true
    if ffmpeg -nostdin -hide_banner -loglevel error -y -i "$base.mkv" -c copy -movflags +faststart "$base.mp4"; then
      rm -f "$base.mkv"
      echo "已保存：$base.mp4 ($(du -h "$base.mp4" | cut -f1))"
    else
      echo "转 MP4 失败，保留原始录像：$base.mkv"
    fi
    ;;
  status)
    if running; then echo "录屏中：$(cat "$NAME_FILE").mp4"; else echo "当前没有录屏"; fi
    ;;
  *) echo "用法：$0 start [fps] [size] | stop | status"; exit 2 ;;
esac
