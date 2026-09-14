# annoying-point

AI로 개발하다 짜증나는 점·좋은 점을 `$ap <한마디>` 한 줄로 그 자리에서 남기고, 나중에 `ap-review`로 모아 하네스(CLAUDE.md·룰·스킬·훅)를 고치는 플러그인. Claude Code · Codex CLI · Cursor Agent CLI 공용.

왜: "이건 룰을 무시했다", "표가 너무 길다", "이 판단은 좋았다" 같은 순간은 하루에도 여러 번 생기지만, 메인 세션에 말하면 턴·토큰을 쓰고 작업 흐름이 끊긴다. 따로 메모하면 며칠 뒤 어느 세션·어느 룰 때문이었는지 복원할 수 없다. 답은 그 세션 안에 있으니, 사용자는 한마디만 남기고 상황 복원은 그 세션을 포크한 AI가 대신한다.

- **메인 세션 턴 0 · 토큰 0** — 훅이 프롬프트를 가로채 저장하고 block한다. 메인 AI에는 아무것도 전달되지 않는다.
- **상황 자동 복원** — 백그라운드에서 그 세션을 포크해 5섹션 context(상황·경위·문제·추정 원인·근거)와 `target` 태그를 붙인다. 같은 모델·같은 config라 prefix 캐시를 탄다 (실측 `cache_read 300,588 / input 2`).
- **3 CLI 공용** — Claude Code · Codex CLI · Cursor Agent CLI 어디서 남겨도 같은 md 포맷으로 같은 저장소에 쌓인다.

## 동작

```
사용자 ──"$ap 표 너무 김"──▶ CLI ──UserPromptSubmit / beforeSubmitPrompt──▶ scripts/ap-capture.sh
                                                                            │
   ┌────────────────────────────────────────────────────────────────────────┤
   │ ① $AP_HOME/inbox/<id>.md 즉시 생성 (frontmatter + 원문, 권한 600)        │
   │ ② scripts/ap-fork.sh <md> 를 새 세션(setsid)으로 완전 분리 기동           │
   │ ③ block: "📌 ap #<id> 저장 · context 생성 중" → 메인 AI 미전달 (턴 0)   │
   └────────────────────────────────────────────────────────────────────────┘
                                        ‖ (백그라운드 — 메인 세션과 무관)
   ap-fork.sh ─▶ 그 세션 포크 (claude -p --resume --fork-session / codex exec fork / cursor-agent -p --resume)
              ─▶ 첫 줄 `target:` → frontmatter ─▶ 나머지 → md 끝에 `## context` ─▶ `context: done`
              ─▶ 실패 → `context: failed` + $AP_HOME/log/<id>.log (md 원문은 유지)

