#!/usr/bin/env bash
# ap-notify.sh 단위 테스트 — docs/PLAN.md 커밋 4 검증 1~2. 외부 프레임워크 없음. AP_HOME 은 $HOME 아래 임시 디렉토리.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTIFY="$ROOT_DIR/scripts/ap-notify.sh"
TMP="$(mktemp -d "$HOME/.ap-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1"; }
assert() { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }
# run <AP_HOME> [--agent x] → OUT·RC (stdin 은 훅 입력 흉내)
run() { local h="$1"; shift; OUT="$(printf '{"session_id":"s","source":"startup"}' | AP_HOME="$h" /bin/bash "$NOTIFY" "$@" 2>&1)"; RC=$?; }
mk() { touch "$1/inbox/2026-$2_100000_claude_r_ab12.md"; }

echo "== 검증 1: 건수·최근·무출력"
H="$TMP/h0"; run "$H"; assert "1 AP_HOME 없음 → 무출력" [ -z "$OUT" ]; assert "1 AP_HOME 없음 → exit 0" [ "$RC" = 0 ]
mkdir -p "$H/inbox"; run "$H"; assert "1 inbox 0건 → 무출력" [ -z "$OUT" ]; assert "1 inbox 0건 → exit 0" [ "$RC" = 0 ]
touch "$H/inbox/readme.txt" "$H/inbox/note.md.bak"; run "$H"; assert "1 md 아닌 파일은 안 셈 → 무출력" [ -z "$OUT" ]
H="$TMP/h3"; mkdir -p "$H/inbox"; mk "$H" 09-13; mk "$H" 09-14; mk "$H" 09-12; touch "$H/inbox/readme.txt"; mkdir "$H/inbox/dir.md"
run "$H"; assert "1 3건 → systemMessage 정확" [ "$(printf '%s' "$OUT" | jq -r .systemMessage)" = "📌 ap inbox 3건 (최근 09-14)" ]
assert "1 출력 1줄 JSON" [ "$(printf '%s' "$OUT" | wc -l | tr -d ' ')" = 0 -a "$(printf '%s' "$OUT" | jq -c 'keys')" = '["systemMessage"]' ]
assert "1 exit 0" [ "$RC" = 0 ]
run "$H" --agent codex; assert "1 codex 도 systemMessage" [ "$(printf '%s' "$OUT" | jq -r .systemMessage)" = "📌 ap inbox 3건 (최근 09-14)" ]
run "$H" --agent cursor; assert "1 cursor 는 additional_context" [ "$(printf '%s' "$OUT" | jq -c .)" = '{"additional_context":"📌 ap inbox 3건 (최근 09-14)"}' ]
mk "$H" 09-11; run "$H"; assert "1 4건·최근은 이름순 마지막(09-14)" [ "$(printf '%s' "$OUT" | jq -r .systemMessage)" = "📌 ap inbox 4건 (최근 09-14)" ]
H="$TMP/h1"; mkdir -p "$H/inbox"; mk "$H" 08-30; run "$H"; assert "1 1건" [ "$(printf '%s' "$OUT" | jq -r .systemMessage)" = "📌 ap inbox 1건 (최근 08-30)" ]
OUT="$(printf '{}' | AP_HOME="$TMP/h1" PATH=/bin /bin/bash "$NOTIFY" 2>&1)"; RC=$?
assert "1 jq 없어도 동작 (PATH=/bin)" [ "$RC" = 0 -a "$OUT" = '{"systemMessage":"📌 ap inbox 1건 (최근 08-30)"}' ]
OUT="$(AP_HOME="$TMP/h1" /bin/bash "$NOTIFY" </dev/null 2>&1)"; assert "1 stdin 없어도 동작" [ -n "$OUT" ]

H="$TMP/hq"; mkdir -p "$H/inbox"; touch "$H/inbox/abcde\"x.md"; run "$H"
assert "1 형식 밖 파일명 → 최근 -" [ "$(printf '%s' "$OUT" | jq -r .systemMessage)" = "📌 ap inbox 1건 (최근 -)" ]
assert "1 형식 밖 파일명도 JSON 파싱 OK" [ "$(printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; echo $?)" = 0 ]
echo "== 검증 2: 지연 — inbox 100건 30회 p95 < 100ms"
H="$TMP/h100"; mkdir -p "$H/inbox"; for i in $(seq -w 1 100); do touch "$H/inbox/2026-07-${i:1:2}_1000${i:1:2}_claude_r_${i}a.md"; done
RES="$(python3 - "$NOTIFY" "$H" <<'PY'
import os, subprocess, sys, time
n, home = sys.argv[1:3]; env = dict(os.environ, AP_HOME=home); ts = []
for _ in range(30):
    t = time.time(); subprocess.run(["/bin/bash", n], input=b"{}", capture_output=True, env=env); ts.append(time.time() - t)
ts.sort(); p95 = ts[int(len(ts) * 0.95)]
print(f"p95={p95*1000:.1f}ms max={ts[-1]*1000:.1f}ms min={ts[0]*1000:.1f}ms"); sys.exit(0 if p95 < 0.1 else 1)
PY
)"; RC=$?; echo "   $RES"
assert "2 p95 < 100ms" [ "$RC" = 0 ]
run "$H"; assert "2 100건 집계 + 최근 = 이름순 마지막" [ "$(printf '%s' "$OUT" | jq -r .systemMessage)" = "📌 ap inbox 100건 (최근 $(ls "$H/inbox" | sort | tail -1 | cut -c6-10))" ]

echo "== $PASS/$((PASS+FAIL)) 통과"
[ "$FAIL" = 0 ]
