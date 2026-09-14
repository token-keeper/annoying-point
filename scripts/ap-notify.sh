#!/usr/bin/env bash
# annoying-point SessionStart 알림 — $AP_HOME/inbox 의 md 개수를 1줄로 알린다 (docs/TECH_SPEC.md §6). LLM 미개입.
# 호출: bash ap-notify.sh [--agent claude|codex|cursor]  (stdin 은 읽고 버린다). 0건·디렉토리 없음 → 무출력. 어떤 경우도 exit 0.
# 출력: Claude·Codex {"systemMessage":"…"} — 둘 다 화면 표시 경로(plain stdout 은 모델 컨텍스트로만 감, 공식 문서 2026-09-14 확인)
#       Cursor {"additional_context":"…"} — sessionStart 는 user_message 미적용이라 모델 컨텍스트에만 넣는다
umask 077
set -uo pipefail
AGENT="claude"; [ "${1:-}" = "--agent" ] && AGENT="${2:-claude}"
[ -t 0 ] || cat >/dev/null  # 훅 입력은 안 쓴다 — 읽고 버려 CLI 쪽 EPIPE 방지

# AP_HOME 해석 (§4.3) — 훅과 같은 규칙
ap_home() {
  [ -n "${AP_HOME:-}" ] && { echo "$AP_HOME"; return; }
  local v; v="$(sed -n 's/^AP_HOME=//p' "$HOME/.config/ap/config" 2>/dev/null | head -1)"
  v="${v/#\~/$HOME}"; echo "${v:-$HOME/.local/share/ap}"
}

INBOX="$(ap_home)/inbox"
[ -d "$INBOX" ] || exit 0
N=0; LAST=""
for f in "$INBOX"/*.md; do [ -f "$f" ] || continue; N=$((N+1)); LAST="${f##*/}"; done  # glob 은 이름순 → 마지막 = 최근
[ "$N" -gt 0 ] || exit 0
RECENT="${LAST:5:5}"; case "$RECENT" in [0-9][0-9]-[0-9][0-9]) ;; *) RECENT="-" ;; esac  # 파일명 YYYY-MM-DD_… 의 MM-DD, 형식 밖이면 -
MSG="📌 ap inbox ${N}건 (최근 $RECENT)"
# 메시지는 숫자·고정 문구뿐이라 jq 없이 그대로 JSON 에 넣는다
if [ "$AGENT" = cursor ]; then printf '{"additional_context":"%s"}\n' "$MSG"; else printf '{"systemMessage":"%s"}\n' "$MSG"; fi
exit 0
