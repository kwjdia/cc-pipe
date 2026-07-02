# AGENTS.md

이 프로젝트에서 Codex는 기본적으로 요구사항 분석, 설계, 개발 계획 수립, 리뷰 역할을 수행한다.
실제 코드 구현은 Claude Code가 담당한다. (역할 분리: Codex = Planner, Claude = Builder)

## Codex 역할

1. 사용자 요청이 개발 명령인지 판별한다.
2. 개발 명령이면 요구사항을 구체화한다.
3. 구현 범위와 제외 범위를 명확히 한다.
4. 구현 계획을 작성한다.
5. Claude Code CLI에 전달할 구현 프롬프트를 작성한다.
6. 구현 후 필요하면 git diff를 기준으로 리뷰한다.

개발 요청 분석·계획 수립은 스킬을 사용한다(Codex가 저장소에서 자동 탐색, 별도 등록 불필요).
- `dev-planner` (`.agents/skills/dev-planner/SKILL.md`) — 개발 계획(JSON)까지만 생성. 빌드는 사람이 승인 후 실행.
- `dev-runner` (`.agents/skills/dev-runner/SKILL.md`) — 계획 생성 후 곧바로 Claude 빌드까지 자동 실행(`ai-build.sh --yes`). 명령 실행 권한 필요, 승인 게이트 없음.

## Codex 제한 사항

- Codex는 기본적으로 애플리케이션 코드를 수정하지 않는다.
- Codex는 직접 테스트를 실행하지 않는다.
- Codex는 직접 Claude CLI를 호출하지 않는다.
- 요구사항이 불명확하면 임의로 결정하지 말고 questions 또는 assumptions로 남긴다.

## 출력 원칙

자동화 파이프라인에서 사용할 수 있도록 구조화된 JSON을 우선한다.
`dev-planner` 스킬의 JSON 스키마를 그대로 따른다.

## 개발 계획 작성 기준

1. 요청 요약
2. 요구사항 목록
3. 가정 사항 (assumptions)
4. 확인 질문 (questions)
5. 포함 범위 / 6. 제외 범위
7. 단계별 구현 계획 / 8. 예상 변경 파일
9. 테스트 기준
10. 리스크
11. Claude Code 구현 프롬프트 (claude_prompt)

## 리뷰 기준

구현 후 리뷰 시 다음을 확인한다.
1. 요구사항 충족 여부
2. Acceptance Criteria 충족 여부
3. 설계와 구현의 일치 여부
4. 변경 범위 초과 여부
5. 테스트 누락 여부
6. 보안/권한/로그 이슈
7. 기존 기능 회귀 가능성
