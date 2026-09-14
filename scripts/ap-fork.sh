#!/usr/bin/env bash
# annoying-point 백그라운드 요약기 런처 — inbox md 하나를 받아 그 세션을 포크해 5섹션 context 를 붙인다 (docs/TECH_SPEC.md §5).
# 호출: bash ap-fork.sh <md>   (ap-capture.sh 가 nohup 으로 기동. stdout·stderr 는 이미 log/<id>.log)
# Claude 분기만 구현(Codex·Cursor 는 커밋 3). 어떤 실패도 context: failed + log 한 줄로 끝나며 md 본문은 손대지 않는다.
umask 077
set -uo pipefail

MD="${1:-}"
[ -f "$MD" ] || { echo "md 없음: $MD"; exit 1; }
AP_FORK_TIMEOUT="${AP_FORK_TIMEOUT:-300}"  # 포크 기한(초) — 초과 시 자식 kill → failed
AP_FORK_CMD="${AP_FORK_CMD:-claude}"       # 테스트용 — claude 대신 가짜 명령

# AP_HOME 해석 (§4.3) — ap-capture.sh 와 같은 규칙 (공용 파일 없이 복제)
ap_home() {
  [ -n "${AP_HOME:-}" ] && { echo "$AP_HOME"; return; }
  local v; v="$(sed -n 's/^AP_HOME=//p' "$HOME/.config/ap/config" 2>/dev/null | head -1)"
  v="${v/#\~/$HOME}"; echo "${v:-$HOME/.local/share/ap}"
}
# 앞뒤 공백 제거
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }
# frontmatter 한 줄 규약 읽기 (§4.2): key: 뒤 줄 끝까지, 첫 줄만
field() { sed -n "s/^$1: //p" "$MD" | head -1; }
# $1=조립된 임시 파일 → 기존 inode 에 덮어쓴다 (mv 금지). md 가 이미 processed 로 이동됐으면 재생성하지 않는다 (§5.5-5)
commit_md() {
  if [ -e "$MD" ]; then cat "$1" > "$MD"; rm -f "$1"; else rm -f "$1"; echo "moved before context"; exit 0; fi
}
# frontmatter 구간(첫 --- ~ 둘째 ---)의 key 값 교체 — target·context 공용. 값의 sed 특수문자(& | \)는 이스케이프
set_field() {
  local v tmp; v="$(printf '%s' "$2" | sed 's/[&|\\]/\\&/g')"; tmp="$(mktemp "$LOG_DIR/.md.XXXXXX")"
  sed "2,/^---$/s|^$1:.*|$1: $v|" "$MD" > "$tmp"; commit_md "$tmp"
}
# $1=단계명 $2=원문(앞 200자만 log) → context: failed 후 종료
fail() { echo "$1${2:+: $(printf '%s' "$2" | head -c 200)}"; set_field context failed; exit 1; }

LOG_DIR="$(ap_home)/log"; mkdir -p "$LOG_DIR"

# 1. md 에서 frontmatter 4개 + 본문(둘째 --- 다음 줄 전부) — 단일 출처
AGENT="$(field agent)"; SESSION="$(field session)"; CWD="$(field cwd)"; KIND="$(field kind)"
TEXT="$(awk 'c>=2{print} /^---$/{c++}' "$MD")"
[ -n "$SESSION" ] || fail "no session"

# 2. 요약 지시 (§5.4 전문). /ap 로 시작하지 않아 포크 세션의 훅에 다시 잡히지 않는다
PROMPT="$(cat <<EOF
방금 이 세션에서 사용자가 다음 기록을 남겼다. 도구를 쓰지 말고, 지금까지의 이 대화 내용만 근거로 아래 형식의 텍스트만 출력하라. 인사·확인·질문·형식 밖의 문장은 쓰지 않는다.

종류: $KIND            (annoying = 짜증, good = 좋은점)
사용자 한마디: $TEXT

출력 형식 (한글, 제목 그대로, 첫 줄은 반드시 target):

target: <태그>
### 상황
### 경위
### 문제
### 추정 원인
### 근거

