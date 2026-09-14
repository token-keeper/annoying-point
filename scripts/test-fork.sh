#!/usr/bin/env bash
# ap-fork.sh 단위 테스트 — docs/PLAN.md 커밋 2 검증 1~4. 외부 프레임워크 없음.
# 검증 3(가짜 명령, AP_FORK_CMD)은 항상 실행. 검증 1·2·4(실제 claude 호출)는 AP_FORK_SESSION=<실세션 id> 를 주면 실행한다.
#   예: AP_FORK_SESSION=<id> AP_FORK_CWD=<그 세션의 cwd> bash scripts/test-fork.sh
# AP_HOME 은 $HOME 아래 임시 디렉토리 (시스템 tmp 는 홈 밖이라 훅 규칙상 못 쓴다).
set -uo pipefail
umask 077  # 픽스처 md 도 capture 와 같은 600 으로 (inode 덮어쓰기는 모드를 유지하므로 픽스처 모드가 곧 결과 모드)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORK="$ROOT_DIR/scripts/ap-fork.sh"
TMP="$(mktemp -d "$HOME/.ap-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1"; }
assert()     { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }
assert_has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (실제: $2)" ;; esac; }

# 가짜 claude — FAKE_OUT 을 stdout 으로, FAKE_RC 로 종료. FAKE_EXEC_SLEEP 이면 sleep 으로 대체(워치독용), FAKE_SLEEP 이면 잠깐 기다렸다 출력
FAKE="$TMP/fake.sh"
cat > "$FAKE" <<'EOF'
#!/bin/bash
[ -n "${FAKE_EXEC_SLEEP:-}" ] && exec sleep "$FAKE_EXEC_SLEEP"
[ -n "${FAKE_SLEEP:-}" ] && sleep "$FAKE_SLEEP"
printf '%s' "${FAKE_OUT:-}"
exit "${FAKE_RC:-0}"
EOF
chmod 755 "$FAKE"

# mkmd <AP_HOME> <session> <cwd> [agent] → inbox md 경로 (ap-capture.sh §4.2 포맷 그대로)
mkmd() {
  mkdir -p "$1/inbox" "$1/log"; local md="$1/inbox/2026-09-14_150000_${4:-claude}_r_ab12.md"
  printf '%s\n' --- "ts: 2026-09-14 15:00" "agent: ${4:-claude}" "kind: annoying" "repo: r" "branch: b" "cwd: $3" \
    "session: $2" "transcript: -" "target:" "context: pending" --- "표 김" > "$md"; echo "$md"
}
# runf <AP_HOME> <md> [env...] — 가짜로 실행, log 는 $LOG
runf() { local h="$1" md="$2"; shift 2; LOG="$h/log/$(basename "$md" .md).log"; env AP_HOME="$h" AP_FORK_CMD="$FAKE" "$@" /bin/bash "$FORK" "$md" >>"$LOG" 2>&1; RC=$?; }
ctx() { sed -n 's/^context: //p' "$1" | head -1; }
GOOD=$'target: model\n### 상황\n프로젝트 X\n### 경위\n턴1\n### 문제\n표 김\n### 추정 원인\nrule:a\n### 근거\n해당 없음'
GOOD_JSON="$(jq -cn --arg r "$GOOD" '{result:$r,is_error:false,usage:{input_tokens:12,cache_read_input_tokens:3400}}')"

echo "== 검증 3: 결과 검증 5단계·저장 (가짜 명령)"
H="$TMP/f1"; MD="$(mkmd "$H" s1 "$ROOT_DIR")"; runf "$H" "$MD" FAKE_OUT='{}'
assert "3-① {} → failed" [ "$(ctx "$MD")" = failed ]; assert_has "3-① log result 없음" "$(cat "$LOG")" "result 없음"
assert "3-① 본문 무변경" [ "$(sed -n 13p "$MD")" = "표 김" ]; assert "3-① 총 13행 유지" [ "$(wc -l < "$MD" | tr -d ' ')" = 13 ]

