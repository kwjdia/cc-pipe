#!/usr/bin/env bash
#
# ai-build.sh — Codex 개발 계획(codex-plan.json)을 사람이 승인하면 Claude로 구현하는 빌드 단계.
#
#   사용법: ./scripts/ai-build.sh <run-dir>
#     예:   ./scripts/ai-build.sh docs/ai/runs/20260701-120000
#
# 이 스크립트는 두 진입점이 공유한다.
#   - CLI 경로: ai-dev.sh 가 계획 생성 후 자동 위임
#   - Codex 앱 경로: 앱에서 $dev-planner 로 만든 계획을 codex-plan.json 으로 저장한 뒤 직접 실행
#
set -euo pipefail

RUN_DIR="${1:-}"

if [ -z "$RUN_DIR" ]; then
  echo "사용법: ./scripts/ai-build.sh <run-dir>" >&2
  echo "  예: ./scripts/ai-build.sh docs/ai/runs/20260701-120000" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PLAN="$RUN_DIR/codex-plan.json"
if [ ! -f "$PLAN" ]; then
  echo "오류: '$PLAN' 이 없습니다. Codex 개발 계획(codex-plan.json)이 필요합니다." >&2
  exit 1
fi

# ---- 의존성 확인 --------------------------------------------------------------
if ! command -v claude >/dev/null 2>&1; then
  echo "오류: claude CLI를 찾을 수 없습니다." >&2
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
  echo "오류: 동작하는 python 3 을 찾을 수 없습니다." >&2
  exit 1
fi
# Python 입출력을 UTF-8로 강제 (Windows 로케일 인코딩으로 인한 한글 깨짐 방지)
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8

# ---- 계획 유효성 확인 --------------------------------------------------------
set +e
RUN_DIR="$RUN_DIR" "$PYTHON" - <<'PY'
import json, os, sys
from pathlib import Path
data = json.loads((Path(os.environ["RUN_DIR"]) / "codex-plan.json").read_text(encoding="utf-8"))
if data.get("is_development_request") is not True:
    sys.stderr.write("오류: is_development_request 가 true 가 아닙니다. 빌드할 계획이 아닙니다.\n")
    sys.exit(2)
if not str(data.get("claude_prompt", "")).strip():
    sys.stderr.write("오류: claude_prompt 가 비어 있습니다.\n")
    sys.exit(2)
PY
VALID_EXIT=$?
set -e
[ "$VALID_EXIT" -eq 0 ] || exit "$VALID_EXIT"

# ---- git 저장소 경고 (검토 결과: B1) -----------------------------------------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "경고: 현재 위치가 git 저장소가 아닙니다. 구현 후 git diff 검토가 불가능합니다." >&2
  read -r -p "그래도 계속할까요? [y/N] " GIT_CONFIRM
  if [[ "$GIT_CONFIRM" != "y" && "$GIT_CONFIRM" != "Y" ]]; then
    echo "중단했습니다."
    exit 0
  fi
fi

# ---- 계획 요약 출력 (검토 결과: M2 — 승인 대상 전체 노출) ---------------------
echo "===== Codex 개발 플랜 요약 ====="
echo
RUN_DIR="$RUN_DIR" "$PYTHON" - <<'PY'
import json, os
from pathlib import Path
data = json.loads((Path(os.environ["RUN_DIR"]) / "codex-plan.json").read_text(encoding="utf-8"))

def section(title, items):
    print(f"[{title}]")
    if items:
        for it in items:
            print(" -", it)
    else:
        print(" (없음)")
    print()

print("요약:", data.get("request_summary", ""))
print()
section("요구사항", data.get("requirements", []))
section("가정 사항 (assumptions)", data.get("assumptions", []))
section("확인 질문 (questions)", data.get("questions", []))

scope = data.get("scope", {}) or {}
section("포함 범위", scope.get("included", []))
section("제외 범위", scope.get("excluded", []))

print("[작업 계획]")
for step in data.get("development_plan", []):
    print(f" - {step.get('step')}. {step.get('title')}: {step.get('description')}")
    for f in step.get("expected_files", []) or []:
        print(f"     · 예상 파일: {f}")
    for t in step.get("test_criteria", []) or []:
        print(f"     · 테스트: {t}")
print()
section("Acceptance Criteria", data.get("acceptance_criteria", []))
section("리스크", data.get("risk_notes", []))

print("[Claude에 전달될 구현 요청 (claude_prompt)]")
print(data.get("claude_prompt", "").strip())
print()
PY

