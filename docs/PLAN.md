# annoying-point — PLAN

> 작성 2026-09-14 · 선행 문서: [PRD.md](./PRD.md)(무엇을 만드는가) · [TECH_SPEC.md](./TECH_SPEC.md)(어떻게 구현하는가)
> 이 문서는 **언제·어떤 순서로** 진행할지만 다룬다.

## 1. 개요

`/ap <한마디>`를 훅이 가로채 `$AP_HOME/inbox/`에 md로 즉시 저장하고 block한 뒤, 백그라운드 포크가 5섹션 context를 붙인다. `/ap-review`는 현재 세션 AI가 대화형으로 진행한다. 런타임은 bash + jq, 대상은 Claude Code · Codex CLI 0.154.0 · Cursor Agent CLI 2026.09.10.

구성 파일 (총 9개):

| 파일 | 역할 | 만드는 커밋 |
|---|---|---|
| `scripts/ap-capture.sh` | 훅 본체 — 매칭·저장·block·포크 기동 | 1 (Cursor 분기는 3) |
| `hooks/hooks.json` | Claude `UserPromptSubmit` · `SessionStart` 등록 | 1 (SessionStart는 4) |
| `scripts/ap-fork.sh` | 백그라운드 요약기 런처 | 2 (Codex·Cursor 분기는 3) |
| `install.sh` | Codex·Cursor 훅 등록 + 스킬 심링크 + AP_HOME 생성 | 3 |
| `scripts/ap-notify.sh` | SessionStart 1줄 알림 | 4 |
| `skills/ap-review/SKILL.md` | 대화형 리뷰 스킬 | 5 |
| `commands/ap.md` | `/ap` 자동완성 등록 + 훅 미동작 안내 | 6 |
| `.claude-plugin/plugin.json` | 매니페스트 | 6 |
| `README.md` | 설치·사용법·한계 | 6 |

## 2. 커밋 단위 분해

기준: **커밋 1개 = 프로덕션 코드 300줄 이하** (문서·픽스처는 별도 계산). 전체 7개 커밋 + 범위 밖 1단계, PR 1개. 브랜치는 `feature/docs`에서 이어가지 않고 구현용 브랜치를 분리한다(이름은 착수 시 대표 확인).

라이브 검증은 전부 `AP_HOME`을 임시 디렉토리로 지정해 실행한다 — 사용자 실제 저장소를 오염시키지 않는다.

### 커밋 1 — `feat(hook): /ap 캡처 훅 ap-capture.sh + hooks.json (Claude)`

- 산출: `scripts/ap-capture.sh`(매칭 정규식 `[[:space:]]` · AP_HOME 해석 · md 생성 — 파일명 초+4hex · frontmatter 한 줄 규약 · `context: pending` · noclobber 이중 안전 · block 출력 · 포크 기동 — 런처 stdout·stderr를 `log/<id>.log`로), `hooks/hooks.json`(`UserPromptSubmit`만)
- 이 커밋에서는 `ap-fork.sh`가 아직 없으므로 기동 직전 `[ -f "$SCRIPT_DIR/ap-fork.sh" ]` 확인 후 없으면 건너뛴다.
- 의존: 없음
- 예상 줄수: 스크립트 100 + hooks.json 15 ≈ **115줄**
- 검증:
  1. 단위 — `echo '{"prompt":"/ap 표 너무 김","session_id":"s1","transcript_path":"/t.jsonl","cwd":"'"$PWD"'"}' | AP_HOME=$TMP bash scripts/ap-capture.sh` → stdout이 `{"decision":"block","reason":"📌 ap 저장됨 #… (정상 — 훅이 가로챔, 답변 없음) · 30초 뒤 상황 요약 자동 첨부"}`, `$TMP/inbox/`에 md 1개, frontmatter 10개 키 존재(`context: pending` 포함), `stat -f %Lp` = 600
  2. 단위 — `/ap +좋음` → `kind: good`, 본문에 `+` 없음 · `/ap` 단독 → 사용법 block, 파일 0개 · `/ap-review x` → 출력 없음 exit 0 · `hello` → 출력 없음 exit 0 · `$ap x` → 캡처
  3. 단위 — 같은 초 2회 → 4hex가 다른 파일 2개, 덮어쓰기 0 · `transcript_path: null` → `transcript: -` · git 아닌 cwd → `branch: -`
  4. 단위 — `AP_HOME=/tmp/x`(홈 밖) → block에 원문 포함, 파일 0개 · `PATH`에서 jq 제거 → 출력 없음 exit 0
  5. 라이브 — `claude --plugin-dir /Users/mini/Github/ai-tools/annoying-point` 새 세션에서 `/ap 테스트` → 화면에 block 한 줄, AI 응답 없음, 세션 transcript의 assistant 턴 수 변화 0 (**검증 항목 1**)
  6. 지연 — 1번 입력으로 30회 실행 p95 < 1초

