#!/usr/bin/env sh
#
# cc-pipe installer (macOS / Linux) — 타깃 프로젝트 루트에서 실행한다.
#   sh install.sh [TARGET_PATH] [--force]
#
# 설치물: .agents/skills/dev-planner, scripts/ai-dev.sh, scripts/ai-build.sh,
#         docs/ai/runs/.gitkeep, .cc-pipe/(update.sh, update.ps1, version.json),
#         AGENTS.md / CLAUDE.md 관리 블록.
#
set -eu

TARGET_PATH="$(pwd)"
FORCE="false"

for arg in "$@"; do
  case "$arg" in
    --force) FORCE="true" ;;
    -*) echo "Unknown argument: $arg" >&2; exit 1 ;;
    *) TARGET_PATH="$arg" ;;
  esac
done

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGET_ROOT=$(CDPATH= cd -- "$TARGET_PATH" && pwd)
CC_PIPE_REPO="https://github.com/kwjdia/cc-pipe.git"
CC_PIPE_REF="main"

# ---- 가이드 블록 ------------------------------------------------------------
write_agents_block() {
  cat <<'EOF'
<!-- cc-pipe:start -->
## cc-pipe (Codex Planner × Claude Builder)

개발 요청을 Codex가 계획하고 Claude CLI가 구현하는 로컬 파이프라인.

실행:
```
./scripts/ai-dev.sh "<개발 요청>"
```

Codex(Planner)는 요청 판별 → 요구사항 구체화 → 개발 계획/구현 프롬프트(JSON)를 생성하며 코드는 수정하지 않는다.
개발 요청 분석은 `dev-planner` 스킬(`.agents/skills/dev-planner/SKILL.md`)을 사용한다(Codex 자동 탐색).

자동 업데이트: `ai-dev.sh` 실행 시 원격 최신 여부를 확인해 자동 재설치한다(fail-open, `CC_PIPE_NO_UPDATE=1` 로 비활성).
수동 확인: macOS `sh .cc-pipe/update.sh --check-only` · Windows `.\.cc-pipe\update.ps1 -CheckOnly`
<!-- cc-pipe:end -->
EOF
}

write_claude_block() {
  cat <<'EOF'
<!-- cc-pipe:start -->
## cc-pipe (Codex Planner × Claude Builder)

이 프로젝트는 cc-pipe 파이프라인을 사용한다. Claude Code는 Builder로서 Codex 계획(`codex-plan.json`)을 구현한다.

실행:
```
./scripts/ai-dev.sh "<개발 요청>"
```

Builder 규칙:
- 먼저 `git status` 확인 후 관련 파일을 탐색한다.
- 승인된 범위(`scope.included`)만 구현하고 `scope.excluded`는 건드리지 않는다.
- 신규 파일은 Write 도구로 생성한다(Edit는 기존 파일 전용).
- Secret/API Key/Token 하드코딩 금지, 불필요한 dependency 추가 금지.
- 비대화형(`-p`)이라 되물을 수 없다. 미해결 `questions`는 `assumptions` 기준으로 진행하고 남은 리스크에 표기한다.
- 구현 후 변경 파일·요약·테스트 결과·남은 리스크·사람 확인 항목을 보고한다.

자동 업데이트: `ai-dev.sh` 실행 시 원격 최신 여부를 확인해 자동 재설치한다(fail-open).
수동 확인: macOS `sh .cc-pipe/update.sh --check-only` · Windows `.\.cc-pipe\update.ps1 -CheckOnly`
<!-- cc-pipe:end -->
EOF
}

# 마커 블록을 멱등 주입: 있으면 교체, 없으면 append, 파일 없으면 신규 생성.
update_markdown_guide() {
  guide_file="$TARGET_ROOT/$1"
  block_file=$(mktemp)
  output_file=$(mktemp)

  "$2" > "$block_file"

  if [ -f "$guide_file" ]; then
    if grep -q '<!-- cc-pipe:start -->' "$guide_file" && grep -q '<!-- cc-pipe:end -->' "$guide_file"; then
      awk -v block_file="$block_file" '
        BEGIN { while ((getline line < block_file) > 0) { block = block line ORS } }
        /<!-- cc-pipe:start -->/ { printf "%s", block; in_block = 1; next }
        /<!-- cc-pipe:end -->/ { in_block = 0; next }
        !in_block { print }
      ' "$guide_file" > "$output_file"
      mv "$output_file" "$guide_file"
    else
      cat "$guide_file" > "$output_file"
      printf '\n\n' >> "$output_file"
      cat "$block_file" >> "$output_file"
      mv "$output_file" "$guide_file"
    fi
  else
    cp "$block_file" "$guide_file"
  fi

  rm -f "$block_file" "$output_file"
}

current_commit() {
  git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown'
}

install_updater() {
  cc_root="$TARGET_ROOT/.cc-pipe"
  mkdir -p "$cc_root"
  cp "$REPO_ROOT/updaters/update.sh" "$cc_root/update.sh"
  cp "$REPO_ROOT/updaters/update.ps1" "$cc_root/update.ps1"
  chmod +x "$cc_root/update.sh" 2>/dev/null || true

  installed_commit=$(current_commit)
  installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$cc_root/version.json" <<EOF
{
  "repo": "$CC_PIPE_REPO",
  "ref": "$CC_PIPE_REF",
  "installedCommit": "$installed_commit",
  "installedAt": "$installed_at"
}
EOF
}

# ---- 자산 복사 --------------------------------------------------------------
# (dest 상대경로 목록) — 존재하고 --force 아니면 중단
guard_exists() {
  dest="$TARGET_ROOT/$1"
  if [ -e "$dest" ] && [ "$FORCE" != "true" ]; then
    echo "설치 중단: '$dest' 가 이미 존재합니다. 덮어쓰려면 --force 로 다시 실행하세요." >&2
    exit 1
  fi
}

guard_exists ".agents/skills/dev-planner"
guard_exists "scripts/ai-dev.sh"
guard_exists "scripts/ai-build.sh"

mkdir -p "$TARGET_ROOT/.agents/skills" "$TARGET_ROOT/scripts" "$TARGET_ROOT/docs/ai/runs"

rm -rf "$TARGET_ROOT/.agents/skills/dev-planner"
cp -R "$REPO_ROOT/.agents/skills/dev-planner" "$TARGET_ROOT/.agents/skills/"
cp "$REPO_ROOT/scripts/ai-dev.sh" "$TARGET_ROOT/scripts/ai-dev.sh"
cp "$REPO_ROOT/scripts/ai-build.sh" "$TARGET_ROOT/scripts/ai-build.sh"
chmod +x "$TARGET_ROOT/scripts/ai-dev.sh" "$TARGET_ROOT/scripts/ai-build.sh" 2>/dev/null || true

if [ ! -e "$TARGET_ROOT/docs/ai/runs/.gitkeep" ]; then
  : > "$TARGET_ROOT/docs/ai/runs/.gitkeep"
fi

update_markdown_guide "AGENTS.md" write_agents_block
update_markdown_guide "CLAUDE.md" write_claude_block

install_updater

echo "cc-pipe 설치 완료: $TARGET_ROOT"
echo "  설치물: .agents/skills/dev-planner, scripts/ai-dev.sh, scripts/ai-build.sh, docs/ai/runs/"
echo "  업데이터: .cc-pipe/ (update.sh, update.ps1, version.json)"
echo "  가이드 블록 갱신: AGENTS.md, CLAUDE.md"
echo
echo "사용법: ./scripts/ai-dev.sh \"개발 요청 내용\""