세션 시작 ──SessionStart──▶ scripts/ap-notify.sh ──▶ "📌 ap inbox 3건 (최근 09-14)" (0건이면 무출력)
사용자 ──ap-review──▶ 훅 통과 ──▶ 현재 세션 AI가 skills/ap-review/SKILL.md 절차를 대화형으로 수행
```

## 설치

선행 조건: `jq`(macOS 15 이상 기본 탑재 `/usr/bin/jq`, 없으면 `brew install jq`), `perl`(macOS 기본 — 포크 프로세스 분리에 사용, 없으면 nohup 폴백).

| CLI | 방법 |
|---|---|
| Claude Code | 마켓플레이스 `token-keeper/plugins` 등록 예정. 등록 전에는 `claude --plugin-dir /절대/경로/annoying-point` (세션 한정 로드, 전역 설정 무변경). 훅·커맨드·스킬이 플러그인으로 자동 등록되므로 `install.sh` 불필요 |
| Codex CLI · Cursor | repo에서 `bash install.sh` |

`install.sh`가 하는 일 (재실행 멱등):

1. `jq` 확인 — 없으면 안내 후 exit 1
2. `~/.codex/hooks.json`에 `UserPromptSubmit`(캡처) · `SessionStart`(알림) 병합
3. `~/.cursor/hooks.json`에 `beforeSubmitPrompt`(캡처) · `sessionStart`(알림) 병합
4. 기존 항목 보존 — 같은 command가 이미 있으면 건너뛰고, 올바르지 않은 JSON은 손대지 않는다. 파일을 바꾸기 전 `<파일>.bak-<타임스탬프>`로 백업
5. `$AP_HOME/{inbox,processed,log}` 생성 (권한 700)
6. `--skills`를 주면 `~/.agents/skills/ap-review` · `~/.cursor/skills/ap-review` 심링크 생성 (기본은 스킵 — 그 디렉토리가 다른 repo로 가는 심링크인 환경 보호)

```bash
bash install.sh --dry-run     # 바뀔 JSON만 출력, 파일은 손대지 않는다
bash install.sh               # 훅 등록 + AP_HOME 생성
bash install.sh --skills      # + ap-review 스킬 심링크 (Codex·Cursor에서 리뷰를 쓰려면 필요)
```

## 사용법

### 캡처

| CLI | 입력 |
|---|---|
| Claude Code | `/annoying-point:ap <한마디>` 또는 플레인 텍스트 `$ap <한마디>` |
| Codex CLI | `$ap <한마디>` |
| Cursor | `$ap <한마디>` |

- 좋은점은 `+` 접두: `$ap +브리핑 표 형식 좋음` → `kind: good`으로 저장 (접두는 원문에서 제거).
- 인자 없는 `$ap`는 저장하지 않고 사용법 한 줄만 표시한다.
- bare `/ap`는 세 CLI 모두 미등록 슬래시 커맨드라 훅에 도달하지 않는다 (실측). Claude는 네임스페이스 `/annoying-point:ap`, 나머지는 `$ap`.

화면 표시 (실측):

| CLI | 표시 |
|---|---|
| Claude Code | `/annoying-point:ap` → `UserPromptExpansion operation blocked by hook: 📌 ap #<id> 저장 · context 생성 중` · `$ap` → `UserPromptSubmit operation blocked by hook: 📌 …` |
| Codex CLI | `Blocked by hook` |
| Cursor | 프롬프트만 사라지고 메시지는 표시되지 않는다 (저장·포크는 정상) |

몇 초~수십 초 뒤 (실측 Claude 36초 · Codex 27초 · Cursor 18초) md에 `## context`가 붙고 `context: done`이 된다.

### 리뷰

| CLI | 입력 |
|---|---|
| Claude Code | `/annoying-point:ap-review` |
| Codex CLI | `$ap-review` |
| Cursor | 스킬 로딩(`install.sh --skills` 또는 프로젝트 `.cursor/skills/ap-review` 심링크) 후 "ap 리뷰 해줘" 같은 명시 요청 — 실측: 슬래시 목록에는 안 뜨고 자연어 요청으로 `Used ap-review` 로딩됨 |

현재 세션 AI가 대화형으로 진행한다: inbox 전부 읽기 → `target`별 그룹 → 진단(반복 vs 1회성, 원인 파일 특정) → 그룹당 diff 1개 → **그룹 하나씩** 1 반영 / 2 스킵 / 3 보류 → 반영한 건은 `resolution:`을 붙여 `processed/YYYY-MM/`으로 이동 → 바뀐 파일 목록 1줄. 커밋·push는 하지 않는다. 서브에이전트·헤드리스 위임도 없다.

### 세션 시작 알림

inbox에 1건 이상 있으면 한 줄: `📌 ap inbox 3건 (최근 09-14)`. 0건이면 아무것도 표시하지 않는다. 표시 위치(실측): Claude는 세션 첫 화면 `SessionStart:startup says: …`, Codex는 첫 프롬프트를 보낸 직후 그 아래 `↳ Hook · …`(시작 화면엔 안 뜸), Cursor는 `additional_context`라 모델 컨텍스트에만 들어가고 화면에는 보이지 않는다.

## 저장 위치·형식

