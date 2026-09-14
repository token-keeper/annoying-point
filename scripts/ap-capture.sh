#!/usr/bin/env bash
# annoying-point 캡처 훅 — "/ap <한마디>" 를 가로채 $AP_HOME/inbox 에 md 로 저장하고 block 한다.
# Claude 는 UserPromptSubmit(플레인 /ap·$ap) + UserPromptExpansion(플러그인 커맨드 /annoying-point:ap) 두 이벤트에 같은 스크립트를 건다.
# 트랜스크립트는 읽지 않는다. 어떤 경우에도 exit 0 또는 block 으로 끝난다 (docs/TECH_SPEC.md §3·§4·§9).
# 호출: bash ap-capture.sh --agent claude|codex|cursor   (기본 claude, stdin = 훅 입력 JSON)
umask 077
set -uo pipefail

AGENT="claude"
[ "${1:-}" = "--agent" ] && AGENT="${2:-claude}"
USAGE="📌 ap 사용법: /ap <한마디> · /ap +<좋은점>"

# AP_HOME 해석 (§4.3): env → ~/.config/ap/config 의 AP_HOME= 첫 줄(~ → $HOME) → ~/.local/share/ap
ap_home() {
  [ -n "${AP_HOME:-}" ] && { echo "$AP_HOME"; return; }
  local v; v="$(sed -n 's/^AP_HOME=//p' "$HOME/.config/ap/config" 2>/dev/null | head -1)"
  v="${v/#\~/$HOME}"; echo "${v:-$HOME/.local/share/ap}"
}

# 앞뒤 공백 제거 (bash 3.2 파라미터 확장만 사용)
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }
# 첫 토큰(/ap·$ap·/annoying-point:ap) 을 뗀 나머지
after_head() { printf '%s' "${1#"${1%%[[:space:]]*}"}"; }

# $1=문구 — jq --arg 로 이스케이프해 block JSON 을 내고 종료
block() {
  jq -n --arg r "$1" '{decision:"block",reason:$r}'  # TODO 커밋3: cursor 는 {continue:false,user_message:$r}
  exit 0
}

INPUT="$(cat)"  # jq 확인보다 먼저 읽어 어떤 경로에서도 stdin 을 소비하고 끝낸다 (CLI 쪽 EPIPE 방지)
command -v jq >/dev/null 2>&1 || exit 0
PROMPT="$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)" || exit 0
CMD="$(printf '%s' "$INPUT" | jq -r '.command_name // empty')"  # UserPromptExpansion(플러그인 커맨드) 에만 있음

if [ -n "$CMD" ]; then
  # 플러그인 커맨드는 command_name 으로만 판정 — prompt 접두 매칭으로 타 커맨드를 삼키지 않는다 (wdis 선례)
  case "${CMD#/}" in ap|annoying-point:ap) ;; *) exit 0 ;; esac
  TEXT="$(printf '%s' "$INPUT" | jq -r '.command_args // empty')"
  # command_args 없으면 prompt 에서 — prompt 는 "/ap x" 일 수도 인자만("x") 일 수도 있다
  [ -n "$TEXT" ] || case "$PROMPT" in /*) TEXT="$(after_head "$PROMPT")" ;; *) TEXT="$PROMPT" ;; esac
else
  # 플레인 프롬프트: /ap·$ap·/annoying-point:ap 만 캡처. /ap-review 등은 통과 (bash 3.2 는 \s 미지원 → [[:space:]])
  RE='^([/$]ap|/annoying-point:ap)([[:space:]]|$)'
  [[ $PROMPT =~ $RE ]] || exit 0
  TEXT="$(after_head "$PROMPT")"
fi

# 줄바꿈은 공백 치환 → 트림. "+" 접두면 good
TEXT="$(trim "${TEXT//[$'\r\n']/ }")"
KIND="annoying"
case "$TEXT" in +*) KIND="good"; TEXT="$(trim "${TEXT#+}")" ;; esac
[ -z "$TEXT" ] && block "$USAGE"

SESSION="$(printf '%s' "$INPUT" | jq -r '.session_id // empty')"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // "-"')"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"; CWD="${CWD:-$PWD}"
REPO="$(basename "$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)"
REPO="${REPO:-$(basename "$CWD")}"
BRANCH="$(git -C "$CWD" branch --show-current 2>/dev/null)"; BRANCH="${BRANCH:--}"

# 저장 (§4) — $HOME 아래만 허용, 디렉토리 700·파일 600 은 umask, noclobber 로 덮어쓰기 방지
DIR="$(ap_home)"
FAIL="📌 ap 저장 실패 ($DIR 쓰기 불가) — 원문: $PROMPT"
case "$DIR" in "$HOME"/*) ;; *) block "$FAIL" ;; esac
mkdir -p "$DIR/inbox" "$DIR/processed" "$DIR/log" 2>/dev/null || block "$FAIL"
ID="$(date +%Y-%m-%d_%H%M%S)_${AGENT}_${REPO}_$(head -c2 /dev/urandom | xxd -p)"
MD="$DIR/inbox/$ID.md"
( set -C; printf '%s\n' "---" "ts: $(date '+%Y-%m-%d %H:%M')" "agent: $AGENT" "kind: $KIND" \
  "repo: $REPO" "branch: $BRANCH" "cwd: $CWD" "session: $SESSION" "transcript: $TRANSCRIPT" \
  "target:" "context: pending" "---" "$TEXT" > "$MD" ) 2>/dev/null || block "$FAIL"

# 포크 기동 (§5.1) — 런처 stdout·stderr 는 log/<id>.log 로. session 없으면 기동 생략
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$DIR/log/$ID.log"
if [ -z "$SESSION" ]; then
  echo "no session" >> "$LOG"
elif [ -f "$SCRIPT_DIR/ap-fork.sh" ]; then
  ( nohup bash "$SCRIPT_DIR/ap-fork.sh" "$MD" </dev/null >>"$LOG" 2>&1 & )
fi
block "📌 ap #$ID 저장 · context 생성 중"
