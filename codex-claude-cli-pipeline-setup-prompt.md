# Codex + Claude CLI 개발 파이프라인 셋팅 프롬프트

## 목적

이 프롬프트는 현재 프로젝트에 **Codex로 사용자 개발 요청을 분석하고, Claude CLI로 실제 구현을 수행하는 단순 로컬 파이프라인**을 셋팅하기 위한 실행 지시서입니다.

최종 목표는 다음 명령 하나로 개발 요청을 처리하는 것입니다.

```bash
./scripts/ai-dev.sh "사용자 개발 요청"
```

동작 흐름은 아래와 같습니다.

```text
사용자 프롬프트 입력
→ Codex가 개발 명령인지 판별
→ Codex가 요구사항 구체화 및 개발 플랜 생성
→ Codex가 Claude CLI용 구현 프롬프트 생성
→ 사람이 실행 여부 승인
→ Claude CLI가 실제 코드 구현
→ 구현 결과와 로그 저장
→ 사람이 git diff 확인
```

---

## Codex에게 요청할 작업

너는 이 프로젝트의 로컬 AI 개발 파이프라인 셋업 담당자다.

아래 요구사항에 따라 필요한 파일과 디렉터리를 생성해라.

중요한 원칙:

1. 기존 애플리케이션 코드는 수정하지 마라.
2. 이번 작업은 AI 개발 파이프라인 셋팅 파일만 추가한다.
3. 이미 동일 파일이 있으면 내용을 확인하고, 기존 프로젝트 규칙을 해치지 않는 방향으로 병합하거나 보완한다.
4. 실행 가능한 shell script를 작성한다.
5. Codex는 Planner 역할, Claude CLI는 Builder 역할로 분리한다.
6. Claude CLI 자동 호출 전에는 반드시 사용자 승인 게이트를 둔다.
7. 생성 후 변경 파일 목록과 사용 방법을 요약해라.

---

## 생성할 최종 파일 구조

프로젝트 루트 기준으로 아래 구조를 생성해라.

```text
project-root/
  AGENTS.md
  CLAUDE.md

  .agents/
    skills/
      dev-planner/
        SKILL.md

  scripts/
    ai-dev.sh

  docs/
    ai/
      runs/
        .gitkeep
```

---

## 1. `.agents/skills/dev-planner/SKILL.md` 생성

다음 파일을 생성해라.

```text
.agents/skills/dev-planner/SKILL.md
```

내용은 아래 기준을 따르되, 프로젝트 특성에 맞게 필요한 부분은 보완해도 된다.

```md
---
name: dev-planner
description: 사용자의 자연어 요청이 소프트웨어 개발 명령인지 판별하고, 개발 요청이면 요구사항을 구체화한 뒤 Claude Code CLI가 구현할 수 있는 개발 계획과 구현 프롬프트를 생성한다. 코드 수정은 하지 않는다.
---

# dev-planner Skill

너는 이 프로젝트의 개발 요청 분석가이자 구현 계획 수립자다.

## 목적

사용자 프롬프트를 받아서 다음을 수행한다.

1. 개발 명령인지 판별한다.
2. 개발 명령이면 요구사항을 구체화한다.
3. 구현 범위를 정의한다.
4. 작업 단위를 나눈다.
5. 테스트 기준을 작성한다.
6. Claude Code CLI에 전달할 구현 프롬프트를 생성한다.

## 절대 금지

- 코드를 수정하지 않는다.
- 애플리케이션 파일을 직접 변경하지 않는다.
- 테스트를 실행하지 않는다.
- Claude CLI를 직접 호출하지 않는다.
- 요구사항이 불명확한 경우 임의로 확정하지 말고 assumption과 question으로 분리한다.

## 입력

사용자의 원본 프롬프트.

## 출력 형식

반드시 아래 JSON 형식으로만 출력한다.

JSON 앞뒤에 설명 문장, Markdown 코드블록, 주석을 붙이지 마라.

```json
{
  "is_development_request": true,
  "request_summary": "",
  "requirements": [],
  "assumptions": [],
  "questions": [],
  "scope": {
    "included": [],
    "excluded": []
  },
  "development_plan": [
    {
      "step": 1,
      "title": "",
      "description": "",
      "expected_files": [],
      "test_criteria": []
    }
  ],
  "acceptance_criteria": [],
  "risk_notes": [],
  "claude_prompt": ""
}
```

## 개발 요청이 아닌 경우

개발 요청이 아니면 다음 JSON을 출력한다.

```json
{
  "is_development_request": false,
  "answer": "사용자에게 직접 응답할 내용"
}
```

## 개발 명령 판별 기준

다음에 해당하면 개발 명령으로 판단한다.

- 기능 추가 요청
- 버그 수정 요청
- 리팩터링 요청
- 테스트 추가 요청
- 코드 구조 변경 요청
- API, UI, DB, 배치, 설정 변경 요청
- 성능, 보안, 로깅, 예외 처리 개선 요청

다음에 해당하면 일반 질문으로 판단한다.

- 개념 설명 요청
- 단순 질의응답
- 코드 수정 없이 의견만 묻는 요청
- 문서 번역 또는 요약 요청
- 개발 실행이 필요 없는 검토 요청

단, 사용자가 “수정해줘”, “구현해줘”, “추가해줘”, “반영해줘”, “고쳐줘”라고 요청하면 개발 명령일 가능성이 높다.

## Claude Prompt 작성 규칙

`claude_prompt`에는 Claude Code가 바로 실행할 수 있는 명령형 프롬프트를 작성한다.

반드시 포함할 것:

1. 구현 목표
2. 변경 범위
3. 제외 범위
4. 구현 순서
5. 테스트 기준
6. 금지 사항
7. 구현 후 요약 형식

Claude Code에게 다음을 강제한다.

- 먼저 `git status` 확인
- 변경 전 관련 파일 탐색
- 승인된 범위만 구현
- 불필요한 리팩터링 금지
- Secret, API Key, Token 하드코딩 금지
- 가능한 경우 테스트 실행
- 변경 파일 목록과 테스트 결과 출력

## 보안/품질 기준

개발 계획에는 다음 항목을 반드시 고려한다.

- 인증/인가 영향
- 개인정보/민감정보 노출 가능성
- 로그 출력 영향
- 외부 API 영향
- DB schema 변경 여부
- 기존 public API contract 영향
- 테스트 누락 가능성
- 롤백 가능성
```

