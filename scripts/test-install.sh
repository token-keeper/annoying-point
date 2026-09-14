#!/usr/bin/env bash
# install.sh 단위 테스트 — docs/PLAN.md 커밋 3 검증 1. HOME 을 임시 디렉토리로 바꿔 실행하므로 실제 ~/.codex·~/.cursor·~/.agents 는 건드리지 않는다.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INST="$ROOT_DIR/install.sh"
TMP="$(mktemp -d "$HOME/.ap-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1"; }
assert()     { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }
assert_has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (실제: $2)" ;; esac; }
CX_CMD="bash \"$ROOT_DIR/scripts/ap-capture.sh\" --agent codex"
CU_CMD="bash \"$ROOT_DIR/scripts/ap-capture.sh\" --agent cursor"

echo "== 1a: 새 HOME 에 설치"
H="$TMP/h1"; mkdir -p "$H"; OUT="$(HOME="$H" /bin/bash "$INST" 2>&1)"; RC=$?
assert "1a rc 0" [ "$RC" = 0 ]
assert "1a codex 항목 구조" [ "$(jq -c '.hooks.UserPromptSubmit[0].hooks[0] | [.type, .timeout]' "$H/.codex/hooks.json")" = '["command",5]' ]
assert "1a codex command 절대경로" [ "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$H/.codex/hooks.json")" = "$CX_CMD" ]
assert "1a cursor 항목 구조" [ "$(jq -c '.hooks.beforeSubmitPrompt[0] | [.command, .timeout]' "$H/.cursor/hooks.json")" = "[$(jq -cn --arg c "$CU_CMD" '$c'),10]" ]
assert "1a cursor version 1" [ "$(jq -r .version "$H/.cursor/hooks.json")" = 1 ]
assert "1a cursor 항목에 type 없음" [ "$(jq -r '.hooks.beforeSubmitPrompt[0] | has("type")' "$H/.cursor/hooks.json")" = false ]
assert "1a AP_HOME 3개 700" [ "$(stat -f %Lp "$H/.local/share/ap/inbox")$(stat -f %Lp "$H/.local/share/ap/processed")$(stat -f %Lp "$H/.local/share/ap/log")" = 700700700 ]
assert_has "1a 요약 출력 추가" "$OUT" "추가: $H/.codex/hooks.json"
assert_has "1a 스킬 기본 스킵" "$OUT" "스킬 심링크: 스킵 (--skills"
assert "1a 실제 ~/.agents 무변경" [ ! -e "$H/.agents" ]

echo "== 1b: 재실행 멱등"
OUT="$(HOME="$H" /bin/bash "$INST" 2>&1)"
assert "1b UserPromptSubmit 길이 1 유지" [ "$(jq '.hooks.UserPromptSubmit|length' "$H/.codex/hooks.json")" = 1 ]
assert "1b beforeSubmitPrompt 길이 1 유지" [ "$(jq '.hooks.beforeSubmitPrompt|length' "$H/.cursor/hooks.json")" = 1 ]
assert_has "1b 이미 있음 출력" "$OUT" "이미 있음: $H/.cursor/hooks.json"
assert "1b 재실행 시 백업 없음" [ -z "$(ls "$H/.codex/" | grep bak)" ]

echo "== 1c: 기존 항목 있는 hooks.json 보존 + 백업"
H="$TMP/h2"; mkdir -p "$H/.codex" "$H/.cursor"
printf '%s' '{"hooks":{"UserPromptSubmit":[{"hooks":[]},{"hooks":[{"type":"command","command":"echo other","timeout":10}]}],"PreToolUse":[{"hooks":[]}]}}' > "$H/.codex/hooks.json"
printf '%s' '{"hooks":{"beforeSubmitPrompt":[{"command":"echo other","timeout":10}],"stop":[{"command":"echo s","timeout":10}]},"version":1}' > "$H/.cursor/hooks.json"
OUT="$(HOME="$H" /bin/bash "$INST" 2>&1)"
assert "1c codex 기존 2 + 우리 1 = 3" [ "$(jq '.hooks.UserPromptSubmit|length' "$H/.codex/hooks.json")" = 3 ]
assert "1c codex 기존 항목 보존" [ "$(jq -r '.hooks.UserPromptSubmit[1].hooks[0].command' "$H/.codex/hooks.json")" = "echo other" ]
assert "1c codex 다른 이벤트 보존" [ "$(jq -c '.hooks.PreToolUse' "$H/.codex/hooks.json")" = '[{"hooks":[]}]' ]
assert "1c codex 우리 항목 마지막" [ "$(jq -r '.hooks.UserPromptSubmit[2].hooks[0].command' "$H/.codex/hooks.json")" = "$CX_CMD" ]
assert "1c cursor 기존 1 + 우리 1 = 2" [ "$(jq '.hooks.beforeSubmitPrompt|length' "$H/.cursor/hooks.json")" = 2 ]
assert "1c cursor stop 보존" [ "$(jq -r '.hooks.stop[0].command' "$H/.cursor/hooks.json")" = "echo s" ]
assert "1c 백업 파일 생성" [ "$(ls "$H/.codex/" | grep -c 'hooks.json.bak-')" = 1 ]
assert "1c 백업 = 원본" [ "$(cat "$H"/.codex/hooks.json.bak-* | jq -c .)" = "$(printf '%s' '{"hooks":{"UserPromptSubmit":[{"hooks":[]},{"hooks":[{"type":"command","command":"echo other","timeout":10}]}],"PreToolUse":[{"hooks":[]}]}}' | jq -c .)" ]
assert_has "1c 백업 출력" "$OUT" "백업: $H/.codex/hooks.json.bak-"

