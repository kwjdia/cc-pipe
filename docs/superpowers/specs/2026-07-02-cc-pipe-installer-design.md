# cc-pipe 설치 / 자동 업데이트 기능 설계

> 작성일: 2026-07-02
> 상태: 승인됨 (구현 대기)
> 참고 구현: `D:\aiProject\agent-framework` (install.sh/ps1, updaters/, version.json 패턴)

## 목적

cc-pipe 파이프라인을 **CLI 명령 하나로 임의의 타깃 프로젝트에 설치**하고, 이후 `ai-dev.sh` 실행 때마다 **원격 최신 여부를 확인해 자동 재설치(업데이트)** 한다. cc-pipe 저장소(`https://github.com/kwjdia/cc-pipe.git`)는 public이므로 GitHub에서 직접 clone한다.

## 목표 / 비목표

**목표**
- Windows(PowerShell) · macOS/Linux(sh) 각각 호환되는 설치·업데이트 명령 제공.
- 타깃 프로젝트에 cc-pipe 자산(스킬·스크립트·가이드·업데이터) 설치.
- 기존 `AGENTS.md`/`CLAUDE.md`를 보존하며 관리 블록만 멱등 주입.
- `ai-dev.sh` 실행 시 자동 버전 확인 + 자동 업데이트(fail-open).

**비목표**
- 파이프라인 실행 로직 자체 변경(계획/승인/빌드 흐름은 그대로).
- PowerShell 네이티브 파이프라인 실행(스크립트는 bash 유지; Windows는 Git Bash/WSL).
- cc-pipe 소스 저장소 자체의 자기 자동업데이트(개발 안전을 위해 제외).

## 결정 사항 (승인됨)

1. **자동 업데이트 후 진행** — 실행 시작 시 원격 main과 비교해 최신이 아니면 조용히 재설치 후 계속. 오프라인/실패 시 경고만 하고 진행(fail-open).
2. **관리 블록 주입** — 타깃의 `AGENTS.md`/`CLAUDE.md`에 `<!-- cc-pipe:start -->`~`<!-- cc-pipe:end -->` 블록만 추가/갱신, 기존 내용 보존.
3. **전체 재설치** — 업데이트 시 스킬 + scripts + 가이드 블록 + 업데이터를 원격 최신으로 재설치(install --force 재실행).

## 설치 결과 레이아웃 (타깃 프로젝트)

```text
target/
  .agents/skills/dev-planner/SKILL.md   # 복사 (Codex 자동 탐색)
  scripts/
    ai-dev.sh                           # 복사 (자동 업데이트 블록 포함)
    ai-build.sh                         # 복사
  docs/ai/runs/.gitkeep                 # 생성
  .cc-pipe/                             # 제어 디렉터리
    update.sh
    update.ps1
    version.json                        # { repo, ref, installedCommit, installedAt }
  AGENTS.md   ← 관리 블록 주입 (Planner/dev-planner 규칙 + 사용법 + 업데이트 안내)
  CLAUDE.md   ← 관리 블록 주입 (Builder 규칙 + 사용법 + 업데이트 안내)
```

## 컴포넌트 설계

### 1. `install.sh` / `install.ps1` (cc-pipe 루트)

인자: `TargetPath`(기본=현재 디렉터리), `--force`/`-Force`.

동작:
1. `REPO_ROOT`(스크립트 위치=clone된 cc-pipe), `TARGET_ROOT` 확정.
2. 자산 복사: `.agents/skills/dev-planner`, `scripts/ai-dev.sh`, `scripts/ai-build.sh`, `docs/ai/runs/.gitkeep`.
   - 대상이 이미 있고 `--force`가 아니면 중단(안내).
3. 가이드 블록 주입: `AGENTS.md`(codex/planner), `CLAUDE.md`(claude/builder).
   - 마커 존재 → 블록 교체, 없음 → 파일 끝에 append, 파일 없음 → 신규 생성.
4. 업데이터 설치: `.cc-pipe/`에 `update.sh`·`update.ps1` 복사 + `version.json` 생성
   - `installedCommit = git -C REPO_ROOT rev-parse HEAD` (실패 시 `unknown`).
   - `repo = https://github.com/kwjdia/cc-pipe.git`, `ref = main`.
5. 완료 요약 출력.

### 2. `updaters/update.sh` / `update.ps1` → 타깃 `.cc-pipe/`

경로 유추: `SCRIPT_ROOT=.cc-pipe`, `TARGET_ROOT=.cc-pipe/..`.
`version.json`에서 repo/ref/installedCommit 읽음.

모드(인자):
- (기본) : 확인 + `y/N` 프롬프트 + 적용.
- `--check-only` / `-CheckOnly` : 확인만, 적용 안 함.
- `--force` / `-Force` : 프롬프트 없이 적용.
- `--auto` / `-Auto` : ai-dev.sh용. 확인 후 있으면 프롬프트 없이 적용. **fail-open**.

동작:
1. `git ls-remote <repo> refs/heads/<ref>` → `remoteCommit`.
2. `installedCommit == remoteCommit` → "up to date", **exit 0**.
3. 다름 → "update available: X -> Y".
   - `--check-only` → exit 0.
   - 적용: `git clone --depth 1 --branch <ref> <repo> $tmp` → `install.sh $TARGET_ROOT --force`(win은 install.ps1) → 정리.
   - `--auto` 성공 적용 → **exit 10** (호출자에게 "업데이트됨" 신호).
