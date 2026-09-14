#!/usr/bin/env bash
# ap-capture.sh 단위 테스트 — docs/PLAN.md 커밋 1 검증 1~4·6. 외부 프레임워크 없음.
# AP_HOME 은 $HOME 아래 임시 디렉토리로 지정한다 (훅이 홈 밖 경로를 거부하므로 시스템 tmp 는 못 쓴다).
# 훅은 /bin/bash(macOS 기본 3.2) 로 실행해 호환성을 같이 확인한다.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "$HOME/.ap-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# 훅은 옆에 ap-fork.sh 가 있으면 실제 claude 포크를 백그라운드로 띄운다 → 사본을 빈 디렉토리에서 실행해 기동을 막는다.
# 기동 배선 자체는 검증 5 에서 원본 경로 + 가짜 명령(AP_FORK_CMD)으로 1회 확인
mkdir -p "$TMP/bin"; cp "$ROOT_DIR/scripts/ap-capture.sh" "$TMP/bin/"; CAP="$TMP/bin/ap-capture.sh"
PASS=0; FAIL=0; OUT=""; RC=0

ok()  { PASS=$((PASS+1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1"; }
assert()     { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }
assert_has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (출력: $2)" ;; esac; }

# j <prompt> [cwd] — 훅 입력 JSON 생성
j() { jq -cn --arg p "$1" --arg c "${2:-$ROOT_DIR}" '{prompt:$p,session_id:"s1",transcript_path:"/t.jsonl",cwd:$c}'; }
# jc <command_name> <command_args> <prompt> — UserPromptExpansion 입력 JSON (command_args 가 "" 면 키 자체를 뺀다)
jc() { jq -cn --arg n "$1" --arg a "$2" --arg p "$3" --arg c "$ROOT_DIR" '{command_name:$n,command_args:$a,prompt:$p,session_id:"s1",transcript_path:"/t.jsonl",cwd:$c} | if $a == "" then del(.command_args) else . end'; }
# run <AP_HOME> <json> — 전역 OUT(stdout+stderr)·RC 에 결과
run() { OUT="$(printf '%s' "$2" | AP_HOME="$1" /bin/bash "$CAP" --agent claude 2>&1)"; RC=$?; }
nfiles() { ls "$1/inbox" 2>/dev/null | wc -l | tr -d ' '; }
md1() { ls "$1"/inbox/*.md 2>/dev/null | head -1; }
reason() { printf '%s' "$1" | jq -r '.reason // empty'; }

echo "== 검증 1: 기본 캡처"
H="$TMP/c1"; run "$H" "$(j '/ap 표 너무 김')"; MD="$(md1 "$H")"
assert "1 exit 0" [ "$RC" = 0 ]
assert "1 decision=block" [ "$(printf '%s' "$OUT" | jq -r .decision)" = block ]
assert_has "1 reason 에 저장" "$(reason "$OUT")" "저장"
assert_has "1 reason 에 #id" "$(reason "$OUT")" "#$(basename "$MD" .md)"
assert_has "1 reason 에 요약 첨부 안내" "$(reason "$OUT")" "상황 요약 자동 첨부"
assert "1 inbox md 1개" [ "$(nfiles "$H")" = 1 ]
assert "1 frontmatter 키 10개 순서" [ "$(sed -n '2,11p' "$MD" | cut -d: -f1 | tr '\n' ' ')" = "ts agent kind repo branch cwd session transcript target context " ]
assert "1 ---·---·원문 위치" [ "$(sed -n '1p;12p;13p' "$MD" | tr '\n' '|')" = "---|---|표 너무 김|" ]
assert "1 총 13행" [ "$(wc -l < "$MD" | tr -d ' ')" = 13 ]
assert "1 context: pending" grep -qx 'context: pending' "$MD"
assert "1 target 빈 값" grep -qx 'target:' "$MD"
assert "1 repo" [ "$(sed -n 's/^repo: //p' "$MD")" = "$(basename "$ROOT_DIR")" ]
assert "1 branch" [ "$(sed -n 's/^branch: //p' "$MD")" = "$(git -C "$ROOT_DIR" branch --show-current)" ]
assert "1 파일 600" [ "$(stat -f %Lp "$MD")" = 600 ]
assert "1 디렉토리 700" [ "$(stat -f %Lp "$H/inbox")$(stat -f %Lp "$H/log")$(stat -f %Lp "$H/processed")" = 700700700 ]
assert "1 파일명 형식" [ "$(basename "$MD" | grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}_claude_[^_]+_[0-9a-f]{4}\.md$')" = 1 ]

echo "== 검증 2: good·사용법·매칭 제외"
H="$TMP/c2"; run "$H" "$(j '/ap +좋음')"; MD="$(md1 "$H")"
assert "2 +좋음 kind: good" grep -qx 'kind: good' "$MD"
assert "2 +좋음 본문에 + 없음" [ "$(sed -n 13p "$MD")" = 좋음 ]
H="$TMP/c2b"
run "$H" "$(j '/ap')";        assert_has "2 /ap 단독 사용법" "$(reason "$OUT")" "ap 사용법"
run "$H" "$(j '/ap   ')";     assert_has "2 /ap 공백만 사용법" "$(reason "$OUT")" "ap 사용법"
run "$H" "$(j '/ap +')";      assert_has "2 /ap + 사용법" "$(reason "$OUT")" "ap 사용법"
run "$H" "$(j '/ap +  ')";    assert_has "2 /ap +공백 사용법" "$(reason "$OUT")" "ap 사용법"
assert "2 사용법 케이스 파일 0" [ "$(nfiles "$H")" = 0 ]
run "$H" "$(j '/ap-review x')"; assert "2 /ap-review 출력 없음" [ -z "$OUT" ]; assert "2 /ap-review exit 0" [ "$RC" = 0 ]
run "$H" "$(j 'hello')";        assert "2 hello 출력 없음" [ -z "$OUT" ];      assert "2 hello exit 0" [ "$RC" = 0 ]
run "$H" "$(j '/apx')";         assert "2 /apx 출력 없음" [ -z "$OUT" ]
assert "2 통과 케이스 파일 0" [ "$(nfiles "$H")" = 0 ]
run "$H" "$(j '$ap x')"; MD="$(md1 "$H")"
assert "2 \$ap x 캡처" [ "$(nfiles "$H")" = 1 ]
assert "2 \$ap x 본문" [ "$(sed -n 13p "$MD")" = x ]
H="$TMP/c2c"; run "$H" "$(j $'/ap 첫줄\n둘째줄')"; MD="$(md1 "$H")"
assert "2 줄바꿈 → 공백" [ "$(sed -n 13p "$MD")" = "첫줄 둘째줄" ]

echo "== 검증 2b: 플러그인 커맨드(UserPromptExpansion)·네임스페이스"
H="$TMP/c2d"; run "$H" "$(jc 'annoying-point:ap' '표 김' '/annoying-point:ap 표 김')"; MD="$(md1 "$H")"
assert "2b command_name=annoying-point:ap 캡처" [ "$(nfiles "$H")" = 1 ]
assert "2b command_args 본문" [ "$(sed -n 13p "$MD")" = "표 김" ]
assert_has "2b block reason 저장" "$(reason "$OUT")" "저장"
H="$TMP/c2e"; run "$H" "$(jc '/ap' 'x' '/ap x')"
assert "2b command_name=/ap 캡처" [ "$(nfiles "$H")" = 1 ]
assert "2b command_name=/ap 본문" [ "$(sed -n 13p "$(md1 "$H")")" = x ]
H="$TMP/c2f"; run "$H" "$(jc 'other:cmd' 'x' '/other:cmd x')"
assert "2b 타 커맨드 → 출력 없음" [ -z "$OUT" ]; assert "2b 타 커맨드 → exit 0" [ "$RC" = 0 ]
run "$H" "$(jc 'other:cmd' '' '/ap x')"
assert "2b 타 커맨드는 prompt 가 /ap 여도 통과" [ -z "$OUT" ]
assert "2b 타 커맨드 파일 0" [ "$(nfiles "$H")" = 0 ]
H="$TMP/c2g"; run "$H" "$(jc 'annoying-point:ap' '' '/annoying-point:ap 표 김')"
assert "2b command_args 없음 → prompt 첫 토큰 제거" [ "$(sed -n 13p "$(md1 "$H")")" = "표 김" ]
H="$TMP/c2h"; run "$H" "$(jc 'annoying-point:ap' '' '표 김')"
assert "2b command_args 없음·prompt 인자만 → 그대로" [ "$(sed -n 13p "$(md1 "$H")")" = "표 김" ]
H="$TMP/c2i"; run "$H" "$(jc 'annoying-point:ap' '' '/annoying-point:ap')"
assert_has "2b 커맨드 인자 없음 → 사용법" "$(reason "$OUT")" "ap 사용법"
assert "2b 커맨드 인자 없음 → 파일 0" [ "$(nfiles "$H")" = 0 ]
H="$TMP/c2j"; run "$H" "$(jc 'annoying-point:ap' '+좋음' '/annoying-point:ap +좋음')"
assert "2b 커맨드 +좋음 → good" grep -qx 'kind: good' "$(md1 "$H")"
H="$TMP/c2k"; run "$H" "$(j '/annoying-point:ap 표 김')"; MD="$(md1 "$H")"
assert "2b 플레인 /annoying-point:ap 캡처" [ "$(nfiles "$H")" = 1 ]
assert "2b 플레인 /annoying-point:ap 본문" [ "$(sed -n 13p "$MD")" = "표 김" ]
run "$H" "$(j '/annoying-point:apx y')"; assert "2b /annoying-point:apx 출력 없음" [ -z "$OUT" ]
run "$H" "$(j '/annoying-point:ap-review y')"; assert "2b /annoying-point:ap-review 출력 없음" [ -z "$OUT" ]
assert "2b 위 두 케이스 파일 추가 0" [ "$(nfiles "$H")" = 1 ]

echo "== 검증 2c: Cursor(beforeSubmitPrompt) 입출력"
jcu() { jq -cn --arg p "$1" --arg c "$ROOT_DIR" '{prompt:$p,conversation_id:"c1",workspace_roots:[$c],transcript_path:"/t"}'; }
runc() { OUT="$(printf '%s' "$2" | AP_HOME="$1" /bin/bash "$CAP" --agent cursor 2>&1)"; RC=$?; }
H="$TMP/c2l"; runc "$H" "$(jcu '/ap 커서 테스트')"; MD="$(md1 "$H")"
assert "2c continue=false" [ "$(printf '%s' "$OUT" | jq -r .continue)" = false ]
assert_has "2c user_message 저장" "$(printf '%s' "$OUT" | jq -r .user_message)" "📌 ap 저장됨 #$(basename "$MD" .md) (정상"
assert "2c decision 키 없음" [ "$(printf '%s' "$OUT" | jq -r 'has("decision")')" = false ]
assert "2c agent: cursor" grep -qx 'agent: cursor' "$MD"
assert "2c session = conversation_id" grep -qx 'session: c1' "$MD"
assert "2c cwd = workspace_roots[0]" grep -qx "cwd: $ROOT_DIR" "$MD"
assert "2c 파일명에 cursor" [ "$(basename "$MD" | grep -c '_cursor_')" = 1 ]
assert "2c 본문" [ "$(sed -n 13p "$MD")" = "커서 테스트" ]
runc "$H" "$(jcu '/ap')"; assert "2c 사용법도 cursor 형식" [ "$(printf '%s' "$OUT" | jq -r '.continue, (.user_message|startswith("📌 ap 사용법"))' | tr '\n' ' ')" = "false true " ]
OUT="$(printf '%s' "$(jcu '/ap 홈 밖')" | AP_HOME=/tmp/x /bin/bash "$CAP" --agent cursor 2>&1)"
assert_has "2c 저장 실패도 cursor 형식" "$(printf '%s' "$OUT" | jq -r .user_message)" "저장 실패"
runc "$H" "$(jcu 'hello')"; assert "2c 통과는 무출력 exit 0" [ -z "$OUT" -a "$RC" = 0 ]
runc "$H" '{"prompt":"/ap 루트 없음","conversation_id":"c2","cwd":"/tmp"}'
assert "2c workspace_roots 없으면 cwd" grep -qx 'cwd: /tmp' "$(ls -t "$H"/inbox/*.md | head -1)"
run "$H" '{"prompt":"/ap 코덱스","session_id":"x1","transcript_path":null,"cwd":"/tmp"}'
assert "2c --agent claude 출력은 그대로 decision" [ "$(printf '%s' "$OUT" | jq -r .decision)" = block ]

echo "== 검증 3: 충돌·null·git 아님"
H="$TMP/c3"; run "$H" "$(j '/ap a')"; run "$H" "$(j '/ap b')"
assert "3 같은 초 2회 → 파일 2개" [ "$(nfiles "$H")" = 2 ]
assert "3 둘 다 4hex 접미" [ "$(ls "$H/inbox" | grep -Ec '_[0-9a-f]{4}\.md$')" = 2 ]
assert "3 본문 a·b 보존" [ "$(for f in "$H"/inbox/*.md; do sed -n 13p "$f"; done | sort | tr '\n' ' ')" = "a b " ]
H="$TMP/c3b"; run "$H" '{"prompt":"/ap t","session_id":"s1","transcript_path":null,"cwd":"'"$ROOT_DIR"'"}'
assert "3 transcript null → -" grep -qx 'transcript: -' "$(md1 "$H")"
NG="$(mktemp -d)"; H="$TMP/c3c"; run "$H" "$(j '/ap t' "$NG")"; MD="$(md1 "$H")"
assert "3 git 아님 branch: -" grep -qx 'branch: -' "$MD"
assert "3 git 아님 repo=디렉토리명" [ "$(sed -n 's/^repo: //p' "$MD")" = "$(basename "$NG")" ]
rm -rf "$NG"

echo "== 검증 4: 쓰기 불가·jq 없음·파싱 실패·session 없음"
run /tmp/x "$(j '/ap 홈 밖 원문')"
assert_has "4 홈 밖 → 저장 실패 block" "$(reason "$OUT")" "저장 실패"
assert_has "4 홈 밖 → 원문 포함" "$(reason "$OUT")" "홈 밖 원문"
assert "4 홈 밖 → 파일 0" [ ! -e /tmp/x/inbox ]
# macOS 15+ 는 /usr/bin/jq 를 기본 탑재 → PATH=/bin 으로 jq 만 뺀다 (jq 확인이 첫 단계라 다른 명령은 필요 없음)
assert "4 사전: PATH=/bin 에 jq 없음" [ -z "$(PATH=/bin command -v jq)" ]
OUT="$(printf '%s' "$(j '/ap x')" | AP_HOME="$TMP/c4" PATH=/bin /bin/bash "$CAP" 2>&1)"; RC=$?
assert "4 jq 없음 → 출력 없음" [ -z "$OUT" ]; assert "4 jq 없음 → exit 0" [ "$RC" = 0 ]
run "$TMP/c4" 'not json'; assert "4 JSON 아님 → 출력 없음" [ -z "$OUT" ]; assert "4 JSON 아님 → exit 0" [ "$RC" = 0 ]
assert "4 위 케이스 파일 0" [ "$(nfiles "$TMP/c4")" = 0 ]
# 가짜 ap-fork.sh (사본 옆) — 호출된 md 경로를 <AP_HOME>/launched 에 기록
mkfake_fork() { printf '#!/bin/bash\necho "$1" > "$(dirname "$1")/../launched"\n' > "$TMP/bin/ap-fork.sh"; }
mkfake_fork; H="$TMP/c4s"; run "$H" '{"prompt":"/ap s","session_id":"","cwd":"'"$ROOT_DIR"'"}'; MD="$(md1 "$H")"
for i in 1 2 3 4 5 6; do [ -s "$H/launched" ] && break; sleep 0.5; done
assert "4 session 없음 → 저장은 함" [ "$(nfiles "$H")" = 1 ]
assert "4 session 없음 → 런처는 기동됨 (no session 판정은 런처 몫)" [ "$(cat "$H/launched" 2>/dev/null)" = "$MD" ]
assert "4 session 없음 → 훅은 log 에 no session 안 씀" [ ! -s "$H/log/$(basename "$MD" .md).log" ]
rm -f "$TMP/bin/ap-fork.sh"

echo "== 검증 4b: 메타 개행·홈 경계(.. / 심링크)"
H="$TMP/c4b"; run "$H" "$(jq -cn --arg c "$ROOT_DIR" '{prompt:"/ap 메타",session_id:"s\n1",transcript_path:"/t\r\n2",cwd:$c}')"; MD="$(md1 "$H")"
assert "4b 메타 개행 → 13행 유지" [ "$(wc -l < "$MD" | tr -d ' ')" = 13 ]
assert "4b session 개행 → 공백" grep -qx 'session: s 1' "$MD"
assert "4b transcript CRLF → 공백" grep -qx 'transcript: /t  2' "$MD"
run "$HOME/x/../../tmp" "$(j '/ap 점점')"; assert_has "4b \$HOME/x/../../tmp → 저장 실패" "$(reason "$OUT")" "저장 실패"
assert "4b .. 경로 파일 0" [ ! -e "$HOME/x" -a ! -e /tmp/inbox ]
OUTSIDE="$(mktemp -d)"; ln -s "$OUTSIDE" "$TMP/link-out"; run "$TMP/link-out" "$(j '/ap 심링크')"
assert_has "4b 홈 안 심링크 → 홈 밖 → 저장 실패" "$(reason "$OUT")" "저장 실패"
assert "4b 심링크 너머 inbox 파일 0" [ "$(ls "$OUTSIDE/inbox" 2>/dev/null | wc -l | tr -d ' ')" = 0 ]
rm -rf "$OUTSIDE"
mkdir -p "$TMP/real-in"; ln -s "$TMP/real-in" "$TMP/link-in"; run "$TMP/link-in" "$(j '/ap 홈안링크')"
assert "4b 홈 안을 가리키는 심링크는 정상 저장" [ "$(nfiles "$TMP/real-in")" = 1 ]

echo "== 검증 5: 포크 기동 배선 (원본 경로 + 가짜 claude)"
FAKE="$TMP/fake.sh"; printf '#!/bin/bash\nprintf %%s "$FAKE_OUT"\n' > "$FAKE"; chmod 755 "$FAKE"
FAKE_OUT="$(jq -cn --arg r $'target: model\n### 상황\n### 경위\n### 문제\n### 추정 원인\n### 근거' '{result:$r,usage:{input_tokens:1,cache_read_input_tokens:9}}')"
H="$TMP/c5"; OUT="$(printf '%s' "$(j '/ap 배선')" | AP_HOME="$H" AP_FORK_CMD="$FAKE" FAKE_OUT="$FAKE_OUT" /bin/bash "$ROOT_DIR/scripts/ap-capture.sh" 2>&1)"; RC=$?
assert "5 block 즉시 반환" [ "$(printf '%s' "$OUT" | jq -r .decision)" = block ]
MD="$(md1 "$H")"; LOGF="$H/log/$(basename "$MD" .md).log"
for i in 1 2 3 4 5 6 7 8 9 10; do grep -qx 'context: done' "$MD" 2>/dev/null && break; sleep 0.5; done
assert "5 백그라운드 포크가 md 를 done 으로" grep -qx 'context: done' "$MD"
assert "5 log/<id>.log 에 usage" grep -q '^usage input=1 cache_read=9' "$LOGF"
assert "5 포크 프로세스 잔존 0" [ -z "$(pgrep -f "ap-fork.sh $H")" ]

echo "== 검증 5b: 포크가 새 프로세스 그룹(setsid)으로 분리되는지 — 사본 옆에 가짜 ap-fork.sh"
# macOS ps 의 sess 는 항상 0 이라 pgid 로 판정: setsid 자식은 pgid = 자기 pid, nohup 자식은 부모 pgid 그대로
printf '#!/bin/bash\nps -o pgid= -p $$ | tr -d " " > "$(dirname "$1")/../pgid"; echo $$ > "$(dirname "$1")/../pid"\n' > "$TMP/bin/ap-fork.sh"
H="$TMP/c5b"; run "$H" "$(j '/ap 분리')"; for i in 1 2 3 4 5 6; do [ -s "$H/pgid" ] && break; sleep 0.5; done
assert "5b 포크 기동됨" [ -s "$H/pgid" ]
assert "5b 포크 pgid ≠ 테스트 pgid ($(cat "$H/pgid" 2>/dev/null) vs $(ps -o pgid= -p $$ | tr -d ' '))" [ "$(cat "$H/pgid")" != "$(ps -o pgid= -p $$ | tr -d ' ')" ]
assert "5b 포크 pgid = 자기 pid (세션 리더)" [ "$(cat "$H/pgid")" = "$(cat "$H/pid")" ]
# perl 없음 폴백 — perl 만 뺀 PATH 로 같은 가짜 ap-fork.sh 기동 → log 에 폴백 1줄 + nohup 이라 pgid 가 부모와 같다
mkdir -p "$TMP/nobin"; for b in jq bash cat sed head date xxd git basename dirname mkdir nohup ps tr; do ln -s "$(command -v $b)" "$TMP/nobin/$b"; done
H="$TMP/c5c"; OUT="$(printf '%s' "$(j '/ap 폴백')" | AP_HOME="$H" PATH="$TMP/nobin" /bin/bash "$CAP" 2>&1)"
for i in 1 2 3 4 5 6; do [ -s "$H/pgid" ] && break; sleep 0.5; done
assert "5b perl 없음 → 폴백 log 1줄" grep -q '^perl 없음 — nohup 폴백' "$H/log/$(basename "$(md1 "$H")" .md).log"
assert "5b 폴백은 nohup — pgid = 테스트 pgid" [ "$(cat "$H/pgid")" = "$(ps -o pgid= -p $$ | tr -d ' ')" ]
rm -f "$TMP/bin/ap-fork.sh"

echo "== 검증 6: 지연 30회 p95 < 1초"
RES="$(python3 - "$CAP" "$TMP/c6" "$(j '/ap 표 너무 김')" <<'PY'
import os, subprocess, sys, time
cap, home, inp = sys.argv[1:4]
env = dict(os.environ, AP_HOME=home)
ts = []
for _ in range(30):
    t = time.time()
    subprocess.run(["/bin/bash", cap, "--agent", "claude"], input=inp.encode(), capture_output=True, env=env)
    ts.append(time.time() - t)
ts.sort()
p95 = ts[int(len(ts) * 0.95)]
print(f"p95={p95:.3f}s max={ts[-1]:.3f}s min={ts[0]:.3f}s")
sys.exit(0 if p95 < 1 else 1)
PY
)"; RC=$?
echo "   $RES"
assert "6 p95 < 1초" [ "$RC" = 0 ]
assert "6 30회 → 파일 30개" [ "$(nfiles "$TMP/c6")" = 30 ]

echo "== $PASS/$((PASS+FAIL)) 통과"
[ "$FAIL" = 0 ]
