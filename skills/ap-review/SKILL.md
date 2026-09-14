---
name: ap-review
description: $AP_HOME/inbox에 쌓인 짜증·좋은점 기록(/ap 캡처)을 target별로 묶어 진단하고, 그룹 하나씩 승인받은 수정안만 하네스(CLAUDE.md·AGENTS.md·rules·skills·훅)에 반영한 뒤 processed로 옮기는 대화형 리뷰. 사용자가 /ap-review를 호출하거나 "ap 리뷰", "짜증 리뷰", "inbox 정리", "쌓인 피드백 정리" 류를 명시적으로 요청할 때 사용. 명시 호출 없이는 자동 발동하지 않는다.
---
# ap-review — 짜증·좋은점 inbox 리뷰

`/ap <한마디>`로 쌓인 기록을 모아 원인 파일을 찾고, 승인받은 것만 고친다. 전 과정을 **현재 세션이 직접, 대화형으로** 수행한다 —
서브에이전트·헤드리스 위임 없음, 커밋·push 없음, 사용자 홈 밖 쓰기 없음. 한글로 진행한다.

## 0. 준비

1. `AP_HOME` 해석 — 순서대로 첫 번째 것: ① env `AP_HOME` ② `~/.config/ap/config`의 `AP_HOME=` 첫 줄(`~`는 `$HOME`) ③ `~/.local/share/ap`.
2. `$AP_HOME/inbox/*.md` 목록. **0건이면 "inbox 비어 있음" 한 줄로 끝.**
3. 파일마다 `context:` 값으로 이번 리뷰 포함 여부를 정한다:
   - `done` → context까지 사용
   - `pending`이고 `ts`가 지금부터 5분 이내 → **이번 리뷰 제외**, 목록에 "요약 대기 중"으로만 표시
   - `pending` 5분 초과 · `failed` → 원문(한마디)만으로 리뷰

## 1. 읽기

md 포맷은 한 줄 규약이다 — frontmatter는 YAML이 아니라 `key: value`(콜론+공백 뒤 줄 끝까지가 값, 이스케이프·주석 없음),
첫 `---`와 둘째 `---` 사이가 frontmatter, 그 다음 줄이 원문 한마디, `## context` 아래가 요약(있을 때만).
키: `ts agent kind repo branch cwd session transcript target context`. 값 추출은 `sed -n 's/^key: //p' file | head -1`.

전부 읽고 표 1개로 요약한다: `| id | agent | repo | kind | target | context | 한마디 |`. id는 파일명에서 `.md`를 뺀 것.

## 2. 묶기

- 그룹 키 = `target`의 **첫 태그**(`skill:br-briefing, rule:code-review`면 `skill:br-briefing`). 1건도 그룹이다.
- `target`이 비어 있으면 원문·context로 태그를 추정해 편입한다. 태그 형식: `skill:<이름>` / `rule:<파일명>` / `tool:<이름>` / `model` / `env`. 추정임을 표에 표시.
- `rule:`/`skill:`이 **프로젝트 스코프 파일**(프로젝트 `CLAUDE.md`·`AGENTS.md`·`.claude/skills`·`.cursor/rules`)이면 기록의 `cwd`로 실제 경로를 확인해 그룹 키에 경로를 붙인다(예: `rule:CLAUDE.md @ ~/Github/foo`). 같은 이름이라도 프로젝트가 다르면 다른 그룹.
- `cwd`에 접근할 수 없으면 "경로 불가"로 표시하고 **현재 프로젝트 파일로 대체 해석하지 않는다.**
- `kind: good`은 같은 target이라도 별도 그룹(유지 패턴)으로 둔다.

## 3. 진단

그룹마다:

- **반복 vs 1회성** — 같은 target에 2건 이상, 또는 다른 repo에서 같은 증상이면 반복.
- **원인 파일 특정** — 어느 SKILL.md 몇 번 절, CLAUDE.md·rules 어느 항목, 어느 훅 스크립트인지 실제로 열어 확인한다. 열지 않고 추정만으로 적지 않는다.
- 하네스 표준 경로(여기서 찾는다, 사용자별 경로를 하드코딩하지 않는다):
  `~/.claude/CLAUDE.md` · `~/.claude/rules/` · `~/.claude/skills/` · `~/.agents/skills/` · `~/.cursor/skills/` · `~/.codex/AGENTS.md` ·
  프로젝트 `CLAUDE.md` / `AGENTS.md` / `.cursor/rules/` / `.claude/skills/`(프로젝트 스코프는 기록의 `cwd` 기준).