### 커밋 2 — `feat(fork): 백그라운드 요약기 ap-fork.sh (Claude)`

- 산출: `scripts/ap-fork.sh`(md 읽기 · 지시 조립 · `claude -p --resume --fork-session --output-format json` 실행 — 워치독 300초 · 결과 검증 5단계 · `[ -e ]` 확인 후 inode 덮어쓰기 · `target:` 채움 · `## context` append · `context: done/failed` · log). 요약 지시 전문은 TECH_SPEC §5.4를 스크립트 안 heredoc으로 둔다.
- 의존: 커밋 1
- 예상 줄수: 스크립트 90 + 지시 heredoc 30 ≈ **120줄**
- 검증:
  1. 단위 — 커밋 1의 md를 인자로 `AP_HOME=$TMP bash scripts/ap-fork.sh $TMP/inbox/<id>.md` (세션은 방금 쓴 실제 Claude 세션 id) → 60초 내 md에 `## context` + 5개 `###` 제목, frontmatter `target:` 값 존재 + `context: done`, `log/<id>.log`에 usage 1줄
  2. 단위 — 존재하지 않는 session id → md 본문 무변경 + `context: failed`, `log/<id>.log`에 exit code
  3. 캐시 — log의 `cache_read / (input + cache_read)` ≥ 90%
  4. 격리 — 포크 전후 원본 세션 jsonl의 줄 수·mtime 동일
  5. 라이브 — `claude --plugin-dir` 세션에서 `/ap 테스트` → 훅 즉시 반환 + 60초 내 md 완성. 훅 프로세스가 포크를 기다리지 않음(`ps`로 훅 종료 확인)
  6. **검증 항목 6** — 다른 디렉토리에서 `claude -p --resume <id>` 실행 결과 기록 → `cd "$cwd"` 필요 여부 확정
  7. **검증 항목 7** — 포크 출력 JSON의 `model` 필드(있으면)·usage `cache_read`로 세션 모델·config 계승 확인. 계승 안 되면 훅 입력·transcript에서 세션 모델을 읽어 `--model` 명시

### 커밋 3 — `feat(install): Codex·Cursor 분기 + install.sh`