---

## 2. `AGENTS.md` 생성 또는 보완

프로젝트 루트에 다음 파일을 생성하거나 기존 파일이 있으면 보완해라.

```text
AGENTS.md
```

내용은 아래 기준을 따른다.

```md
# AGENTS.md

이 프로젝트에서 Codex는 기본적으로 요구사항 분석, 설계, 개발 계획 수립, 리뷰 역할을 수행한다.

## Codex 역할

Codex는 다음을 수행한다.

1. 사용자 요청이 개발 명령인지 판별한다.
2. 개발 명령이면 요구사항을 구체화한다.
3. 구현 범위와 제외 범위를 명확히 한다.
4. 구현 계획을 작성한다.
5. Claude Code CLI에 전달할 구현 프롬프트를 작성한다.
6. 구현 후 필요하면 git diff를 기준으로 리뷰한다.

## Codex 제한 사항

- Codex는 기본적으로 애플리케이션 코드를 수정하지 않는다.
- Codex는 직접 테스트를 실행하지 않는다.
- Codex는 직접 Claude CLI를 호출하지 않는다.
- 실제 구현은 Claude Code가 담당한다.
- 요구사항이 불명확하면 임의로 결정하지 말고 질문 또는 assumption으로 남긴다.

## 출력 원칙

자동화 파이프라인에서 사용할 수 있도록 구조화된 JSON 또는 Markdown을 우선한다.

## 개발 계획 작성 기준

개발 계획에는 다음을 포함한다.

1. 요청 요약
2. 요구사항 목록
3. 가정 사항
4. 확인 질문
5. 포함 범위
6. 제외 범위
7. 단계별 구현 계획
8. 예상 변경 파일
9. 테스트 기준
10. 리스크
11. Claude Code 구현 프롬프트

## 리뷰 기준

구현 후 리뷰 시 다음을 확인한다.

1. 요구사항 충족 여부
2. Acceptance Criteria 충족 여부
3. 설계와 구현의 일치 여부
4. 변경 범위 초과 여부
5. 테스트 누락 여부
6. 보안/권한/로그 이슈
7. 기존 기능 회귀 가능성
```

---

## 3. `CLAUDE.md` 생성 또는 보완

프로젝트 루트에 다음 파일을 생성하거나 기존 파일이 있으면 보완해라.

```text
CLAUDE.md
```

내용은 아래 기준을 따른다.

