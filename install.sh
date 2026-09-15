#!/usr/bin/env bash
# annoying-point 설치 — Codex·Cursor 훅 등록(캡처·SessionStart 알림) + $AP_HOME 생성 (+ --skills 스킬 심링크). 재실행 멱등 (docs/TECH_SPEC.md §8).
# Claude 는 플러그인 설치(hooks/hooks.json)로 자동 등록되므로 이 스크립트가 필요 없다.
# 사용: bash install.sh [--skills] [--dry-run]
#   --skills   ~/.agents/skills·~/.cursor/skills 에 add·review 심링크 (기본 스킵 — 그 디렉토리가 다른 repo 로 가는 심링크인 환경이 있다)
#   --dry-run  바뀔 JSON 만 stdout 에 출력, 파일·디렉토리는 손대지 않는다
set -uo pipefail
umask 077
command -v jq >/dev/null 2>&1 || { echo "jq 가 필요하다: brew install jq"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAP="$ROOT/scripts/ap-capture.sh"; NOTIFY="$ROOT/scripts/ap-notify.sh"
SKILLS=0; DRY=0; ERR=0; TOUCHED=""; BROKEN=""; TS="$(date +%Y%m%d%H%M%S)"
for a in "$@"; do case "$a" in --skills) SKILLS=1 ;; --dry-run) DRY=1 ;; *) echo "사용법: bash install.sh [--skills] [--dry-run]"; exit 1 ;; esac; done

# AP_HOME 해석 (§4.3) — 훅과 같은 규칙
ap_home() {
  [ -n "${AP_HOME:-}" ] && { echo "$AP_HOME"; return; }
  local v; v="$(sed -n 's/^AP_HOME=//p' "$HOME/.config/ap/config" 2>/dev/null | head -1)"
  v="${v/#\~/$HOME}"; echo "${v:-$HOME/.local/share/ap}"
}

# register <hooks.json> <스크립트 절대경로> <agent> <command 목록 jq> <추가 jq> — 같은 스크립트·agent 항목이 있으면(따옴표 형식이 달라도) 건너뛰고,
# 아니면 백업 후 병합. 기존 항목 보존. 경로는 셸 단일 인용으로 감싼다(공백·특수문자 안전). 쓰기는 임시 파일 → jq 검증 → mv
register() {
  local f="$1" script="$2" agent="$3" list="$4" add="$5" q c cur new tmp
  case " $BROKEN " in *" $f "*) echo "병합 실패($f): 앞 항목 실패 — 손대지 않음"; return 1 ;; esac  # 한 파일은 전부 아니면 전무
  q="$(printf '%s' "$script" | sed "s/'/'\\\\''/g")"; c="bash '$q' --agent $agent"
  cur="$( [ -s "$f" ] && cat "$f" || echo '{}' )"  # 0바이트는 {} 취급
  printf '%s' "$cur" | jq -e . >/dev/null 2>&1 || { echo "병합 실패($f): 올바른 JSON 이 아니다 — 손대지 않음"; return 1; }
  if printf '%s' "$cur" | jq -e --arg n "${script##*/}" --arg a " --agent $agent" "$list | any(contains(\$n) and endswith(\$a))" >/dev/null; then echo "이미 있음: $f"; return 0; fi
  new="$(printf '%s' "$cur" | jq --arg c "$c" "$add" 2>/dev/null)" && [ -n "$new" ] || { BROKEN="$BROKEN $f"; echo "병합 실패($f): 기존 구조가 예상과 다르다 — 손대지 않음"; return 1; }
  if [ "$DRY" = 1 ]; then echo "[dry-run] $f →"; printf '%s\n' "$new"; return 0; fi
  mkdir -p "$(dirname "$f")" || { echo "병합 실패($f): 디렉토리 생성 불가"; return 1; }
  # 백업은 실행당 파일별 1회 — 같은 파일에 두 번째 항목을 넣을 때 방금 쓴 중간 상태를 또 백업하지 않는다
  case " $TOUCHED " in *" $f "*) ;; *) TOUCHED="$TOUCHED $f"
    [ -f "$f" ] && { cp "$f" "$f.bak-$TS" && echo "백업: $f.bak-$TS" || { echo "병합 실패($f): 백업 불가 — 손대지 않음"; return 1; }; } ;; esac
  tmp="$(mktemp "$f.tmp.XXXXXX")" || { echo "병합 실패($f): 임시 파일 불가"; return 1; }
  if printf '%s\n' "$new" > "$tmp" && jq -e . "$tmp" >/dev/null 2>&1 && mv "$tmp" "$f"; then echo "추가: $f"
  else rm -f "$tmp"; echo "병합 실패($f): 쓰기 불가 — 손대지 않음"; return 1; fi
}