- 산출: `ap-capture.sh`에 `--agent cursor` 출력 분기(`{"continue":false,"user_message":…}`, `conversation_id`·`workspace_roots[0]` 사용), `ap-fork.sh`에 `codex exec fork` · `cursor-agent -p --resume` 분기, `install.sh`(jq 확인 · `~/.codex/hooks.json` · `~/.cursor/hooks.json` 병합 · 심링크 · AP_HOME 생성 · 멱등)
- 의존: 커밋 1·2. **검증 항목 4**(Codex 출력 캡처 방식·sandbox 플래그)는 이 커밋 착수 시 `codex exec fork --help`로 먼저 확정하고 결과를 커밋 메시지에 기록한다.
- 예상 줄수: capture +15, fork +35, install.sh 90 ≈ **140줄**
- 검증:
  1. 단위 — `HOME=$TMP bash install.sh` → `$TMP/.codex/hooks.json`·`$TMP/.cursor/hooks.json`에 엔트리 존재(절대경로), 심링크 2개, `$TMP/.local/share/ap/{inbox,processed,log}` 존재. 재실행 후 `jq '.hooks.UserPromptSubmit|length'` 값 동일(중복 0)
  2. 단위 — Cursor 입력 JSON(`conversation_id`·`workspace_roots`)으로 `--agent cursor` 실행 → `{"continue":false,"user_message":"📌 ap #… 저장 …"}`, md `agent: cursor`, `session:` = conversation_id
  3. 라이브 Codex — `/ap 테스트` 입력 → md 생성 + block 표시 (**검증 항목 2·3**). 포크 → `## context` 완성 (**검증 항목 4**)
  4. 라이브 Cursor — `/ap 테스트` 입력 → md 생성 + 프롬프트 중단 (**검증 항목 2**). 포크 → `## context` 완성, `conversation_id`로 `--resume` 성공 (**검증 항목 5**)
  5. 격리 — Cursor 인터랙티브 세션에서 "내 메시지 몇 개?" → 포크 전과 같은 수

### 커밋 4 — `feat(notify): SessionStart 알림 ap-notify.sh`

- 산출: `scripts/ap-notify.sh`, `hooks/hooks.json`에 `SessionStart` 추가, `install.sh`에 Codex `SessionStart`(및 Cursor 상당 이벤트가 있으면) 등록 추가
- 의존: 커밋 3
- 예상 줄수: 스크립트 25 + hooks.json 8 + install.sh +12 ≈ **45줄**
- 검증:
  1. 단위 — inbox 0건 → 출력 없음 exit 0 · 3건(파일명 날짜 09-12·09-13·09-14) → `📌 ap inbox 3건 (최근 09-14)` · `AP_HOME` 디렉토리 없음 → 출력 없음 exit 0
  2. 지연 — inbox 100건 픽스처로 30회 p95 < 100ms
  3. 라이브 — Claude 새 세션 첫 화면에 한 줄 표시 확인. 표시 경로(plain stdout vs `systemMessage`)를 실측해 확정하고 커밋 메시지에 기록
  4. 라이브 — Codex 새 세션에서 표시 확인. Cursor는 이벤트 존재 여부 결과를 커밋 메시지에 기록

### 커밋 5 — `feat(skill): ap-review SKILL.md`

- 산출: `skills/ap-review/SKILL.md`(TECH_SPEC §7.2 골격을 채운 전문 — 읽기·묶기·진단·제안·승인·반영·보고 7단계, pending 5분 규칙 · cwd 경로 확인 그룹핑 · 적용 실패 시 보류 · `mv -n` 이동, 표준 하네스 경로 목록, CLI 도구명 없음)
- 의존: 커밋 1·2(리뷰할 md가 있어야 함). 커밋 3의 심링크가 Codex·Cursor 로딩 경로
- 예상 줄수: 마크다운 ≈ **110줄** (코드 아님)
- 검증:
  1. 픽스처 — `$TMP/inbox/`에 md 3건 준비: `target: rule:code-review` 2건 + `target: skill:br-briefing` 1건(`kind: good`) + `target:` 빈 건 1건
  2. 라이브 Claude — `/ap-review` → 그룹 3개(빈 target은 추정 태그로 편입) → 그룹마다 진단·diff 1개 → 1/2/3 질문이 **한 번에 하나씩** → 1 선택 시 파일 수정 + `processed/2026-09/`로 이동 + `resolution:` 추가 → 3 선택 시 inbox 잔류 → 마지막에 바뀐 파일 1줄. 커밋·push 시도 0회
  3. 라이브 Codex(`$ap-review`)·Cursor — 스킬이 로딩되고 같은 절차로 진행되는지 1회씩
  4. 정적 — `grep -n 'AskUserQuestion\|Task(' skills/ap-review/SKILL.md` → 0건 (CLI 특정 도구명 금지)