`AP_HOME` 해석 순서 — 훅·포크·리뷰·install.sh 전부 같은 규칙:

1. 환경변수 `AP_HOME`
2. `~/.config/ap/config`의 `AP_HOME=` 줄 (첫 줄만, `~`는 `$HOME`으로 치환)
3. 기본 `~/.local/share/ap`

`$HOME` 아래만 허용한다. 밖이면 저장을 거부하고 원문을 block 메시지로 되돌려 준다.

```
$AP_HOME/
├── inbox/       <YYYY-MM-DD>_<HHMMSS>_<agent>_<repo>_<4hex>.md   (권한 600)
├── processed/   YYYY-MM/  리뷰가 처리한 건 (resolution: 추가)
└── log/         <id>.log  포크 stderr·exit code·usage 1줄
```

md 예시 (frontmatter는 YAML이 아니라 `key: value` 한 줄 규약 — 따옴표·이스케이프·주석 없음):

```markdown
---
ts: 2026-09-14 14:32
agent: claude
kind: annoying
repo: my-harness
branch: feature/shared-agent-harness
cwd: /Users/me/Github/my-harness
session: a2c2cbd5-…
transcript: /Users/me/.claude/projects/…/a2c2cbd5-….jsonl
target: skill:br-briefing, rule:code-review
context: done
---
표 너무 김

## context
### 상황
### 경위
### 문제
### 추정 원인
### 근거
```

`target`은 `skill:<이름>` / `rule:<파일명>` / `tool:<이름>` / `model` / `env` 중 하나(여럿이면 쉼표). 플러그인은 git을 모른다 — `$AP_HOME`을 git repo로 두면 머신 간 공유는 사용자가 commit·pull로 한다.

## 알려진 한계

1. **Cursor는 포크가 아니라 원본 채팅에 append** — `cursor-agent`에 fork가 없어 `--resume`으로 요약 턴이 그 채팅에 추가된다 (덮어쓰기·깨짐 없음, 감수).
2. **Cursor CLI는 block 메시지를 표시하지 않는다** — 프롬프트만 사라진다. 저장·포크는 정상.
3. **bare `/ap` 불가** — Claude `/annoying-point:ap`, Codex·Cursor `$ap`.
4. **`jq`·`perl` 필수** — jq가 없으면 훅이 아무것도 하지 않고 프롬프트가 AI에 통과한다 (Claude는 `commands/ap.md` 안내가 전달됨). perl이 없으면 nohup 폴백 — Cursor에서는 훅 종료 시 프로세스 그룹이 함께 죽어 포크가 실패한다.
5. **context 생성 실패 시 원문만 리뷰** — `context: failed`, 원인은 `log/<id>.log`. 재시도 없음 (Cursor 빈 결과만 1회 재시도).
6. **포크 워치독 300초** — 초과 시 자식 kill, `context: failed`, log `timeout 300s`. `AP_FORK_TIMEOUT` 환경변수로 조정.
7. **Claude 포크는 `--settings '{"disableAllHooks":true}'`** — 전역 Stop 훅이 살아 있으면 `claude -p`가 종료하지 못하는 것 실측. 시스템 프롬프트는 바뀌지 않아 캐시는 유지된다.

## 개발

```bash
bash scripts/test-capture.sh   # 91/91
bash scripts/test-fork.sh      # 64/64 (실세션 검증은 AP_FORK_SESSION 등 env 지정 시)
bash scripts/test-install.sh   # 47/47
bash scripts/test-notify.sh    # 16/16
```

외부 프레임워크 없음. 테스트는 `$HOME` 아래 임시 디렉토리에 `AP_HOME`·`HOME`을 두고 실행하므로 실제 저장소·`~/.codex`·`~/.cursor`는 건드리지 않는다.

설계 문서: [docs/PRD.md](docs/PRD.md) · [docs/TECH_SPEC.md](docs/TECH_SPEC.md) · [docs/PLAN.md](docs/PLAN.md)

라이선스: [MIT](LICENSE)
