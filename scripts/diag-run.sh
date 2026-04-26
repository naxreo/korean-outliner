#!/usr/bin/env bash
#
# diag-run.sh — 진단 빌드를 실행하고 AX 이벤트 로그를 실시간으로 보여준다.
#
# 동작:
#   1. 기존 실행 중인 Korean Outliner 프로세스를 종료(권한이 충돌하지 않도록).
#   2. 진단 로그 파일을 비움.
#   3. Debug 빌드를 실행.
#   4. 로그 파일을 tail -f로 추적.
#
# 사용:
#   bash scripts/diag-run.sh
#
#   별도 터미널에서:
#     - iTerm 창 두 개 띄우고 한쪽 닫는 시나리오 재현
#     - 단축키로 다른 앱 실행 시나리오 재현
#
#   Ctrl+C로 종료. 로그는 보존됨.
#
# 로그 위치:
#   ~/Library/Logs/KoreanOutliner/focus-tracker.log
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$HOME/Library/Logs/KoreanOutliner/focus-tracker.log"
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/KoreanOutliner-aquavhwuxrorxhgksjowdkngjdcu/Build/Products/Debug/Korean Outliner.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo ">>> Debug build not found at $APP_PATH"
    echo ">>> building..."
    cd "$ROOT_DIR"
    xcodebuild -project KoreanOutliner.xcodeproj -scheme KoreanOutliner \
        -configuration Debug build >/dev/null
fi

echo ">>> killing any existing Korean Outliner instance"
pkill -f "Korean Outliner.app/Contents/MacOS" 2>/dev/null || true
sleep 0.5

mkdir -p "$(dirname "$LOG")"
: > "$LOG"

echo ">>> launching: $APP_PATH (KO_DIAG=1)"
# 환경변수를 자식 프로세스로 전달하기 위해 --env 옵션 사용. KO_DIAG=1 이
# 설정된 경우에만 DiagLogger가 동작한다.
open -n --env KO_DIAG=1 "$APP_PATH"

echo ""
echo ">>> tailing $LOG"
echo ">>> reproduce the scenario in another window. Ctrl+C to stop tailing (app keeps running)."
echo ""
exec tail -f "$LOG"
