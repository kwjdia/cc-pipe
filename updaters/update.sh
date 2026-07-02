#!/usr/bin/env sh
#
# cc-pipe updater — 설치된 프로젝트의 .cc-pipe/ 안에 배치된다.
#   version.json 을 읽어 원격 ref 의 최신 커밋과 비교하고, 필요 시 재설치한다.
#
#   sh .cc-pipe/update.sh                 # 확인 + y/N 프롬프트 + 적용
#   sh .cc-pipe/update.sh --check-only    # 확인만
#   sh .cc-pipe/update.sh --force         # 프롬프트 없이 적용
#   sh .cc-pipe/update.sh --auto          # ai-dev.sh 용: 있으면 무프롬프트 적용, 실패는 fail-open
#
# 종료 코드(--auto): 0 = 최신/스킵, 10 = 업데이트 적용됨
#
set -eu

FORCE="false"
CHECK_ONLY="false"
AUTO="false"

for arg in "$@"; do
  case "$arg" in
    --force) FORCE="true" ;;
    --check-only) CHECK_ONLY="true" ;;
    --auto) AUTO="true" ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

SCRIPT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGET_ROOT=$(CDPATH= cd -- "$SCRIPT_ROOT/.." && pwd)
VERSION_PATH="$SCRIPT_ROOT/version.json"

# --auto 모드에서는 어떤 실패도 파이프라인을 막지 않는다(fail-open).
fail() {
  if [ "$AUTO" = "true" ]; then
    echo "경고(cc-pipe 자동 업데이트): $1 — 업데이트를 건너뛰고 계속합니다." >&2
    exit 0
  fi
  echo "$1" >&2
  exit 1
}

[ -f "$VERSION_PATH" ] || fail "version.json 을 찾을 수 없습니다: $VERSION_PATH"

read_json() {
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$VERSION_PATH" | head -n 1
}

REPO=$(read_json repo)
REF=$(read_json ref)
INSTALLED_COMMIT=$(read_json installedCommit)

[ -n "$REPO" ] || fail "version.json 에 repo 가 없습니다."
[ -n "$REF" ] || REF="main"

command -v git >/dev/null 2>&1 || fail "git 을 찾을 수 없습니다."

REMOTE_LINE=$(git ls-remote "$REPO" "refs/heads/$REF" 2>/dev/null || true)
[ -n "$REMOTE_LINE" ] || fail "원격 ref '$REF' 를 $REPO 에서 찾지 못했습니다(오프라인?)."

REMOTE_COMMIT=$(printf '%s\n' "$REMOTE_LINE" | awk '{print $1}')

if [ "$INSTALLED_COMMIT" = "$REMOTE_COMMIT" ]; then
  [ "$AUTO" = "true" ] || echo "cc-pipe 는 이미 최신입니다: $INSTALLED_COMMIT"
  exit 0
fi

echo "cc-pipe 업데이트 가능: $INSTALLED_COMMIT -> $REMOTE_COMMIT"

if [ "$CHECK_ONLY" = "true" ]; then
  exit 0
fi

if [ "$FORCE" != "true" ] && [ "$AUTO" != "true" ]; then
  printf '지금 업데이트할까요? [y/N] '
  read answer
  case "$answer" in
    y|Y|yes|YES|Yes) ;;
    *) echo "업데이트를 건너뛰었습니다."; exit 0 ;;
  esac
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

if ! git clone --depth 1 --branch "$REF" "$REPO" "$TMP_DIR" >/dev/null 2>&1; then
  fail "cc-pipe clone 실패: $REPO ($REF)"
fi

if [ ! -f "$TMP_DIR/install.sh" ]; then
  fail "clone 된 저장소에 install.sh 가 없습니다: $REPO ($REF)"
fi

# 새 install.sh 로 재설치(전체 재설치). 재실행 루프 방지를 위해 자동업데이트는 끈다.
# --auto 모드에서 재설치가 실패해도 파이프라인을 막지 않도록 fail() 로 처리한다.
if ! CC_PIPE_NO_UPDATE=1 sh "$TMP_DIR/install.sh" "$TARGET_ROOT" --force; then
  fail "cc-pipe 재설치 실패: $REPO ($REF)"
fi

echo "cc-pipe 업데이트 완료: $REMOTE_COMMIT"

if [ "$AUTO" = "true" ]; then
  exit 10
fi
exit 0