```md
# CLAUDE.md

이 프로젝트에서 Claude Code는 Codex가 생성한 개발 계획과 구현 프롬프트를 기준으로 실제 코드를 구현한다.

## Claude Code 역할

Claude Code는 다음을 수행한다.

1. Codex가 생성한 개발 계획을 읽는다.
2. 구현 전 `git status`를 확인한다.
3. 관련 파일을 탐색한다.
4. 승인된 범위 안에서만 코드를 수정한다.
5. 필요한 테스트를 추가하거나 수정한다.
6. 가능한 경우 테스트를 실행한다.
7. 변경 결과를 요약한다.

## 구현 전 필수 확인

1. 먼저 `git status`를 확인한다.
2. 기존 변경 사항이 있으면 주의한다.
3. 관련 파일을 탐색한 뒤 구현한다.
4. 요청 범위 밖의 리팩터링은 하지 않는다.

## 구현 원칙

- Codex가 생성한 개발 계획을 따른다.
- 불필요한 dependency를 추가하지 않는다.
- Secret, API Key, Token을 하드코딩하지 않는다.
- 기존 코드 스타일과 아키텍처를 따른다.
- 핵심 로직 변경 시 테스트를 추가하거나 수정한다.
- 가능한 경우 테스트를 실행한다.
- 테스트 실행이 불가능하면 이유를 명확히 남긴다.

## 금지 사항

- 승인된 범위를 벗어난 대규모 리팩터링 금지
- 불필요한 신규 패키지 추가 금지
- public API contract 임의 변경 금지
- DB schema 임의 변경 금지
- 인증/인가 로직 임의 변경 금지
- 내부 에러 메시지 또는 민감정보 로그 출력 금지

## 구현 후 출력

다음 형식으로 결과를 요약한다.

1. 변경 파일 목록
2. 구현 요약
3. 실행한 테스트 명령
4. 테스트 결과
5. 설계와 달라진 점
6. 남은 리스크
7. 사람이 확인해야 할 부분
```

---

## 4. `scripts/ai-dev.sh` 생성

다음 파일을 생성해라.

```text
scripts/ai-dev.sh
```

내용은 아래 기준으로 작성한다.

중요:

- Bash script로 작성한다.
- 실행 중 오류 발생 시 중단되도록 `set -euo pipefail`을 사용한다.
- 사용자 프롬프트를 인자로 받는다.
- 실행 로그는 `docs/ai/runs/{timestamp}`에 저장한다.
- Codex는 read-only sandbox로 실행한다.
- Codex 결과는 JSON으로 저장한다.
- JSON 파싱에 실패하면 원본 결과를 보여주고 중단한다.
- 개발 요청이 아니면 Claude를 호출하지 않는다.
- 개발 요청이면 요약을 보여주고 사용자에게 y/N 승인을 받는다.
- 승인한 경우에만 Claude CLI를 호출한다.
- Claude 실행 결과를 `claude-result.md`에 저장한다.
- 마지막에 `git diff` 확인 명령을 안내한다.

스크립트 내용:

