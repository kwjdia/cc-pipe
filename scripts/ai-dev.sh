#!/usr/bin/env bash
#
# ai-dev.sh — Codex(Planner) → 사람 승인 → Claude(Builder) 로컬 파이프라인 (CLI 진입점)
#
#   사용법: ./scripts/ai-dev.sh "개발 요청 내용"
#
# 흐름:
#   1) Codex가 요청을 분석해 개발 계획(JSON)을 생성 (read-only)
#   2) JSON 파싱 + 스키마 검증
#   3) 개발 요청이 아니면 answer 출력 후 종료
#   4) 개발 요청이면 ai-build.sh 로 위임 (요약 → 승인 게이트 → Claude 구현)
#
set -euo pipefail

USER_PROMPT="${*:-}"

if [ -z "$USER_PROMPT" ]; then
  echo "사용법: ./scripts/ai-dev.sh \"개발 요청 내용\"" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# ---- cc-pipe 자동 업데이트 (설치본에서만 동작) --------------------------------
# .cc-pipe/update.sh 가 있으면(=타깃 프로젝트에 설치된 경우) 실행 시작 시 원격
# 최신 여부를 확인하고 필요하면 재설치한다. fail-open(오프라인/실패 시 그냥 진행).
# cc-pipe 소스 저장소에는 .cc-pipe/ 가 없으므로 자기 자신은 자동 업데이트되지 않는다.
# CC_PIPE_NO_UPDATE=1 로 비활성화(재실행 루프 방지 및 오프라인/CI 용).
if [ -z "${CC_PIPE_NO_UPDATE:-}" ] && [ -f "$REPO_ROOT/.cc-pipe/update.sh" ]; then
  set +e
  sh "$REPO_ROOT/.cc-pipe/update.sh" --auto
  UPD_EXIT=$?
  set -e
  if [ "$UPD_EXIT" -eq 10 ]; then
    echo "==> cc-pipe 업데이트 적용됨 — 최신 버전으로 재실행합니다."
    exec env CC_PIPE_NO_UPDATE=1 "$0" "$@"
  fi
fi

# ---- 의존성 확인 --------------------------------------------------------------
if ! command -v codex >/dev/null 2>&1; then
  echo "오류: codex CLI를 찾을 수 없습니다. Codex CLI 설치 및 PATH 등록을 확인하세요." >&2
  exit 1
fi
if ! command -v claude >/dev/null 2>&1; then
  echo "오류: claude CLI를 찾을 수 없습니다. Claude Code CLI 설치 및 PATH 등록을 확인하세요." >&2
  exit 1
fi
# 동작하는 Python 3 선택 (Windows의 Microsoft Store python3 스텁 회피)
PYTHON=""
for _py in python3 python py; do
  if command -v "$_py" >/dev/null 2>&1 \
     && "$_py" -c 'import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1; then
    PYTHON="$_py"
    break
  fi
done
if [ -z "$PYTHON" ]; then
  echo "오류: 동작하는 python 3 을 찾을 수 없습니다. JSON 파싱에 필요합니다." >&2
  exit 1
fi
# Python 입출력을 UTF-8로 강제 (Windows 로케일 인코딩으로 인한 한글 깨짐 방지)
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8

# ---- git 저장소 경고 (검토 결과: B1) -----------------------------------------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "경고: 현재 위치가 git 저장소가 아닙니다. 구현 후 git diff 검토가 불가능합니다." >&2
  echo "      'git init' 후 사용을 권장합니다." >&2
fi

# ---- 실행 디렉터리 -----------------------------------------------------------
RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="docs/ai/runs/${RUN_ID}"
mkdir -p "$RUN_DIR"
printf '%s\n' "$USER_PROMPT" > "$RUN_DIR/user-prompt.txt"

echo "==> [1/4] Codex로 개발 요청 분석 및 플랜 생성 (read-only)"

CODEX_PROMPT="$(cat <<EOF
\$dev-planner

다음 사용자 요청을 분석해줘.

사용자 요청:
${USER_PROMPT}