H="$TMP/f2"; MD="$(mkmd "$H" s1 "$ROOT_DIR")"; runf "$H" "$MD" FAKE_OUT="$GOOD_JSON"
assert "3-② done" [ "$(ctx "$MD")" = done ]; assert "3-② rc 0" [ "$RC" = 0 ]
assert "3-② target: model" grep -qx 'target: model' "$MD"
assert "3-② frontmatter 키 순서 유지" [ "$(sed -n '2,11p' "$MD" | cut -d: -f1 | tr '\n' ' ')" = "ts agent kind repo branch cwd session transcript target context " ]
assert "3-② 본문 유지" [ "$(sed -n 13p "$MD")" = "표 김" ]
assert "3-② ## context 가 14행 공백 뒤" [ "$(sed -n '14p;15p' "$MD" | tr '\n' '|')" = "|## context|" ]
assert "3-② 헤더 5개" [ "$(grep -c '^### ' "$MD")" = 5 ]
assert "3-② context 에 target 줄 없음" [ "$(grep -c '^target:' "$MD")" = 1 ]
assert_has "3-② log usage" "$(cat "$LOG")" "usage input=12 cache_read=3400"
assert "3-② 파일 600" [ "$(stat -f %Lp "$MD")" = 600 ]
assert "3-② 임시 파일 잔존 0" [ -z "$(ls -A "$H/log" | grep '^\.')" ]