```bash
#!/usr/bin/env bash
set -euo pipefail

USER_PROMPT="${*:-}"

if [ -z "$USER_PROMPT" ]; then
  echo "사용법: ./scripts/ai-dev.sh \"개발 요청 내용\""
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "오류: codex CLI를 찾을 수 없습니다."
  echo "먼저 Codex CLI가 설치되어 있고 PATH에 등록되어 있는지 확인하세요."
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "오류: claude CLI를 찾을 수 없습니다."
  echo "먼저 Claude Code CLI가 설치되어 있고 PATH에 등록되어 있는지 확인하세요."
  exit 1
fi

if ! command -v python >/dev/null 2>&1; then
  echo "오류: python을 찾을 수 없습니다."
  echo "JSON 파싱을 위해 python이 필요합니다."
  exit 1
fi

RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="docs/ai/runs/${RUN_ID}"

mkdir -p "$RUN_DIR"

echo "$USER_PROMPT" > "${RUN_DIR}/user-prompt.txt"

echo "==> Codex로 개발 요청 분석 및 플랜 생성"

CODEX_PROMPT=$(cat <<EOF
\$dev-planner

다음 사용자 요청을 분석해줘.

사용자 요청:
${USER_PROMPT}

규칙:
- 코드는 수정하지 마.
- 개발 요청이면 요구사항 구체화, 개발 계획, Claude Code 구현 프롬프트를 JSON으로 출력해.
- 개발 요청이 아니면 is_development_request=false로 출력해.
- JSON 앞뒤에 설명 문장이나 Markdown 코드블록을 붙이지 마.
EOF
)

set +e
codex exec --sandbox read-only "$CODEX_PROMPT" > "${RUN_DIR}/codex-plan.raw"
CODEX_EXIT_CODE=$?
set -e

if [ "$CODEX_EXIT_CODE" -ne 0 ]; then
  echo "오류: Codex 실행에 실패했습니다."
  echo "원본 출력 파일: ${RUN_DIR}/codex-plan.raw"
  exit "$CODEX_EXIT_CODE"
fi

python - <<EOF
import json
from pathlib import Path
import re
import sys

run_dir = Path("${RUN_DIR}")
raw_path = run_dir / "codex-plan.raw"
json_path = run_dir / "codex-plan.json"

raw = raw_path.read_text(encoding="utf-8").strip()

def extract_json(text: str) -> str:
    if text.startswith("{") and text.endswith("}"):
        return text

    fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.S)
    if fenced:
        return fenced.group(1)

    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        return text[start:end+1]

    return text

candidate = extract_json(raw)

try:
    data = json.loads(candidate)
except Exception as e:
    print("오류: Codex 결과를 JSON으로 파싱하지 못했습니다.")
    print(f"원본 파일: {raw_path}")
    print(f"에러: {e}")
    sys.exit(1)

json_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
EOF

echo "==> Codex 결과 저장: ${RUN_DIR}/codex-plan.json"

IS_DEV=$(python - <<EOF
import json
from pathlib import Path

path = Path("${RUN_DIR}/codex-plan.json")
data = json.loads(path.read_text(encoding="utf-8"))
print(str(data.get("is_development_request", False)).lower())
EOF
)

if [ "$IS_DEV" != "true" ]; then
  echo "==> 개발 요청이 아닙니다. Codex 응답:"
  python - <<EOF
import json
from pathlib import Path

data = json.loads(Path("${RUN_DIR}/codex-plan.json").read_text(encoding="utf-8"))
print(data.get("answer", "응답 없음"))
EOF
  exit 0
fi

echo
echo "==> 개발 요청으로 판단됨"
echo
echo "===== Codex 개발 플랜 요약 ====="

python - <<EOF
import json
from pathlib import Path

data = json.loads(Path("${RUN_DIR}/codex-plan.json").read_text(encoding="utf-8"))

print("요약:", data.get("request_summary", ""))
print()

print("요구사항:")
for item in data.get("requirements", []):
    print("-", item)

print()
print("가정 사항:")
for item in data.get("assumptions", []):
    print("-", item)

print()
print("확인 질문:")
for item in data.get("questions", []):
    print("-", item)

print()
print("작업 계획:")
for step in data.get("development_plan", []):
    print(f"- {step.get('step')}. {step.get('title')}: {step.get('description')}")

print()
print("리스크:")
for item in data.get("risk_notes", []):
    print("-", item)
EOF

echo
read -r -p "이 플랜으로 Claude Code 구현을 진행할까요? [y/N] " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "중단했습니다."
  echo "Codex 결과는 다음 위치에 저장되어 있습니다:"
  echo "  ${RUN_DIR}/codex-plan.json"
  exit 0
fi

python - <<EOF
import json
from pathlib import Path

run_dir = Path("${RUN_DIR}")
data = json.loads((run_dir / "codex-plan.json").read_text(encoding="utf-8"))

claude_prompt = data.get("claude_prompt", "")

if not claude_prompt:
    raise SystemExit("오류: claude_prompt가 비어 있습니다.")

full_prompt = f"""
너는 이 프로젝트의 구현 담당 Claude Code다.

아래 Codex 개발 계획을 기준으로 구현해라.

[Codex 개발 계획]
{json.dumps(data, ensure_ascii=False, indent=2)}

[구현 요청]
{claude_prompt}

[추가 규칙]
1. 먼저 git status를 확인해라.
2. 관련 파일을 탐색한 뒤 구현해라.
3. 요청 범위를 초과하는 리팩터링은 하지 마라.
4. 불필요한 dependency를 추가하지 마라.
5. Secret, Token, API Key를 코드에 하드코딩하지 마라.
6. 가능한 경우 테스트를 실행해라.
7. 테스트 실행이 불가능하면 이유를 남겨라.
8. 최종 응답에 변경 파일, 구현 요약, 테스트 결과, 남은 리스크를 포함해라.
"""

(run_dir / "claude-prompt.md").write_text(full_prompt, encoding="utf-8")
EOF

echo
echo "==> Claude Code 구현 시작"
echo "==> Claude 프롬프트: ${RUN_DIR}/claude-prompt.md"

set +e
claude -p "$(cat "${RUN_DIR}/claude-prompt.md")" \
  --allowedTools "Read,Edit,Bash" \
  --append-system-prompt-file CLAUDE.md \
  | tee "${RUN_DIR}/claude-result.md"
CLAUDE_EXIT_CODE=${PIPESTATUS[0]}
set -e

if [ "$CLAUDE_EXIT_CODE" -ne 0 ]; then
  echo
  echo "주의: Claude Code 실행이 실패했거나 중단되었습니다."
  echo "결과 파일을 확인하세요:"
  echo "  ${RUN_DIR}/claude-result.md"
  exit "$CLAUDE_EXIT_CODE"
fi

echo
echo "==> 완료"
echo "결과 디렉터리: ${RUN_DIR}"
echo
echo "다음 명령으로 변경 사항을 확인하세요:"
echo "  git diff --stat"
echo "  git diff"
echo
echo "문제가 없으면 직접 테스트 후 commit 하세요."
```

