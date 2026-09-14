# annoying-point — PRD

> 작성일 2026-09-14 (월) · 상태 설계 확정(구현 전) · 대상 제품 Claude Code · Codex CLI · Cursor Agent CLI 공용 플러그인 `annoying-point` (슬래시 커맨드 `/ap` · `/ap-review`)

## 1. 개요

### 한 줄 정의

AI로 개발하다가 짜증나는 점·좋은 점을 `/ap <한마디>`로 그 자리에서 남기면, 훅이 가로채 **메인 세션 컨텍스트를 건드리지 않고** 저장하고, 백그라운드에서 그 세션을 포크해 상황 요약을 붙인다. 나중에 `/ap-review`로 쌓인 것을 대화형으로 모아 보며 하네스(CLAUDE.md·룰·스킬·훅)를 고친다.

- 플러그인·repo 이름: `annoying-point` (철자 주의: annoying). GitHub `https://github.com/token-keeper/annoying-point` (private으로 시작, 공개 예정). 로컬 `~/Github/ai-tools/annoying-point`.
- 명령: `/ap` (캡처), `/ap-review` (리뷰). 좋은점은 `/ap +한마디` → `kind: good`.
- 대상 CLI 3종: Claude Code, Codex CLI(0.154.0), Cursor Agent CLI(2026.09.10). 셋 다 같은 동작.
- 형제 플러그인(구조 참조): `~/Github/ai-tools/what-did-i-say`.

### 배경 · 문제

AI 코딩 도구를 하루 여러 시간 쓰면 "이건 룰을 무시했다", "표가 너무 길다", "이 도구 판단은 좋았다" 같은 순간이 하루에도 수 회 생긴다. 지금은 이 순간을 남길 방법이 셋뿐이고 전부 비용이 크다.

1. **메인 세션에 말한다** — 턴 1개와 토큰을 소비하고, 현재 작업 컨텍스트에 무관한 대화가 섞인다. AI가 "죄송합니다"로 응답하며 작업 흐름이 끊긴다.
2. **다른 곳에 메모한다** — 전환 비용 때문에 대부분 생략된다. 남겨도 "표 너무 김" 한 줄뿐이라 며칠 뒤에는 어느 세션·어느 룰 때문이었는지 복원할 수 없다.
3. **기억에 의존한다** — 하네스(CLAUDE.md·룰·스킬) 개선이 감으로 이루어지고, 같은 짜증이 반복된다. 유지해야 할 좋은 패턴은 아예 기록되지 않는다.

답은 이미 그 세션 안에 있다. 사용자는 한마디만 남기고, 상황 복원은 그 세션을 포크한 AI가 대신하면 된다.

## 2. 목표 / 비목표

### 목표

- **G-1 캡처 비용 0** — `/ap`는 메인 AI에 전달되지 않는다(턴 0·추가 토큰 0). 입력 후 1초 안에 저장 확인 한 줄이 표시된다.
- **G-2 상황 자동 복원** — 백그라운드 포크가 5섹션 context(상황·경위·문제·추정 원인·근거)와 `target` 태그를 채운다. 리뷰어가 트랜스크립트를 열지 않아도 판단할 수 있어야 한다.
- **G-3 3 CLI 동일 동작** — Claude Code·Codex·Cursor 어디서 `/ap`를 쳐도 같은 md 포맷으로 같은 저장소에 쌓인다.
- **G-4 대화형 리뷰** — `/ap-review`가 현재 세션 AI 안에서 target별 그룹 → 진단 → diff 수준 수정안 → 그룹별 승인 → 반영 → `processed/` 이동까지 진행한다.
- **G-5 저장소 하나** — 모든 구성요소는 `$AP_HOME` 하나만 본다. git·동기화는 모른다.
- **G-6 좋은점도 같은 명령** — `/ap +한마디`로 유지할 패턴을 같은 흐름으로 남긴다.

### 비목표

- **NG-1** 자동 수정(승인 없는 반영)
- **NG-2** 백그라운드 리뷰·서브에이전트 위임 리뷰
- **NG-3** 클라우드·머신 간 동기화
- **NG-4** 프로젝트별 저장소, 웹 UI, HTML 채점 버튼
- **NG-5** 트랜스크립트 직접 파싱

상세와 이유는 §7.

## 3. 대상 사용자 & 유저 스토리

### 대상 사용자