- `tool:`·`env`·`model`은 파일이 아니라 도구·환경·판단 문제다. 룰이나 스킬에 가드를 넣어 막을 수 있는지까지만 본다.

## 4. 제안

- 그룹당 **수정안 1개**, 실제 diff 수준으로: 파일 경로 · 바꿀 줄(전) · 바뀐 줄(후). "~를 개선한다" 같은 추상 제안 금지.
- 근거는 §1의 원문·context와 §3에서 연 파일의 실제 내용. 근거 없는 제안은 내지 않는다 — 원인 파일을 못 찾았으면 "원인 파일 미특정, 보류 권장"으로 적는다.
- `kind: good` 그룹은 "유지 패턴"으로 — 어느 룰·스킬 덕분이었는지 특정하고, CLAUDE.md·AGENTS.md·메모리·해당 스킬에 한 줄 추가하는 diff를 낸다.
- diff가 여러 파일에 걸치면 가장 근본 파일 하나로 줄인다. 나머지는 "후속"으로만 적는다.

## 5. 승인 — 그룹 하나씩

그룹 하나를 보여주고 답을 받은 뒤에야 다음 그룹으로 간다. 여러 그룹을 한 번에 나열하고 한꺼번에 답받지 않는다.

보여줄 것: 그룹 키 · 건수(id 목록) · 반복/1회성 · 원인 파일 · diff(전/후). 그 아래 선택지:

```
1 반영 — 위 diff를 지금 적용하고 기록을 processed로 옮긴다
2 스킵 — 적용하지 않고 이유를 기록해 processed로 옮긴다
3 보류 — 아무것도 하지 않고 inbox에 남긴다
```

- 질문 도구가 있으면 쓰고 없으면 대화로 묻는다. 추천이 있으면 1번 줄 끝에 "(추천)"과 이유 한 구절.
- **답을 받기 전에는 다음 그룹으로 넘어가지 않고, 어떤 파일도 바꾸지 않는다.**
- 1이면 즉시 §6을 수행하고 결과를 보여준 뒤 다음 그룹. 2·3도 §6의 해당 절차 후 다음 그룹.
- 사용자가 "다 스킵" · "나머지 보류"라고 하면 남은 그룹 전부에 그 답을 적용한다.

## 6. 반영

**1 반영**
1. diff를 그 파일에 적용한다.
2. 적용 결과 확인 — 바뀐 부분을 파일에서 다시 읽어 전/후를 재출력한다. 의도와 다르면 되돌리고 3 보류로 처리한다.
3. 그룹의 md마다 frontmatter(둘째 `---` 앞)에 `resolution: <한 줄>`을 추가한다(예: `resolution: rule:code-review §심각도에 MINOR 생략 금지 1줄 추가`).
4. `mkdir -p $AP_HOME/processed/YYYY-MM`(기록의 `ts` 연월) 후 `mv -n inbox/<id>.md processed/YYYY-MM/`. 같은 이름이 이미 있으면 `<id>_2.md`로 옮긴다(덮어쓰기 금지).
5. 적용에 실패하면(파일 없음·권한·충돌) **이동하지 않고** 3 보류로 되돌린 뒤 사유를 사용자에게 알린다.

**2 스킵** — 파일은 손대지 않는다. `resolution: 스킵 — <사용자가 말한 이유>`를 추가하고 위 4와 같이 옮긴다.

**3 보류** — 아무것도 하지 않는다. inbox에 남고 `resolution:`도 쓰지 않는다. 다음 리뷰에 다시 나온다.

md 갱신은 `$AP_HOME` 안에서만 한다. 하네스 파일 수정은 승인받은 diff 그 파일뿐이다.

## 7. 보고

리뷰가 끝나면 두 줄:

```
바뀐 파일: ~/.claude/rules/code-review.md, ~/.claude/skills/br-briefing/SKILL.md
처리 3 · 스킵 1 · 보류 2 · 대기 중 1
```

**커밋·push 하지 않는다.** 바뀐 파일을 커밋할지는 사용자가 정한다.

## 금지

- 서브에이전트·헤드리스 위임 — 대화 컨텍스트와 승인 흐름이 끊긴다.
- 승인 없는 반영, 그룹을 건너뛰고 다음 그룹 진행, 여러 그룹 일괄 승인 요구.
- `$AP_HOME`과 승인된 하네스 파일 외의 쓰기, 사용자 홈 밖 쓰기, 커밋·push.
- 원문·context에 있는 비밀값(토큰·경로·에러 본문)을 다른 파일로 옮겨 적기.