### 커밋 6 — `docs: commands/ap.md · plugin.json · README`

- 산출: `commands/ap.md`(자동완성 등록 + "훅이 처리해야 함, 여기 도달했으면 install.sh 또는 jq 안내" 본문), `.claude-plugin/plugin.json`(name `annoying-point`, version 0.1.0, 메타데이터만), `README.md`(설치 3 CLI · 사용법 · `AP_HOME` 설정 · 출력 예시 · 알려진 한계)
- 알려진 한계에 명시: Cursor는 포크가 아니라 원본 채팅 append / jq 필수 / context 미생성 시 원문만 리뷰 / Cursor SessionStart 알림 여부(커밋 4 결과)
- 의존: 커밋 1~5
- 예상 줄수: ap.md 15 + plugin.json 15 + README 80 ≈ **110줄** (문서)
- 검증:
  1. `claude plugin validate /Users/mini/Github/ai-tools/annoying-point --strict` 통과
  2. `claude --plugin-dir` 세션 `/help`에 `ap`·`ap-review` 노출
  3. **검증 항목 1 재확인** — `commands/ap.md`가 있는 상태에서도 `/ap 테스트`가 훅에 원문 그대로 도달(커밋 1 검증 5와 동일 절차)
  4. README 절차만 보고 임시 `HOME`에서 3 CLI 설치·`/ap` 1회씩 재현

### 커밋 7 — `docs(verify): 검증 항목 7개 라이브 확인 결과 기록`

- 산출: `docs/TECH_SPEC.md` §11 표에 항목별 통과/실패·확인 명령·날짜 추가. 실패 항목은 "실패 시" 대응을 적용한 코드 변경을 **별도 `fix:` 커밋**으로 분리
- 의존: 커밋 1~6 (각 항목은 해당 커밋에서 이미 1회 확인됨 — 여기서는 최종 상태로 7개를 한 번에 재확인)
- 예상 줄수: 문서 20줄, 코드 0줄(실패 없을 때)
- 검증: 7개 항목 전부 "통과" 또는 "대응 적용 후 통과"로 기록됨. 미확인 항목 0개

### 단계 8 — 마켓플레이스 등록 · my-harness 설정 (이 PR 범위 밖)

- `token-keeper/plugins`에 submodule 추가 + marketplace.json 항목. 원격 repo `https://github.com/token-keeper/annoying-point` 생성이 선행. **대표 승인 후 실행.**
- my-harness: `AP_HOME=~/Github/ai-tools/my-harness/feedback` 설정(`~/.config/ap/config` 또는 env), 마켓플레이스 설치 항목 1줄, 기존 br-briefing 회수 모드 흡수. 별도 세션·별도 PR.

## 3. 검증 계획

### 로컬 설치 (마켓플레이스 등록 전)

1. `claude plugin validate <repo> --strict` — 매니페스트·hooks·커맨드·스킬 정의 정적 검증.
2. `claude --plugin-dir /Users/mini/Github/ai-tools/annoying-point` — 세션 한정 로드, 전역 설정 오염 없음.
3. Codex·Cursor — `HOME=$TMP bash install.sh`로 먼저 멱등성을 확인한 뒤, 실제 `~/.codex`·`~/.cursor`에 등록한다. 실제 등록 전 두 hooks.json을 `*.bak`으로 복사해 둔다.
4. 모든 라이브 검증은 `AP_HOME=$TMP`(임시 디렉토리)로 실행한다.

### 실측 체크리스트