Claude Code·Codex·Cursor를 하루 여러 시간 쓰며 자기 하네스(글로벌 CLAUDE.md·룰·스킬·훅)를 직접 관리하는 개발자. 한 턴이 수 분 이상 걸리는 위임·리뷰 작업을 반복하고, 여러 프로젝트 탭을 동시에 띄운다.

### 유저 스토리

- **US-1 캡처** As a 작업 중 짜증을 느낀 개발자, I want to `/ap 표 너무 김` 한 줄만 치고 바로 작업으로 돌아가기를, So that 메인 세션 턴·토큰을 쓰지 않고도 그 순간이 상황과 함께 남는다.
- **US-2 좋은점** As a 마음에 드는 응답을 받은 개발자, I want to `/ap +브리핑 표 형식 좋음`으로 같은 명령에 `+`만 붙여 남기기를, So that 유지해야 할 패턴이 짜증과 같은 저장소에 쌓여 리뷰 때 "지키기" 항목으로 다뤄진다.
- **US-3 리뷰** As a 하네스를 관리하는 개발자, I want to `/ap-review`로 쌓인 기록을 target별로 묶어 진단·수정안을 받고 그룹마다 1/2/3으로 승인하기를, So that 반복되는 짜증이 룰·스킬 수정으로 이어지고 처리된 건은 inbox에서 빠진다.
- **US-4 세션 시작 알림** As a 여러 세션을 오가는 개발자, I want to 세션이 시작될 때 `📌 ap inbox 7건 (최근 09-14)` 한 줄을 보기를, So that 리뷰할 게 쌓였는지 별도 확인 없이 알고 0건이면 아무것도 보지 않는다.
- **US-5 3 CLI** As a CLI를 상황마다 바꿔 쓰는 개발자, I want to Codex·Cursor에서도 같은 `/ap`가 같은 저장소에 쌓이기를, So that 어느 도구에서 생긴 짜증이든 한 번의 리뷰로 모아 본다.

## 4. 기능 요구사항

### F-1 캡처 훅

- 이벤트: Claude·Codex `UserPromptSubmit`, Cursor `beforeSubmitPrompt`. 훅 스크립트는 bash + jq 1개(`scripts/ap-capture.sh`)를 3 CLI가 공용하고 Cursor만 출력 JSON 분기를 둔다.
- 매칭: 프롬프트가 정규식 `^[/$]ap([[:space:]]|$)`에 맞을 때만 동작한다(Codex 스킬 호출 표기 `$ap` 포함). `/ap-review`는 매칭 제외 — 리뷰는 AI가 받아야 한다. 그 외 프롬프트는 출력 없이 exit 0으로 통과한다.
- 동작 순서: ① `$AP_HOME/inbox/<id>.md` 즉시 생성(원문 + frontmatter, `context: pending`. `<id>` = `<YYYY-MM-DD>_<HHMMSS>_<agent>_<repo>_<4hex>` — F-3) ② 백그라운드 포크 요약기 기동(완전 분리, 훅은 기다리지 않음) ③ 프롬프트 block — 사용자에게 `📌 ap 저장됨 #<id> (정상 — 훅이 가로챔, 답변 없음) · 30초 뒤 상황 요약 자동 첨부` 한 줄 표시, 메인 AI 미전달.
- `+` 접두: `kind: good`으로 저장하고 접두는 원문에서 제거한다.
- 인자 없는 `/ap`: 저장하지 않고 사용법 한 줄을 block으로 표시한다.

### F-2 백그라운드 포크 요약기

- 훅이 띄운 런처(`scripts/ap-fork.sh`)가 **그 세션을 포크**해 요약 지시를 보낸다: Claude `claude -p --resume <session_id> --fork-session`, Codex `codex exec fork <session_id>`, Cursor `cursor-agent -p --resume <conversation_id>`(fork 없음 → 원본 채팅에 append됨, 감수).
- 요약기는 도구를 쓰지 않고 텍스트만 출력한다. 5섹션(상황·경위·문제·추정 원인·근거) 고정, 한글.
- 런처가 출력의 `target:` 줄을 frontmatter에 채우고 나머지를 md 끝에 `## context` 섹션으로 붙인다.
- 결과 검증 5단계(exit 0 → JSON 파싱 → `.is_error` 아님 → `.result`가 비어 있지 않은 문자열 → 필수 섹션 5개) 통과 시에만 `context: done`, 그 외는 `context: failed`. 워치독 기한 300초 — 초과 시 자식 kill.
- 캐시 조건을 지킨다 — 같은 config dir, 같은 모델(`--model` 미지정), TTL 내 호출. 저가 모델로 바꾸지 않는다.
- 실패하면 `$AP_HOME/log/<id>.log`에 stderr·exit code를 남기고 md는 context 없이(`context: failed`) 둔다. 재시도하지 않는다.