echo "== 1d: --dry-run 무변경"
H="$TMP/h3"; mkdir -p "$H"; OUT="$(HOME="$H" /bin/bash "$INST" --dry-run 2>&1)"; RC=$?
assert "1d rc 0" [ "$RC" = 0 ]
assert "1d 파일 미생성" [ ! -e "$H/.codex" -a ! -e "$H/.cursor" -a ! -e "$H/.local" ]
assert_has "1d 바뀔 JSON 출력" "$OUT" "[dry-run] $H/.codex/hooks.json"
assert_has "1d JSON 본문 포함" "$OUT" "--agent codex"

echo "== 1e: 잘못된 JSON 은 손대지 않음"
H="$TMP/h4"; mkdir -p "$H/.codex"; printf 'not json' > "$H/.codex/hooks.json"
OUT="$(HOME="$H" /bin/bash "$INST" 2>&1)"; RC=$?
assert "1e rc ≠ 0" [ "$RC" != 0 ]; assert_has "1e 병합 실패 메시지" "$OUT" "병합 실패"
assert "1e 원본 그대로" [ "$(cat "$H/.codex/hooks.json")" = "not json" ]
assert "1e cursor 쪽은 진행" [ -f "$H/.cursor/hooks.json" ]

echo "== 1f: jq 없음"
H="$TMP/h5"; mkdir -p "$H"; OUT="$(HOME="$H" PATH=/bin /bin/bash "$INST" 2>&1)"; RC=$?
assert "1f exit 1" [ "$RC" = 1 ]; assert_has "1f 안내" "$OUT" "brew install jq"

echo "== 1g: --skills (repo 사본으로 심링크 경로 검증)"
R="$TMP/repo"; mkdir -p "$R/scripts" "$R/skills/ap-review"; cp "$INST" "$R/"; touch "$R/scripts/ap-capture.sh" "$R/skills/ap-review/SKILL.md"
H="$TMP/h6"; mkdir -p "$H/.real-skills"; mkdir -p "$H/.agents"; ln -s "$H/.real-skills" "$H/.agents/skills"
OUT="$(HOME="$H" /bin/bash "$R/install.sh" --skills 2>&1)"
assert "1g agents 심링크" [ "$(readlink "$H/.agents/skills/ap-review")" = "$R/skills/ap-review" ]
assert "1g cursor 심링크" [ "$(readlink "$H/.cursor/skills/ap-review")" = "$R/skills/ap-review" ]
assert_has "1g 심링크 디렉토리 주의 출력" "$OUT" "주의: $H/.agents/skills 는 심링크 → $H/.real-skills"
OUT="$(HOME="$H" /bin/bash "$R/install.sh" --skills 2>&1)"
assert "1g 재실행 후에도 링크 1개" [ "$(ls "$H/.real-skills" | wc -l | tr -d ' ')" = 1 ]
OUT="$(HOME="$TMP/h7" /bin/bash "$INST" --skills 2>&1)"
assert_has "1g 원본 repo 는 skills 없음 → 스킵(커밋5)" "$OUT" "스킵(커밋5)"
assert "1g 사용법 오류" [ "$(HOME="$TMP/h8" /bin/bash "$INST" --nope >/dev/null 2>&1; echo $?)" = 1 ]

echo "== $PASS/$((PASS+FAIL)) 통과"
[ "$FAIL" = 0 ]