H="$TMP/f3"; MD="$(mkmd "$H" s1 "$ROOT_DIR")"; runf "$H" "$MD" FAKE_OUT="$(jq -cn --arg r "${GOOD#*$'\n'}" '{result:$r}')"
assert "3-③ target 없음 → done" [ "$(ctx "$MD")" = done ]; assert "3-③ target 빈 채 유지" grep -qx 'target:' "$MD"
assert "3-③ context 첫 줄 ### 상황" [ "$(sed -n 16p "$MD")" = "### 상황" ]

H="$TMP/f4"; MD="$(mkmd "$H" s1 "$ROOT_DIR")"; runf "$H" "$MD" FAKE_OUT='{"is_error":true,"result":"x"}'
assert "3-④ is_error → failed" [ "$(ctx "$MD")" = failed ]; assert_has "3-④ log is_error" "$(cat "$LOG")" "is_error"

H="$TMP/f5"; MD="$(mkmd "$H" s1 "$ROOT_DIR")"; runf "$H" "$MD" FAKE_OUT="$(jq -cn --arg r "${GOOD%$'\n### 근거'*}" '{result:$r}')"
assert "3-⑤ 헤더 4개 → failed" [ "$(ctx "$MD")" = failed ]; assert_has "3-⑤ log 섹션 누락" "$(cat "$LOG")" "섹션 누락 ### 근거"
assert "3-⑤ 본문 무변경·append 없음" [ "$(wc -l < "$MD" | tr -d ' ')" = 13 ]

H="$TMP/f6"; MD="$(mkmd "$H" s1 "$ROOT_DIR")"; S=$(date +%s); runf "$H" "$MD" FAKE_EXEC_SLEEP=999 AP_FORK_TIMEOUT=2; E=$(( $(date +%s) - S ))
assert "3-⑥ timeout → failed" [ "$(ctx "$MD")" = failed ]; assert_has "3-⑥ log timeout" "$(cat "$LOG")" "timeout 2s"
assert "3-⑥ 2~4초 내 종료 (${E}s)" [ "$E" -ge 2 -a "$E" -le 4 ]
assert "3-⑥ 자식 sleep 999 잔존 0" [ -z "$(pgrep -f 'sleep 999')" ]
assert "3-⑥ 워치독 sleep 잔존 0" [ -z "$(pgrep -f 'sleep 2$')" ]

H="$TMP/f7"; MD="$(mkmd "$H" s1 "$ROOT_DIR")"; mkdir -p "$H/processed"
runf "$H" "$MD" FAKE_SLEEP=2 FAKE_OUT="$GOOD_JSON" & FP=$!; sleep 1; mv "$MD" "$H/processed/"; wait $FP
assert "3-⑦ inbox 재생성 0" [ "$(ls "$H/inbox" | wc -l | tr -d ' ')" = 0 ]
assert_has "3-⑦ log moved before context" "$(cat "$H/log/"*.log)" "moved before context"
assert "3-⑦ 옮긴 파일 무변경(pending)" [ "$(ctx "$H/processed/$(basename "$MD")")" = pending ]

H="$TMP/f8"; MD="$(mkmd "$H" s1 "$ROOT_DIR")"; runf "$H" "$MD" FAKE_OUT='{"result":"x"}' FAKE_RC=3
assert "3-⑧ exit≠0 → failed" [ "$(ctx "$MD")" = failed ]; assert_has "3-⑧ log exit 3" "$(cat "$LOG")" "exit 3"
H="$TMP/f9"; MD="$(mkmd "$H" s1 "$ROOT_DIR")"; runf "$H" "$MD" FAKE_OUT='not json'
assert "3-⑨ json 아님 → failed" [ "$(ctx "$MD")" = failed ]; assert_has "3-⑨ log json 아님" "$(cat "$LOG")" "json 아님: not json"
H="$TMP/f10"; MD="$(mkmd "$H" '' "$ROOT_DIR")"; runf "$H" "$MD" FAKE_OUT="$GOOD_JSON"
assert "3-⑩ session 없음 → failed" [ "$(ctx "$MD")" = failed ]; assert_has "3-⑩ log no session" "$(cat "$LOG")" "no session"
H="$TMP/f11"; MD="$(mkmd "$H" s1 "$ROOT_DIR" codex)"; runf "$H" "$MD" FAKE_OUT="$GOOD_JSON"
assert "3-⑪ codex → failed" [ "$(ctx "$MD")" = failed ]; assert_has "3-⑪ log agent 미지원(커밋3)" "$(cat "$LOG")" "agent 미지원(커밋3): codex"
H="$TMP/f12"; MD="$(mkmd "$H" s1 "$ROOT_DIR")"; runf "$H" "$MD" FAKE_OUT="$(jq -cn --arg r "target: a&b|c"$'\n'"${GOOD#*$'\n'}" '{result:$r}')"
assert "3-⑫ target 의 sed 특수문자(&|) 보존" grep -qx 'target: a&b|c' "$MD"

if [ -z "${AP_FORK_SESSION:-}" ]; then
  echo "SKIP 검증 1·2·4 — AP_FORK_SESSION 미지정 (실세션 포크는 claude 를 실제로 호출한다)"
else
  CWD="${AP_FORK_CWD:-$PWD}"; PROJ="$HOME/.claude/projects/$(printf '%s' "$CWD" | sed 's#[/.]#-#g')"
  echo "== 검증 2: 존재하지 않는 session"
  H="$TMP/r2"; MD="$(mkmd "$H" 00000000-0000-0000-0000-000000000000 "$CWD")"; LOG="$H/log/$(basename "$MD" .md).log"
  AP_HOME="$H" /bin/bash "$FORK" "$MD" >>"$LOG" 2>&1
  assert "2 없는 session → failed" [ "$(ctx "$MD")" = failed ]; assert_has "2 log exit code" "$(cat "$LOG")" "exit "
  assert "2 본문 무변경" [ "$(wc -l < "$MD" | tr -d ' ')" = 13 ]; echo "   log: $(cat "$LOG" | head -3)"

  echo "== 검증 1·4: 실세션 포크 (session=$AP_FORK_SESSION cwd=$CWD)"
  BEFORE="$(ls "$PROJ"/*.jsonl 2>/dev/null)"; ORIG="$PROJ/$AP_FORK_SESSION.jsonl"; L0="$(wc -l < "$ORIG" | tr -d ' ')"
  H="$TMP/r1"; MD="$(mkmd "$H" "$AP_FORK_SESSION" "$CWD")"; LOG="$H/log/$(basename "$MD" .md).log"
  S=$(date +%s); AP_HOME="$H" /bin/bash "$FORK" "$MD" >>"$LOG" 2>&1; E=$(( $(date +%s) - S )); L1="$(wc -l < "$ORIG" | tr -d ' ')"
  assert "1 120초 내 완료 (${E}s)" [ "$E" -le 120 ]
  assert "1 context: done" [ "$(ctx "$MD")" = done ]
  assert "1 ## context" grep -qx '## context' "$MD"; assert "1 헤더 5개" [ "$(grep -c '^### ' "$MD")" -ge 5 ]
  assert "1 target 채워짐" [ -n "$(sed -n 's/^target: //p' "$MD" | head -1)" ]
  assert_has "1 log usage" "$(cat "$LOG")" "usage input="
  IN="$(sed -n 's/.*usage input=\([0-9]*\).*/\1/p' "$LOG")"; CR="$(sed -n 's/.*cache_read=\([0-9]*\).*/\1/p' "$LOG")"
  assert "1 cache_read 비율 ≥ 90% (input=$IN cache_read=$CR)" [ "$(( CR * 100 / (IN + CR + 1) ))" -ge 90 ]
  NEW="$(comm -13 <(printf '%s\n' "$BEFORE") <(ls "$PROJ"/*.jsonl))"
  assert "4 새 세션 jsonl 정확히 1개" [ "$(printf '%s\n' "$NEW" | grep -c .)" = 1 ]
  assert "4 새 파일 sessionId ≠ 원본" [ "$(head -1 "$NEW" | jq -r .sessionId)" != "$AP_FORK_SESSION" ]
  echo "   원본 jsonl 줄 수 전/후: $L0 / $L1 (이 세션이 계속 활동 중이면 늘 수 있음 — 판정 아님)"
  echo "   새 세션 파일: $NEW"
  echo "----- md 전문 -----"; cat "$MD"; echo "----- log -----"; cat "$LOG"; echo "-------------------"
fi

echo "== $PASS/$((PASS+FAIL)) 통과"
[ "$FAIL" = 0 ]