### F-3 저장·AP_HOME

- 해석 순서: env `AP_HOME` → `~/.config/ap/config`의 `AP_HOME=` 줄 → 기본 `~/.local/share/ap`.
- 디렉토리: `inbox/`(미처리), `processed/YYYY-MM/`(처리 완료), `log/`(요약기 실패 로그).
- 항목당 md 1개. 파일명 `<YYYY-MM-DD>_<HHMMSS>_<agent>_<repo>_<4hex>.md`(초 + 4자리 hex 랜덤 — ID 재사용·덮어쓰기 없음). 생성은 noclobber, `processed/` 이동은 `mv -n`.
- 모든 파일은 권한 600으로 생성한다(원문·요약에 비밀값이 섞일 수 있다).
- 스킬·훅·리뷰 전부 `AP_HOME` 하나만 본다. git·동기화는 모른다(`mv`만). 사용자가 `AP_HOME`을 git repo 아래로 두면 동기화는 사용자 몫이다.

### F-4 리뷰 스킬 `/ap-review`

- 현재 세션 AI가 대화형으로 진행한다. 서브에이전트·헤드리스 위임 없음.
- 절차: 읽기(`inbox/*.md` 전부, context 없는 건 원문만) → 묶기(`target`별, 1건도 그룹) → 진단(반복 vs 1회성, 원인 파일 특정) → 제안(그룹당 diff 수준 수정안 1개, `good`은 "유지 패턴"으로 CLAUDE.md·메모리 추가 제안) → 승인(그룹별 1 반영 / 2 스킵(이유 기록) / 3 보류, **한 번에 하나씩**) → 반영(파일 수정 → `processed/YYYY-MM/` 이동, frontmatter에 `resolution:` 추가) → 보고(바뀐 파일 목록 1줄).
- **커밋·push 없음**(사용자 몫).
- 하네스 위치는 표준 경로 기준으로 탐색한다: `~/.claude/CLAUDE.md`, `~/.claude/skills`, `~/.agents/skills`, `~/.cursor/skills`, 프로젝트 `CLAUDE.md`/`AGENTS.md`. 사용자 전용 경로 하드코딩 금지.
- 스킬 본문에 CLI 특정 도구명을 쓰지 않는다("질문 도구 있으면 쓰고 없으면 대화로").

### F-5 SessionStart 알림

- `$AP_HOME/inbox/*.md` 개수를 세어 1줄 출력: `📌 ap inbox 7건 (최근 09-14)`. 0건이면 아무것도 출력하지 않는다. LLM 미개입.
- Claude: 플러그인 `hooks.json`의 `SessionStart`. Codex: `SessionStart` 등록. Cursor: 해당 이벤트 존재 미확인 → install.sh에서 가능하면 등록, 아니면 생략.

### F-6 install.sh (Codex·Cursor)

- Claude는 플러그인 설치로 훅·명령·스킬이 자동 등록된다. Codex·Cursor는 `install.sh` 1회 실행으로 등록한다.
- 하는 일: `~/.codex/hooks.json`·`~/.cursor/hooks.json`에 훅 엔트리 추가(스크립트 절대경로 기록, 기존 엔트리 보존), 스킬 심링크(`~/.agents/skills`, `~/.cursor/skills`), `$AP_HOME` 디렉토리 생성, jq 존재 확인.
- 재실행해도 중복 등록되지 않는다.

### F-7 3 CLI 지원

- 대상: Claude Code, Codex CLI 0.154.0, Cursor Agent CLI 2026.09.10.
- 저장 md 포맷·`AP_HOME`·리뷰 스킬은 3 CLI 공용이다. 차이는 훅 등록 방식(플러그인 vs install.sh), Cursor 출력 JSON 키, 포크 명령 3종뿐이다.
- 스킬은 Claude·Codex·Cursor 공용 SKILL.md 표준 1개로 작성한다.

## 5. 성공 지표

