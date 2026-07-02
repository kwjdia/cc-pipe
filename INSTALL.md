# cc-pipe 설치

cc-pipe를 설치할 **프로젝트 루트 디렉터리에서** 아래 명령을 실행한다. cc-pipe 저장소는 public이므로 인증 없이 clone된다.

## Windows (PowerShell)

```powershell
$repo="https://github.com/kwjdia/cc-pipe.git"; $tmp=Join-Path $env:TEMP ("cc-pipe-"+[guid]::NewGuid()); git clone --depth 1 $repo $tmp; & (Join-Path $tmp "install.ps1") -TargetPath (Get-Location); Remove-Item -LiteralPath $tmp -Recurse -Force
```

기존 `scripts/`·스킬을 덮어쓰려면 `-Force`:

```powershell
$repo="https://github.com/kwjdia/cc-pipe.git"; $tmp=Join-Path $env:TEMP ("cc-pipe-"+[guid]::NewGuid()); git clone --depth 1 $repo $tmp; & (Join-Path $tmp "install.ps1") -TargetPath (Get-Location) -Force; Remove-Item -LiteralPath $tmp -Recurse -Force
```

## macOS / Linux

```sh
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; git clone --depth 1 https://github.com/kwjdia/cc-pipe.git "$tmp" && sh "$tmp/install.sh" "$(pwd)"
```

덮어쓰기:

```sh
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; git clone --depth 1 https://github.com/kwjdia/cc-pipe.git "$tmp" && sh "$tmp/install.sh" "$(pwd)" --force
```

## 설치물

```text
.agents/skills/dev-planner/SKILL.md     # 개발요청 판별·계획 스킬 (Codex 자동 탐색)
scripts/ai-dev.sh, ai-build.sh          # 파이프라인 스크립트
docs/ai/runs/.gitkeep                   # 실행 산출물 디렉터리
.cc-pipe/                               # update.sh, update.ps1, version.json
AGENTS.md / CLAUDE.md                   # <!-- cc-pipe:start/end --> 관리 블록 주입
```

설치는 `.agents/skills/dev-planner`·`scripts/ai-dev.sh`·`scripts/ai-build.sh`가 이미 있으면 중단한다. 의도적으로 덮어쓸 때 `-Force`(Windows)/`--force`(macOS)를 쓴다. 기존 `AGENTS.md`/`CLAUDE.md`는 보존되며 마커 블록만 추가·갱신된다.

> Windows에서 파이프라인 스크립트(`ai-dev.sh`/`ai-build.sh`)는 bash 기반이므로 **Git Bash 또는 WSL**에서 실행한다. 설치·업데이트 명령은 PowerShell에서 그대로 사용 가능하다.

## 업데이트

설치 후 타깃 프로젝트 안에 업데이터가 함께 설치된다.

- **자동**: `./scripts/ai-dev.sh` 실행 시마다 원격 `main`과 비교해 최신이 아니면 자동 재설치 후 진행한다(fail-open). `CC_PIPE_NO_UPDATE=1`로 비활성화.
- **수동**:

  ```sh
  sh ./.cc-pipe/update.sh               # 확인 + y/N + 적용
  sh ./.cc-pipe/update.sh --check-only  # 확인만
  sh ./.cc-pipe/update.sh --force       # 즉시 적용
  ```

  ```powershell
  .\.cc-pipe\update.ps1
  .\.cc-pipe\update.ps1 -CheckOnly
  .\.cc-pipe\update.ps1 -Force
  ```