| # | 항목 | 판정 | 커밋 |
|---|---|---|---|
| 1 | 캡처 단위 케이스 (매칭·good·사용법·충돌·null·홈 밖·jq 없음) | 전부 기대 출력, 파일 권한 600 | 1 |
| 2 | Claude 라이브 캡처 — 턴 0·토큰 0 | block 한 줄 표시, assistant 턴 증가 0 | 1 |
| 3 | 포크 완성 — `## context` 5섹션 + `target:` | 60초 내, cache read ≥ 90% | 2 |
| 4 | 포크 격리 — 원본 세션 파일 무변경 | 줄 수·mtime 동일 | 2 |
| 5 | 포크 자식 모델·config 계승 (검증 7) | 출력 JSON `model`(있으면)·usage `cache_read`로 확인 | 2 |
| 6 | Codex·Cursor 라이브 캡처 + 포크 | md 생성·block·context 완성 | 3 |
| 7 | install.sh 멱등 | 재실행 후 엔트리 수 동일 | 3 |
| 8 | SessionStart 알림 | 0건 무출력, N건 1줄, 100ms 미만 | 4 |
| 9 | `/ap-review` 대화형 절차 | 그룹·진단·diff·1/2/3 하나씩·processed 이동·resolution | 5 |
| 10 | README 재현 | 문서만 보고 3 CLI 설치·실행 | 6 |
| 11 | 검증 항목 7개 최종 | 전부 통과 기록 | 7 |

체크리스트 2·3·4는 이 플러그인의 존재 이유(메인 세션 비용 0 + 상황 복원)이므로 **최소 1회는 반드시 실세션에서 수행**한다.

## 4. 마일스톤

| 마일스톤 | 포함 커밋 | 종료 조건 |
|---|---|---|
| **M1 — Claude E2E** | 커밋 1~2 | Claude에서 `/ap` → 즉시 block + 60초 내 context 완성. 체크리스트 1~5 통과 |
| **M2 — 3 CLI + 알림** | 커밋 3~4 | Codex·Cursor에서 같은 동작, install.sh 멱등, SessionStart 1줄. 체크리스트 6~8 통과 |
| **M3 — 리뷰·문서** | 커밋 5~6 | `/ap-review` 대화형 절차 동작, README 재현. 체크리스트 9~10 통과 |
| **M4 — 검증·등록** | 커밋 7 + 단계 8 | 검증 항목 7개 기록 완료. 마켓플레이스·my-harness는 대표 승인 후 별도 진행 |

## 5. 리스크·롤백

| 리스크 | 대응 |
|---|---|
| `/ap`가 훅에 원문으로 안 오고 커맨드 전개 결과가 옴 (검증 항목 1) | `commands/ap.md` 제거하고 자동완성 포기, 또는 `UserPromptExpansion` 이벤트로 전환. 커밋 1 라이브 검증에서 즉시 판정 |
| Codex·Cursor가 미등록 `/ap`를 CLI 단에서 거부 (검증 항목 2) | `$ap` 표기 또는 스킬로 등록해 훅까지 도달시킴. 커밋 3에서 판정 |
| 포크가 훅 timeout 안에 안 끝남 | 설계상 훅은 기동만 하고 반환 — fd 리다이렉트 누락이 유일한 실패 원인. 커밋 2 검증 5(`ps`)로 확인 |
| 포크가 uncached로 돌아 비용 급증 | 캐시 조건 3개(config dir·모델·TTL) 준수. 커밋 2 검증 3에서 비율 실측, 90% 미만이면 원인 확인 후 대표 보고 |
| 훅이 프롬프트를 삼켜 원문 유실 | 저장 실패 시 block reason에 원문 포함. jq 없음은 통과(AI에 전달) |
| Cursor 포크가 원본 채팅을 오염 | 사전관찰에서 append만 확인(덮어쓰기·깨짐 없음). 감수하기로 확정. 커밋 3 검증 5로 재확인 |
| install.sh가 기존 hooks.json을 망가뜨림 | jq 병합 + 실행 전 `*.bak` 복사. `HOME=$TMP`로 먼저 검증 |
| 롤백 | Claude: 플러그인 제거. Codex·Cursor: hooks.json의 엔트리 2개·심링크 2개 제거(`*.bak` 복원). 저장 데이터는 `$AP_HOME`에만 있어 삭제 여부는 사용자가 정한다 |