| 지표 | 목표값 | 측정 방법 |
|---|---|---|
| 캡처 지연 (엔터 → 저장 확인 표시) | **p95 1초 미만** | 훅 입력 JSON을 stdin으로 준 `ap-capture.sh` 단독 실행 30회의 p95 + 실세션 육안 1회 |
| 메인 세션 추가 토큰 | **0** | 캡처 전후 메인 세션 transcript(jsonl)의 assistant 턴 수 변화 0 · `/ap` 원문이 AI 메시지에 등장 0회 |
| 메인 세션 원문 오염 | **0건** | Cursor 사전관찰과 같은 방식 — 캡처 뒤 "내 메시지 몇 개?"에 캡처 전과 같은 수 응답 |
| context 생성 성공률 | **10건 중 9건 이상**(`context: done`) | 실사용 첫 10건의 md에서 `context: done` 비율. 실패 건(`context: failed`)은 `log/`에 원인 존재 |
| 포크 cache read 비율 | **90% 이상** | 포크 출력 usage의 `cache_read / (input + cache_read)`. Cursor 사전관찰 실측 18,528 / (152 + 18,528) = 99.2% |
| 포크 완료 시간 (캡처 → `## context` append) | **60초 이내** (워치독 기한 300초) | md mtime − 캡처 시각. Cursor 사전관찰 실측 5.2초 |
| SessionStart 알림 지연 | **100ms 미만** | `ap-notify.sh` 단독 실행 30회 p95 (inbox 100건 픽스처) |
| 실패 시 사용자 영향 | **0건** (턴 차단·원문 유실 없음) | jq 없음 · AP_HOME 쓰기 불가 · transcript null 3개 케이스에서 훅이 통과 또는 원문 포함 안내로 종료 |
| 저장 파일 권한 | **전부 600** | inbox·processed·log의 모든 파일 `stat -f %Lp` = 600 |

## 6. 검증 항목 (구현 때 라이브로 확인)

| # | 항목 | 확인 방법 |
|---|---|---|
| 1 | 플러그인 커맨드로 등록된 `/ap`가 Claude `UserPromptSubmit`에 **원문 그대로** 오는지 (whip 선례상 됨. `UserPromptExpansion` 이벤트와의 순서 확인) | `claude --plugin-dir` 세션에서 `/ap 테스트` → inbox md 생성 + block 표시 |
| 2 | Codex·Cursor에서 미등록 `/ap` 입력이 훅까지 도달하는지 (CLI가 "unknown command"로 먼저 막는지) | 각 CLI에서 `/ap 테스트` 입력 → inbox md 생성 여부 |
| 3 | Codex `UserPromptSubmit` block 라이브 동작 | Codex에서 `/ap 테스트` → AI 응답 없이 block 메시지만 표시 |
| 4 | Codex `codex exec fork` 출력 캡처 방법(`-o`/`--output-last-message`)과 sandbox 플래그 | `codex exec fork --help` 확인 + 1회 실행으로 stdout·파일 출력 비교 |
| 5 | Cursor 훅 `conversation_id` == `--resume` id | 훅 입력의 `conversation_id`로 `cursor-agent -p --resume` 실행 → 원본 컨텍스트 계승 응답 확인 |
| 6 | Claude `claude -p --resume`이 세션 cwd 밖에서도 세션을 찾는지 (안 되면 `cd "$cwd"` 필수) | 다른 디렉토리에서 `--resume <id>` 실행 → 성공/실패 기록 |
| 7 | 훅에서 기동된 포크 자식이 세션 모델·config를 실제로 계승하는지 (`--model` 생략만으로는 증명되지 않음) | 포크 출력 JSON의 `model` 필드(있으면)·usage `cache_read` 확인. 실패 시 세션 모델을 훅 입력·transcript에서 읽어 `--model` 명시 |

## 7. 비목표 상세

| # | 하지 않는 것 | 대신 |
|---|---|---|
| NG-1 | 자동 수정 — 승인 없는 하네스 반영 | 그룹별 1/2/3 승인, 한 번에 하나씩 |
| NG-2 | 백그라운드 리뷰, 서브에이전트·헤드리스 위임 리뷰 | 현재 세션 AI가 대화형으로 |
| NG-3 | 클라우드·머신 간 동기화 | 사용자가 `AP_HOME`을 git repo 아래로 두면 알아서 |
| NG-4 | 프로젝트별 저장소, 웹 UI, HTML 채점 버튼 (기존 br-briefing 회수 모드는 이 플러그인으로 흡수 — my-harness 쪽 후속) | 저장소 하나(`AP_HOME`), 리뷰는 터미널 대화 |
| NG-5 | 트랜스크립트 직접 파싱 | 세션 포크가 대신 읽는다 |
