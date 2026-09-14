#!/usr/bin/env bash
# annoying-point 설치 — Codex·Cursor 훅 등록 + $AP_HOME 생성 (+ --skills 스킬 심링크). 재실행 멱등 (docs/TECH_SPEC.md §8).
# Claude 는 플러그인 설치(hooks/hooks.json)로 자동 등록되므로 이 스크립트가 필요 없다.
# 사용: bash install.sh [--skills] [--dry-run]
#   --skills   ~/.agents/skills·~/.cursor/skills 에 ap-review 심링크 (기본 스킵 — 그 디렉토리가 다른 repo 로 가는 심링크인 환경이 있다)
#   --dry-run  바뀔 JSON 만 stdout 에 출력, 파일·디렉토리는 손대지 않는다
set -uo pipefail
umask 077
command -v jq >/dev/null 2>&1 || { echo "jq 가 필요하다: brew install jq"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAP="$ROOT/scripts/ap-capture.sh"
SKILLS=0; DRY=0; ERR=0; TS="$(date +%Y%m%d%H%M%S)"
for a in "$@"; do case "$a" in --skills) SKILLS=1 ;; --dry-run) DRY=1 ;; *) echo "사용법: bash install.sh [--skills] [--dry-run]"; exit 1 ;; esac; done

# AP_HOME 해석 (§4.3) — 훅과 같은 규칙
ap_home() {
  [ -n "${AP_HOME:-}" ] && { echo "$AP_HOME"; return; }
  local v; v="$(sed -n 's/^AP_HOME=//p' "$HOME/.config/ap/config" 2>/dev/null | head -1)"
  v="${v/#\~/$HOME}"; echo "${v:-$HOME/.local/share/ap}"
}

# register <hooks.json> <command 문자열> <있음 판정 jq> <추가 jq> — 같은 command 가 있으면 건너뛰고, 아니면 백업 후 병합. 기존 항목 보존
register() {
  local f="$1" c="$2" cur new
  cur="$( [ -f "$f" ] && cat "$f" || echo '{}' )"
  printf '%s' "$cur" | jq -e . >/dev/null 2>&1 || { echo "병합 실패: $f 가 올바른 JSON 이 아니다 — 손대지 않음"; return 1; }
  if printf '%s' "$cur" | jq -e --arg c "$c" "$3" >/dev/null; then echo "이미 있음: $f"; return 0; fi
  new="$(printf '%s' "$cur" | jq --arg c "$c" "$4")"
  if [ "$DRY" = 1 ]; then echo "[dry-run] $f →"; printf '%s\n' "$new"; return 0; fi
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] && { cp "$f" "$f.bak-$TS"; echo "백업: $f.bak-$TS"; }
  printf '%s\n' "$new" > "$f" && echo "추가: $f"
}

# ② Codex ~/.codex/hooks.json — Claude 와 같은 형식 {hooks:{UserPromptSubmit:[{hooks:[{type,command,timeout}]}]}}
#    (SessionStart 알림 등록은 커밋 4 에서 여기에 추가)
register "$HOME/.codex/hooks.json" "bash \"$CAP\" --agent codex" \
  '[.hooks.UserPromptSubmit[]?.hooks[]?.command // empty] | index($c) != null' \
  '.hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{hooks:[{type:"command",command:$c,timeout:5}]}])' || ERR=1
# ③ Cursor ~/.cursor/hooks.json — {hooks:{beforeSubmitPrompt:[{command,timeout}]},version:1}
register "$HOME/.cursor/hooks.json" "bash \"$CAP\" --agent cursor" \
  '[.hooks.beforeSubmitPrompt[]?.command // empty] | index($c) != null' \
  '.hooks.beforeSubmitPrompt = ((.hooks.beforeSubmitPrompt // []) + [{command:$c,timeout:10}]) | .version //= 1' || ERR=1

# ④ $AP_HOME/{inbox,processed,log} — umask 077 로 700
D="$(ap_home)"
case "$D" in "$HOME"/*) ;; *) echo "경고: AP_HOME 이 홈 밖이라 훅이 저장을 거부한다: $D" ;; esac
if [ "$DRY" = 1 ]; then echo "[dry-run] AP_HOME: $D/{inbox,processed,log}"
else mkdir -p "$D/inbox" "$D/processed" "$D/log" && echo "AP_HOME: $D"; fi

# ⑤ 스킬 심링크 (옵션) — ~/.agents/skills(Codex) · ~/.cursor/skills(Cursor) → repo skills/ap-review
if [ "$SKILLS" = 1 ]; then
  if [ ! -d "$ROOT/skills/ap-review" ]; then echo "스킬 심링크: 스킵(커밋5) — $ROOT/skills/ap-review 없음"
  else for d in "$HOME/.agents/skills" "$HOME/.cursor/skills"; do
    [ -L "$d" ] && echo "주의: $d 는 심링크 → $(readlink "$d")"
    if [ "$DRY" = 1 ]; then echo "[dry-run] $d/ap-review → $ROOT/skills/ap-review"
    else mkdir -p "$d" && ln -sfn "$ROOT/skills/ap-review" "$d/ap-review" && echo "심링크: $d/ap-review"; fi
  done; fi
else echo "스킬 심링크: 스킵 (--skills 로 실행)"; fi
exit "$ERR"