4. 오류(오프라인/git 실패/clone 실패):
   - 일반/`--force`/`--check-only` → 오류 메시지 + 비정상 종료.
   - `--auto` → 경고 출력 후 **exit 0** (fail-open, 파이프라인 계속).

종료 코드 규약(`--auto` 한정): `0`=최신 또는 fail-open 스킵, `10`=업데이트 적용됨.

### 3. `scripts/ai-dev.sh` 자동 업데이트 블록 (최상단, 의존성 확인 직후)

```sh
if [ -z "${CC_PIPE_NO_UPDATE:-}" ] && [ -x "$REPO_ROOT/.cc-pipe/update.sh" ]; then
  set +e
  "$REPO_ROOT/.cc-pipe/update.sh" --auto
  UPD_EXIT=$?
  set -e
  if [ "$UPD_EXIT" -eq 10 ]; then
    echo "==> cc-pipe 업데이트 적용됨 — 최신 버전으로 재실행"
    exec env CC_PIPE_NO_UPDATE=1 "$0" "$@"
  fi
fi
```

- `CC_PIPE_NO_UPDATE=1` : 자동 업데이트 스킵(재실행 루프 방지·오프라인·CI).
- `.cc-pipe/update.sh`가 없으면(=cc-pipe 소스 저장소에서 직접 실행) 스킵 → 자기 자신은 자동업데이트 안 함.
- 재실행은 새로 설치된 `ai-dev.sh`를 fresh로 로드(실행 중 파일 교체 문제 회피).

### 4. 가이드 블록 내용

- **AGENTS.md 블록**: cc-pipe 역할 분리 요약, `dev-planner` 스킬 안내, 실행법(`./scripts/ai-dev.sh "<요청>"`), 자동 업데이트 안내(수동 확인: `sh .cc-pipe/update.sh --check-only` / `.\.cc-pipe\update.ps1 -CheckOnly`), Planner 핵심 규칙(코드 미수정·JSON 출력).
- **CLAUDE.md 블록**: Builder 핵심 규칙(승인 범위만·Write로 신규 파일·Secret 금지·비대화형 questions 처리·구현 후 출력 형식), 실행법, 자동 업데이트 안내.
- 마커: `<!-- cc-pipe:start -->` / `<!-- cc-pipe:end -->`. 주입은 멱등(재설치·업데이트에 안전).

### 5. `version.json` 스키마

```json
{
  "repo": "https://github.com/kwjdia/cc-pipe.git",
  "ref": "main",
  "installedCommit": "<40-hex or 'unknown'>",
  "installedAt": "<ISO-8601 UTC>"
}
```

## 설치/업데이트 명령 (INSTALL.md / README)

**Windows PowerShell**
```powershell
$repo="https://github.com/kwjdia/cc-pipe.git"; $tmp=Join-Path $env:TEMP ("cc-pipe-"+[guid]::NewGuid()); git clone --depth 1 $repo $tmp; & (Join-Path $tmp "install.ps1") -TargetPath (Get-Location); Remove-Item -LiteralPath $tmp -Recurse -Force
```

**macOS / Linux**
```sh
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; git clone --depth 1 https://github.com/kwjdia/cc-pipe.git "$tmp" && sh "$tmp/install.sh" "$(pwd)"
```

기존 파일 덮어쓰기: `-Force` / `--force`.

**업데이트(수동)**: `.\.cc-pipe\update.ps1` / `sh ./.cc-pipe/update.sh` (프롬프트) · `-CheckOnly`/`--check-only` (확인만) · `-Force`/`--force` (즉시).

## 오류 처리 원칙

- 설치: 대상 존재 && `--force` 아님 → 중단(안내). git rev-parse 실패 → `installedCommit=unknown`(치명적 아님).
- 업데이트 `--auto`: 모든 실패는 경고 후 파이프라인 계속(fail-open). 그 외 모드는 명확한 오류 + 비정상 종료.
- 이식성: `*.sh`는 LF 유지(`.gitattributes` 기존 규칙). 설치 스크립트는 `sh` 호환(POSIX), 파이프라인은 bash.

## 테스트 계획

스텁/픽스처로 네트워크·실 CLI 없이 검증(기존 검증 방식 재사용).

1. **install.sh 신규 설치** → 레이아웃·version.json·가이드 블록 생성 확인.
2. **install.sh 재설치(--force)** → 가이드 블록 멱등(중복 없이 교체) 확인.
3. **기존 CLAUDE.md 보존** → 사용자 내용 위에 블록만 추가/교체 확인.
4. **update.sh --check-only** : installedCommit≠remote(fake) → "update available" + exit 0; 같으면 "up to date".
5. **update.sh --auto fail-open** : 잘못된 repo/오프라인 → 경고 + exit 0.
6. **ai-dev.sh 자동업데이트 스킵** : `.cc-pipe/` 없음(소스 저장소) → 스킵하고 정상 동작. `CC_PIPE_NO_UPDATE=1` → 스킵.
7. install.ps1 / update.ps1 : PowerShell 구문 검사(`Get-Command -Syntax` 또는 파싱) + 가능 시 동작.

## 변경 파일 목록

신규:
- `install.sh`, `install.ps1`
- `updaters/update.sh`, `updaters/update.ps1`
- `INSTALL.md`
- `docs/superpowers/specs/2026-07-02-cc-pipe-installer-design.md` (본 문서)

수정:
- `scripts/ai-dev.sh` (자동 업데이트 블록)
- `README.md` (설치·업데이트 섹션)
- `.gitignore` (필요 시: 타깃 전용 `.cc-pipe/`는 소스 저장소엔 없음 — 변경 불필요 예상)
