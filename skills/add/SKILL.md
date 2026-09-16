---
name: add
description: 짜증·좋은점 한 줄 캡처 — $add <한마디> · $add +<좋은점>. 훅이 가로채 저장하므로 이 스킬 본문이 로드됐다면 훅 미동작이다
argument-hint: <한마디> | +<좋은점>
disable-model-invocation: true
---
# add — 짜증·좋은점 한 줄 캡처

`$add <한마디>`(Claude는 `/add`·`/annoying-point:add`·`$add` 셋 다 됨 — 다른 플러그인이 `add`를 정의하면 `/annoying-point:add`로)는 캡처 훅(`scripts/ap-capture.sh`)이 가로채 저장하고 block한다. 이 본문이 AI에게 도달했다면 훅이 동작하지 않은 것이다 — 원인은 훅 미등록 또는 `jq` 없음.

사용자에게 다음만 안내하고 다른 작업은 하지 않는다:
1. 원문을 그대로 다시 보여준다: `$ARGUMENTS`
2. `jq`가 없으면 `brew install jq`, 있으면 repo에서 `bash install.sh`를 재실행해 훅 등록을 확인하라고 안내한다 (Claude는 플러그인 훅 등록 상태 `/hooks`).