# ② Codex ~/.codex/hooks.json — Claude 와 같은 형식 {hooks:{<이벤트>:[{hooks:[{type,command,timeout}]}]}}. 캡처 + SessionStart 알림
register "$HOME/.codex/hooks.json" "$CAP" codex \
  '[.hooks.UserPromptSubmit[]?.hooks[]?.command // empty]' \
  '.hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{hooks:[{type:"command",command:$c,timeout:5}]}])' || ERR=1
register "$HOME/.codex/hooks.json" "$NOTIFY" codex \
  '[.hooks.SessionStart[]?.hooks[]?.command // empty]' \
  '.hooks.SessionStart = ((.hooks.SessionStart // []) + [{hooks:[{type:"command",command:$c,timeout:5}]}])' || ERR=1
# ③ Cursor ~/.cursor/hooks.json — {hooks:{<이벤트>:[{command,timeout}]},version:1}. 캡처(beforeSubmitPrompt) + 알림(sessionStart, additional_context 만 가능)
register "$HOME/.cursor/hooks.json" "$CAP" cursor \
  '[.hooks.beforeSubmitPrompt[]?.command // empty]' \
  '.hooks.beforeSubmitPrompt = ((.hooks.beforeSubmitPrompt // []) + [{command:$c,timeout:10}]) | .version //= 1' || ERR=1
register "$HOME/.cursor/hooks.json" "$NOTIFY" cursor \
  '[.hooks.sessionStart[]?.command // empty]' \
  '.hooks.sessionStart = ((.hooks.sessionStart // []) + [{command:$c,timeout:5}]) | .version //= 1' || ERR=1

# ④ $AP_HOME/{inbox,processed,log} — umask 077 로 700
D="$(ap_home)"
if [ "${D#"$HOME"/}" = "$D" ]; then echo "경고: AP_HOME 이 홈 밖이라 훅이 저장을 거부한다 — 디렉토리를 만들지 않음: $D"
elif [ "$DRY" = 1 ]; then echo "[dry-run] AP_HOME: $D/{inbox,processed,log}"
else mkdir -p "$D/inbox" "$D/processed" "$D/log" && echo "AP_HOME: $D"; fi

# ⑤ 스킬 심링크 (옵션) — ~/.agents/skills(Codex) · ~/.cursor/skills(Cursor) → repo skills/add · skills/review
if [ "$SKILLS" = 1 ]; then
  for d in "$HOME/.agents/skills" "$HOME/.cursor/skills"; do
    [ -L "$d" ] && echo "주의: $d 는 심링크 → $(readlink "$d")"
    for sk in add review; do
      if [ ! -d "$ROOT/skills/$sk" ]; then echo "스킬 심링크: 스킵 — $ROOT/skills/$sk 없음"
      elif [ -d "$d/$sk" ] && [ ! -L "$d/$sk" ]; then echo "실제 디렉토리 존재 — 스킵: $d/$sk"  # ln -sfn 이 그 안에 링크를 만들어 버린다
      elif [ "$DRY" = 1 ]; then echo "[dry-run] $d/$sk → $ROOT/skills/$sk"
      else mkdir -p "$d" && ln -sfn "$ROOT/skills/$sk" "$d/$sk" && echo "심링크: $d/$sk"; fi
    done
  done
else echo "스킬 심링크: 스킵 (--skills 로 실행)"; fi
echo "Codex: 다음 세션 시작 때 훅 승인(trust) 프롬프트에 Yes"  # 첫 실행 시 [hooks.state] 에 trusted_hash 가 기록되기 전이라 뜬다(실측)
exit "$ERR"
