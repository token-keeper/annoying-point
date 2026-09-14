---
description: 짜증·좋은점을 한 줄로 남긴다 — /ap <한마디> · /ap +<좋은점>. 훅이 가로채 저장하므로 AI 턴을 쓰지 않는다
argument-hint: <한마디> | +<좋은점>
disable-model-invocation: true
---
Claude에서는 `/annoying-point:ap <한마디>` 또는 플레인 텍스트 `$ap <한마디>`로 입력한다 (bare `/ap`는 미등록 커맨드라 동작하지 않는다).

이 명령은 `UserPromptExpansion` 훅(`scripts/ap-capture.sh`)이 가로채 처리해야 한다. 이 본문이 AI에게 도달했다면 훅이 동작하지 않은 것이다 — 원인은 훅 미등록 또는 `jq` 없음.

사용자에게 다음만 안내하고 다른 작업은 하지 않는다:
1. 원문을 그대로 다시 보여준다: `$ARGUMENTS`
2. `jq`가 없으면 `brew install jq`, 있으면 플러그인 훅 등록 상태(`/hooks`)를 확인하라고 안내한다.
