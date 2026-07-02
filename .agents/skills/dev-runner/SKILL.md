---
name: dev-runner
description: 사용자의 개발 요청을 분석해 개발 계획을 생성하고, 곧바로 Claude Code CLI 빌드까지 자동으로 이어서 실행한다(계획→구현 원스텝). Codex 앱에서 명령 실행 권한이 있을 때 사용한다. 계획만 필요하면 dev-planner 를 사용한다.
---

# dev-runner Skill

너는 이 프로젝트의 개발 요청 분석가이자 **엔드투엔드 실행기**다.
`dev-planner`가 개발 계획까지만 만드는 것과 달리, 너는 계획을 만든 뒤 **Claude Code 빌드까지 자동으로 실행**한다.

## 전제와 주의

- 이 스킬은 셸 명령을 실행하고 파일을 쓴다(read-only 샌드박스에서는 동작하지 않는다).
- 빌드는 **사람 승인 게이트 없이 자동**으로 진행된다(`ai-build.sh --yes`). 실제 코드가 변경될 수 있다.
- 너(Codex)는 계획만 생성한다. 실제 코드 구현은 `ai-build.sh`가 호출하는 **Claude**가 담당한다(역할 분리 유지).
- 계획만 원하거나 사람 승인을 거치고 싶으면 이 스킬 대신 `dev-planner`를 사용한다.

## 절대 금지

- 애플리케이션 코드를 직접 수정하지 않는다(구현은 Claude가 한다).
- 계획을 건너뛰고 곧바로 빌드하지 않는다. 반드시 계획(JSON)을 먼저 생성·저장한다.
- 요구사항이 불명확해도 임의로 확정하지 말고 `assumptions`/`questions`로 분리한다.

## 절차

### 1) 요청 분석 (계획 생성)

`dev-planner`와 동일한 JSON 계약을 따른다. 개발 요청이면 아래 스키마로 계획을 구성한다.

```json
{
  "is_development_request": true,
  "request_summary": "",
  "requirements": [],
  "assumptions": [],
  "questions": [],
  "scope": { "included": [], "excluded": [] },
  "development_plan": [
    { "step": 1, "title": "", "description": "", "expected_files": [], "test_criteria": [] }
  ],
  "acceptance_criteria": [],
  "risk_notes": [],
  "claude_prompt": ""
}
```

- `claude_prompt`에는 구현 목표·변경 범위·제외 범위·구현 순서·테스트 기준·금지 사항·구현 후 요약 형식을 담는다.
- 비대화형(`claude -p`)은 되물을 수 없으므로, `questions`가 남으면 `assumptions` 기준으로 진행 가능하도록 계획을 구성한다.
- `request_summary`, `development_plan`(1개 이상), `claude_prompt`는 필수다(검증에서 누락 시 빌드가 중단된다).

개발 요청이 **아니면** 아래를 출력하고 여기서 종료한다(빌드하지 않는다).

```json
{ "is_development_request": false, "answer": "사용자에게 직접 응답할 내용" }
```

### 2) 계획 저장

실행 디렉터리를 만들고 원본 요청과 계획 JSON을 저장한다.

```sh
RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="docs/ai/runs/${RUN_ID}"
mkdir -p "$RUN_DIR"
```

- 사용자 원본 요청 → `"$RUN_DIR/user-prompt.txt"`
- 1)에서 만든 계획 JSON(순수 JSON, 위 스키마) → `"$RUN_DIR/codex-plan.json"`

### 3) Claude 빌드 자동 실행

계획을 저장한 실행 디렉터리로 빌드를 무프롬프트 실행한다.

```sh
sh ./scripts/ai-build.sh "$RUN_DIR" --yes
```

- `ai-build.sh`가 계획 유효성 검증 → `claude-prompt.md` 조립 → `claude -p ... --allowedTools "Read,Edit,Write,Bash"` 실행 → 결과를 `claude-result.md`에 저장한다.
- 스크립트는 bash 기반이다. Windows에서는 Git Bash/WSL 환경에서 실행되어야 한다.

### 4) 보고

- 생성한 `RUN_DIR` 경로.
- Claude 실행 결과 요약(`claude-result.md`)과 변경된 파일.
- 사람이 확인할 것: `git diff --stat && git diff` 로 변경을 검토한 뒤 직접 commit(자동 commit 없음).
- 계획에 `questions`가 남아 있었다면 어떤 가정으로 진행했는지 명확히 표기한다.

## 보안/품질 기준

계획 수립 시 인증/인가 영향, 개인정보 노출, 로그 출력, 외부 API, DB schema 변경, public API contract, 테스트 누락, 롤백 가능성을 고려한다. 파괴적·비가역적 작업(스키마 변경, 대량 삭제 등)은 `scope.excluded`로 빼고 `risk_notes`에 남긴다.
