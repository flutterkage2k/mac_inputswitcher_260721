#!/bin/bash
# 진단 로그를 프로젝트 안으로 매일 복사한다.
# ~/Library/Logs 는 정리하다 지우기 쉬운 위치라, 실험 데이터를 바깥에 이중 보관한다.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="$HOME/Library/Logs/InputSwitcher.log"
DEST="logs"
mkdir -p "$DEST"
cp "$SRC" "$DEST/$(date +%Y%m%d).log" 2>/dev/null || true
cp "$SRC.1" "$DEST/$(date +%Y%m%d)-prev.log" 2>/dev/null || true
# 60일 넘은 스냅샷은 정리
find "$DEST" -name '*.log' -mtime +60 -delete