규칙:
- target 태그는 skill:<이름> / rule:<파일명> / tool:<이름>(orca, codex, tuist …) / model(AI 판단 자체) / env(환경·네트워크) 중 하나. 주 원인 1개를 앞에 두고, 여럿이면 쉼표로 잇는다 (예: target: skill:br-briefing, rule:code-review).
- 상황: 무슨 프로젝트·무슨 작업·어느 단계인지. 2줄 이내.
- 경위: 한마디 직전 3~5턴을 시간순으로. 턴마다 "누가 → 무엇을 했고 → 무엇이 나왔나" 1줄.
- 문제: 사용자 한마디를 구체화한다. 에러 원문·수치·파일명·표 크기 같은 실측을 그대로 인용한다. 종류가 good이면 무엇이 좋았는지를 같은 수준으로 구체화한다.
- 추정 원인: 어느 룰 파일·스킬·도구·모델 판단이 원인인지. 후보가 여럿이면 모두 적는다. good이면 어느 룰·스킬 덕분인지.
- 근거: 재현 명령·경로·직전 출력(도구·환경 문제일 때). 해당 없으면 "해당 없음" 한 줄.
- 길이: 룰 위반형이면 전체 5줄 안팎, 판단 오류·도구형이면 20줄 안팎. 상한 대신 기준은 하나 — 리뷰어가 트랜스크립트를 열지 않고도 판단할 수 있는 만큼.
EOF
)"

# 3. agent 별 포크 명령 (§5.2) — 모델·config 를 바꾸는 옵션은 붙이지 않는다 (§5.3 캐시 조건). 워치독은 §5.1
# disableAllHooks: 포크는 헤드리스 1회성이라 훅이 돌 이유가 없고, Stop 훅이 오래 살면(실측: cache-necromancer 50분) -p 가 안 끝난다.
# 시스템 프롬프트는 안 바뀌므로 캐시 prefix 유지 (실측은 test-fork.sh 검증 1 의 cache_read 비율)
case "$AGENT" in
  claude) CMD=("$AP_FORK_CMD" -p --settings '{"disableAllHooks":true}' --resume "$SESSION" --fork-session --output-format json "$PROMPT") ;;
  codex|cursor) fail "agent 미지원(커밋3)" "$AGENT" ;;  # TODO 커밋3
  *) fail "agent 알 수 없음" "$AGENT" ;;
esac
OUT="$(mktemp "$LOG_DIR/.out.XXXXXX")"; trap 'rm -f "$OUT"' EXIT
cd "$CWD" 2>/dev/null || fail "cd 실패" "$CWD"
"${CMD[@]}" </dev/null >"$OUT" & pid=$!
( sleep "$AP_FORK_TIMEOUT" && echo "timeout ${AP_FORK_TIMEOUT}s" && kill "$pid" ) 2>/dev/null & wd=$!  # stderr 버림: 정상 종료 때 sleep 을 죽이며 나는 "Terminated" 잡음
wait "$pid"; rc=$?
pkill -P "$wd" 2>/dev/null; kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null

# 4. 결과 검증 5단계 (§5.5-4) — 하나라도 실패하면 failed + 단계명 + 원문 앞 200자
[ "$rc" -eq 0 ] || fail "exit $rc" "$(cat "$OUT")"
jq -e . "$OUT" >/dev/null 2>&1 || fail "json 아님" "$(cat "$OUT")"
[ "$(jq -r '.is_error // false' "$OUT")" = "false" ] || fail "is_error" "$(jq -r '.result // ""' "$OUT")"
RESULT="$(jq -er '.result | strings | select(length>0)' "$OUT" 2>/dev/null)" || fail "result 없음" "$(cat "$OUT")"
for h in '### 상황' '### 경위' '### 문제' '### 추정 원인' '### 근거'; do
  printf '%s\n' "$RESULT" | grep -q "^$h" || fail "섹션 누락 $h" "$RESULT"
done

# 5~8. 저장 — 첫 줄이 target: 이면 frontmatter 에 채우고 context 에서 제외 → ## context append → context: done
FIRST="${RESULT%%$'\n'*}"
case "$FIRST" in target:*) set_field target "$(trim "${FIRST#target:}")"; RESULT="${RESULT#*$'\n'}" ;; esac
TMP="$(mktemp "$LOG_DIR/.md.XXXXXX")"
{ cat "$MD" 2>/dev/null; printf '\n## context\n%s\n' "$RESULT"; } > "$TMP"; commit_md "$TMP"
set_field context done

# 9. usage 1줄 — PRD §5 cache read 비율 측정용
echo "usage input=$(jq -r '.usage.input_tokens // 0' "$OUT") cache_read=$(jq -r '.usage.cache_read_input_tokens // 0' "$OUT")"