규칙:
- 코드는 수정하지 마.
- 개발 요청이면 요구사항 구체화, 개발 계획, Claude Code 구현 프롬프트를 JSON으로 출력해.
- 개발 요청이 아니면 is_development_request=false 로 출력해.
- 반드시 dev-planner 스킬(SKILL.md)의 JSON 스키마를 그대로 따라.
- JSON 앞뒤에 설명 문장이나 Markdown 코드블록을 붙이지 마.
EOF
)"

set +e
codex exec --sandbox read-only "$CODEX_PROMPT" \
  > "$RUN_DIR/codex-plan.raw" 2> "$RUN_DIR/codex-stderr.log"
CODEX_EXIT=$?
set -e

if [ "$CODEX_EXIT" -ne 0 ]; then
  echo "오류: Codex 실행에 실패했습니다. (exit ${CODEX_EXIT})" >&2
  echo "  표준출력: $RUN_DIR/codex-plan.raw" >&2
  echo "  표준오류: $RUN_DIR/codex-stderr.log" >&2
  exit "$CODEX_EXIT"
fi

echo "==> [2/4] JSON 파싱 및 스키마 검증"

set +e
IS_DEV="$(RUN_DIR="$RUN_DIR" "$PYTHON" - <<'PY'
import json, os, re, sys
from pathlib import Path

run_dir = Path(os.environ["RUN_DIR"])
raw_path = run_dir / "codex-plan.raw"
json_path = run_dir / "codex-plan.json"
raw = raw_path.read_text(encoding="utf-8").strip()

def extract_json(text):
    if text.startswith("{") and text.endswith("}"):
        return text
    m = re.search(r"```(?:json)?\s*(\{.*\})\s*```", text, re.S)
    if m:
        return m.group(1)
    s, e = text.find("{"), text.rfind("}")
    if s != -1 and e != -1 and e > s:
        return text[s:e + 1]
    return text

try:
    data = json.loads(extract_json(raw))
except Exception as e:
    sys.stderr.write("오류: Codex 결과를 JSON으로 파싱하지 못했습니다.\n")
    sys.stderr.write(f"  원본: {raw_path}\n  에러: {e}\n")
    sys.exit(1)

if not isinstance(data, dict) or "is_development_request" not in data:
    sys.stderr.write("오류: 'is_development_request' 키가 없습니다. (스키마 위반)\n")
    sys.exit(2)

is_dev = data.get("is_development_request")
if is_dev is True:
    problems = []
    if not str(data.get("request_summary", "")).strip():
        problems.append("request_summary 누락")
    dp = data.get("development_plan")
    if not isinstance(dp, list) or not dp:
        problems.append("development_plan 비어있음/형식오류")
    if not str(data.get("claude_prompt", "")).strip():
        problems.append("claude_prompt 누락")
    if problems:
        sys.stderr.write("오류: 개발 계획 스키마 위반 -> " + ", ".join(problems) + "\n")
        sys.exit(2)
elif is_dev is False:
    if not str(data.get("answer", "")).strip():
        sys.stderr.write("오류: is_development_request=false 인데 answer가 비어 있습니다.\n")
        sys.exit(2)
else:
    sys.stderr.write("오류: is_development_request 는 true/false 여야 합니다.\n")
    sys.exit(2)

json_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
print("true" if is_dev else "false")
PY
)"
PARSE_EXIT=$?
set -e

if [ "$PARSE_EXIT" -ne 0 ]; then
  echo "  원본 출력: $RUN_DIR/codex-plan.raw" >&2
  exit "$PARSE_EXIT"
fi

echo "==> Codex 계획 저장: $RUN_DIR/codex-plan.json"

# ---- 분기 -------------------------------------------------------------------
if [ "$IS_DEV" != "true" ]; then
  echo
  echo "==> 개발 요청이 아닙니다. Codex 응답:"
  echo
  RUN_DIR="$RUN_DIR" "$PYTHON" - <<'PY'
import json, os
from pathlib import Path
data = json.loads((Path(os.environ["RUN_DIR"]) / "codex-plan.json").read_text(encoding="utf-8"))
print(data.get("answer", "응답 없음"))
PY
  exit 0
fi

echo "==> [3/4] 개발 요청으로 판단됨 → 승인/빌드 단계로 위임"
echo
exec "$SCRIPT_DIR/ai-build.sh" "$RUN_DIR"