# ---- 미해결 질문 경고 (검토 결과: H2 — -p 는 되물을 수 없음) ------------------
HAS_Q="$(RUN_DIR="$RUN_DIR" "$PYTHON" - <<'PY'
import json, os
from pathlib import Path
data = json.loads((Path(os.environ["RUN_DIR"]) / "codex-plan.json").read_text(encoding="utf-8"))
print(len(data.get("questions", []) or []))
PY
)"
if [ "${HAS_Q:-0}" -gt 0 ]; then
  echo "⚠️  미해결 확인 질문이 ${HAS_Q}건 있습니다."
  echo "    Claude는 -p(비대화형)로 실행되어 되물을 수 없습니다."
  echo "    지금 진행하면 계획의 assumptions 기준으로 자동 처리됩니다."
  echo "    질문에 답을 반영하려면 중단(N) 후 요청을 구체화해 다시 실행하세요."
  echo
fi

# ---- 승인 게이트 (검토 결과: NFR-3 / SC-6) -----------------------------------
read -r -p "이 플랜으로 Claude Code 구현을 진행할까요? [y/N] " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "중단했습니다. Codex 계획은 다음 위치에 보존됩니다:"
  echo "  $PLAN"
  exit 0
fi

# ---- Claude 구현 프롬프트 조립 -----------------------------------------------
RUN_DIR="$RUN_DIR" "$PYTHON" - <<'PY'
import json, os
from pathlib import Path
run_dir = Path(os.environ["RUN_DIR"])
data = json.loads((run_dir / "codex-plan.json").read_text(encoding="utf-8"))
claude_prompt = data.get("claude_prompt", "").strip()

full = f"""너는 이 프로젝트의 구현 담당 Claude Code다.
아래 Codex 개발 계획을 기준으로 구현해라.

[Codex 개발 계획]
{json.dumps(data, ensure_ascii=False, indent=2)}

[구현 요청]
{claude_prompt}

[추가 규칙]
1. 먼저 git status 를 확인해라.
2. 관련 파일을 탐색한 뒤 구현해라.
3. 승인된 범위(scope.included)만 구현하고 scope.excluded 는 건드리지 마라.
4. 요청 범위를 초과하는 리팩터링은 하지 마라.
5. 불필요한 dependency 를 추가하지 마라.
6. Secret, Token, API Key 를 코드에 하드코딩하지 마라.
7. 신규 파일이 필요하면 Write 도구로 생성해라. (Edit 는 기존 파일 전용)
8. 가능한 경우 테스트를 실행하고, 불가능하면 이유를 남겨라.
9. 이 실행은 비대화형(-p)이라 되물을 수 없다. questions 가 남아 있으면 assumptions 를 따르되,
   추정한 부분을 최종 보고의 '남은 리스크'에 명확히 표기해라.
10. 최종 응답에 변경 파일 목록, 구현 요약, 실행한 테스트/결과, 설계와 달라진 점,
    남은 리스크, 사람이 확인할 부분을 포함해라.
"""
(run_dir / "claude-prompt.md").write_text(full, encoding="utf-8")
PY

echo
echo "==> Claude Code 구현 시작"
echo "==> 구현 프롬프트: $RUN_DIR/claude-prompt.md"
echo

# CLAUDE.md 는 프로젝트 루트에서 자동 로드되므로 별도 주입 불필요.
# 신규 파일 생성을 위해 Write 를 반드시 포함한다 (검토 결과: H1).
set +e
claude -p "$(cat "$RUN_DIR/claude-prompt.md")" \
  --allowedTools "Read,Edit,Write,Bash" \
  | tee "$RUN_DIR/claude-result.md"
CLAUDE_EXIT=${PIPESTATUS[0]}
set -e

if [ "$CLAUDE_EXIT" -ne 0 ]; then
  echo
  echo "주의: Claude Code 실행이 실패했거나 중단되었습니다. (exit ${CLAUDE_EXIT})" >&2
  echo "  결과 파일: $RUN_DIR/claude-result.md" >&2
  exit "$CLAUDE_EXIT"
fi

echo
echo "==> 완료"
echo "결과 디렉터리: $RUN_DIR"
echo
echo "다음 명령으로 변경 사항을 확인하세요:"
echo "  git diff --stat"
echo "  git diff"
echo
echo "문제가 없으면 직접 테스트 후 commit 하세요. (자동 commit/merge 하지 않음)"