---

## 5. `docs/ai/runs/.gitkeep` 생성

다음 파일을 생성해라.

```text
docs/ai/runs/.gitkeep
```

빈 파일이면 된다.

---

## 6. 실행 권한 부여

파일 생성 후 다음 명령을 실행해라.

```bash
chmod +x scripts/ai-dev.sh
```

---

## 7. 셋팅 후 검증

셋팅이 끝나면 다음을 확인해라.

```bash
ls -la .agents/skills/dev-planner/SKILL.md
ls -la AGENTS.md
ls -la CLAUDE.md
ls -la scripts/ai-dev.sh
ls -la docs/ai/runs/.gitkeep
```

그리고 아래 명령으로 사용법 출력이 정상인지 확인해라.

```bash
./scripts/ai-dev.sh
```

인자가 없으면 다음과 비슷하게 출력되어야 한다.

```text
사용법: ./scripts/ai-dev.sh "개발 요청 내용"
```

---

## 8. 실제 사용 예시

셋팅이 완료되면 아래처럼 실행한다.

```bash
./scripts/ai-dev.sh "로그인 실패 시 실패 횟수를 증가시키고, 5회 이상 실패하면 계정을 잠금 처리하도록 수정해줘"
```

예상 흐름:

```text
1. Codex가 사용자 요청을 분석한다.
2. 개발 요청으로 판단한다.
3. 요구사항, 가정, 질문, 작업 계획을 출력한다.
4. 사용자에게 Claude Code 실행 여부를 묻는다.
5. y 입력 시 Claude Code가 구현을 시작한다.
6. 결과가 docs/ai/runs/{timestamp}/ 에 저장된다.
7. 사용자는 git diff로 변경사항을 확인한다.
```

---

## 9. 산출물 저장 위치

각 실행 결과는 아래에 저장된다.

```text
docs/ai/runs/{timestamp}/
  user-prompt.txt
  codex-plan.raw
  codex-plan.json
  claude-prompt.md
  claude-result.md
```

각 파일 의미:

```text
user-prompt.txt      사용자가 입력한 원본 개발 요청
codex-plan.raw       Codex 원본 출력
codex-plan.json      파싱된 Codex 개발 계획
claude-prompt.md     Claude CLI에 전달한 최종 구현 프롬프트
claude-result.md     Claude CLI 실행 결과
```

---

## 10. 완료 후 최종 응답 형식

작업을 완료한 뒤 사용자에게 다음 형식으로 보고해라.

```md
## 셋팅 완료

다음 파일을 생성/수정했습니다.

- `.agents/skills/dev-planner/SKILL.md`
- `AGENTS.md`
- `CLAUDE.md`
- `scripts/ai-dev.sh`
- `docs/ai/runs/.gitkeep`

## 사용 방법

```bash
./scripts/ai-dev.sh "개발 요청 내용"
```

## 동작 흐름

```text
사용자 요청
→ Codex 분석/계획
→ 사용자 승인
→ Claude CLI 구현
→ 결과 저장
→ git diff 확인
```

## 다음 확인 사항

1. Codex CLI 로그인 상태 확인
2. Claude CLI 로그인 상태 확인
3. `./scripts/ai-dev.sh` 실행 권한 확인
4. 작은 개발 요청으로 PoC 실행
```

---

## 11. 주의 사항

이 파이프라인은 단순 PoC용이다.

초기에는 다음 원칙을 지켜라.

1. 대규모 리팩터링 작업에 바로 사용하지 않는다.
2. 인증/인가/결제/DB schema 변경 작업에는 바로 적용하지 않는다.
3. 처음에는 작은 validation, 메시지 수정, 테스트 보강 작업으로 검증한다.
4. Claude Code 실행 전 항상 Codex 계획을 사람이 확인한다.
5. Claude Code 실행 후 항상 `git diff`를 사람이 확인한다.
6. 자동 commit 또는 자동 merge는 하지 않는다.
