#!/usr/bin/env bash
#
# iterm-close-scenario.sh — iTerm 두 창 띄우기 → 한쪽 닫기 시나리오를 자동
# 재현하면서 ax-inspect.swift로 AX 알림 스트림을 캡처한다.
#
# 결과:
#   build/diag/iterm-<timestamp>.log
#
# 검증 포인트:
#   1. 윈도우 파괴 시 어떤 알림이 발생하는가?
#      - kAXUIElementDestroyedNotification?
#      - kAXFocusedWindowChangedNotification?
#      - 둘 다 / 둘 다 아님?
#   2. 파괴 직후 kAXFocusedWindow 질의 결과는 nil인가, stale window인가, 새 윈도우인가?
#   3. 그 결과가 시간이 지남에 따라 어떻게 바뀌는가?
#
# 권한 요구사항:
#   - 이 스크립트를 실행하는 셸(또는 그 부모 앱)에 Accessibility / Automation 권한
#   - System Settings → Privacy & Security → Accessibility, Automation 모두 확인
#
# Usage:
#   bash scripts/iterm-close-scenario.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/build/diag"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$LOG_DIR/iterm-$TS.log"

echo ">>> log: $LOG"

# Step 1. 기존 iTerm 창 정리(있다면) — 깨끗한 시작 상태를 위해.
osascript <<'EOF' || true
tell application "iTerm"
    if (count of windows) > 0 then
        repeat (count of windows) times
            close first window
        end repeat
    end if
end tell
EOF

# Step 2. iTerm 활성화 + 첫 번째 창 생성.
osascript <<'EOF'
tell application "iTerm"
    activate
    create window with default profile
end tell
EOF

sleep 1

# iTerm이 살아있는지 확인 후 inspector 시작.
if ! pgrep -x "iTerm2" >/dev/null && ! pgrep -x "iTerm" >/dev/null; then
    echo "ERROR: iTerm 프로세스를 찾지 못했습니다."
    exit 1
fi

echo ">>> starting ax-inspect for com.googlecode.iterm2"
xcrun swift "$ROOT_DIR/scripts/ax-inspect.swift" com.googlecode.iterm2 \
    > "$LOG" 2>&1 &
INSPECTOR_PID=$!
trap 'kill $INSPECTOR_PID 2>/dev/null || true' EXIT

# inspector가 observer 등록을 마치도록 약간 대기.
sleep 1

echo ">>> [event] creating second iTerm window"
echo "--- HARNESS: creating second window at $(date +%H:%M:%S.%N | cut -c1-12)" >> "$LOG"
osascript <<'EOF'
tell application "iTerm"
    create window with default profile
end tell
EOF
sleep 2

echo ">>> [event] closing front iTerm window via System Events Cmd+W (close current session/window)"
echo "--- HARNESS: closing front window at $(date +%H:%M:%S.%N | cut -c1-12)" >> "$LOG"
# AppleScript의 'close current window' 보다 사용자가 실제로 누르는 Cmd+W를
# 흉내내는 키 이벤트가 더 충실하게 재현된다(iTerm이 다르게 처리할 수 있음).
osascript <<'EOF'
tell application "System Events"
    tell process "iTerm2"
        keystroke "w" using command down
    end tell
end tell
EOF

# 닫힘 후 시스템이 포커스를 옮길 시간을 충분히 확보(우리 retry 백오프 최대 400ms +
# 여유). 1.5초 동안 발생하는 모든 이벤트를 잡는다.
sleep 1.5

echo ">>> [event] sampling done. dumping last 80 lines of inspector output:"
echo "--- HARNESS: scenario complete at $(date +%H:%M:%S.%N | cut -c1-12)" >> "$LOG"

kill $INSPECTOR_PID 2>/dev/null || true
wait $INSPECTOR_PID 2>/dev/null || true

echo ""
echo "=========================== inspector log ==========================="
tail -80 "$LOG"
echo "====================================================================="
echo ""
echo "full log saved to: $LOG"
