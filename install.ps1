#
# cc-pipe installer (Windows) — 타깃 프로젝트 루트에서 실행한다.
#   .\install.ps1 [-TargetPath <path>] [-Force]
#
# 설치물: .agents/skills/dev-planner, scripts/ai-dev.sh, scripts/ai-build.sh,
#         docs/ai/runs/.gitkeep, .cc-pipe/(update.sh, update.ps1, version.json),
#         AGENTS.md / CLAUDE.md 관리 블록.
#
param(
  [string]$TargetPath = (Get-Location).Path,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$targetRoot = (Resolve-Path -LiteralPath $TargetPath).Path
$ccPipeRepo = "https://github.com/kwjdia/cc-pipe.git"
$ccPipeRef = "main"
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Get-AgentsBlock {
  return @'
<!-- cc-pipe:start -->
## cc-pipe (Codex Planner × Claude Builder)

개발 요청을 Codex가 계획하고 Claude CLI가 구현하는 로컬 파이프라인.

실행:
```
./scripts/ai-dev.sh "<개발 요청>"
```

Codex(Planner)는 요청 판별 → 요구사항 구체화 → 개발 계획/구현 프롬프트(JSON)를 생성하며 코드는 수정하지 않는다.
스킬(Codex 자동 탐색):
- `dev-planner` — 개발 계획(JSON)까지만 생성. 빌드는 사람이 승인 후 실행.
- `dev-runner` — 계획 생성 후 곧바로 Claude 빌드까지 **자동 실행**(`ai-build.sh --yes`). 명령 실행 권한 필요, 승인 게이트 없음.

자동 업데이트: `ai-dev.sh` 실행 시 원격 최신 여부를 확인해 자동 재설치한다(fail-open, `CC_PIPE_NO_UPDATE=1` 로 비활성).
수동 확인: macOS `sh .cc-pipe/update.sh --check-only` · Windows `.\.cc-pipe\update.ps1 -CheckOnly`
<!-- cc-pipe:end -->
'@
}

function Get-ClaudeBlock {
  return @'
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
'@
}

function Update-MarkdownGuide {
  param([string]$Path, [string]$Block)

  $pattern = "(?s)<!-- cc-pipe:start -->.*?<!-- cc-pipe:end -->"
  if (Test-Path -LiteralPath $Path) {
    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ([regex]::IsMatch($content, $pattern)) {
      $updated = [regex]::Replace($content, $pattern, [System.Text.RegularExpressions.MatchEvaluator] { param($m) $Block })
    } else {
      $updated = $content.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $Block + [Environment]::NewLine
    }
  } else {
    $updated = $Block + [Environment]::NewLine
  }
  [System.IO.File]::WriteAllText($Path, $updated, $utf8)
}

function Get-CurrentCommit {
  try {
    $commit = git -C $repoRoot rev-parse HEAD
    if (-not [string]::IsNullOrWhiteSpace($commit)) { return $commit.Trim() }
  } catch { }
  return "unknown"
}

function Install-Updater {
  $ccRoot = Join-Path $targetRoot ".cc-pipe"
  $updaterRoot = Join-Path $repoRoot "updaters"
  New-Item -ItemType Directory -Path $ccRoot -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $updaterRoot "update.sh") -Destination (Join-Path $ccRoot "update.sh") -Force
  Copy-Item -LiteralPath (Join-Path $updaterRoot "update.ps1") -Destination (Join-Path $ccRoot "update.ps1") -Force

  $version = [ordered]@{
    repo = $ccPipeRepo
    ref = $ccPipeRef
    installedCommit = Get-CurrentCommit
    installedAt = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  } | ConvertTo-Json
  [System.IO.File]::WriteAllText((Join-Path $ccRoot "version.json"), $version + [Environment]::NewLine, $utf8)
}

# ---- 자산 복사 --------------------------------------------------------------
# .agents/skills 하위의 모든 스킬(dev-planner, dev-runner, …)을 대상으로 한다.
$skillsSource = Join-Path $repoRoot ".agents\skills"
$skillDirs = Get-ChildItem -LiteralPath $skillsSource -Directory
$guards = @("scripts\ai-dev.sh", "scripts\ai-build.sh")
foreach ($s in $skillDirs) { $guards += ".agents\skills\" + $s.Name }
foreach ($g in $guards) {
  $dest = Join-Path $targetRoot $g
  if ((Test-Path -LiteralPath $dest) -and -not $Force) {
    throw "설치 중단: '$dest' 가 이미 존재합니다. 덮어쓰려면 -Force 로 다시 실행하세요."
  }
}

New-Item -ItemType Directory -Path (Join-Path $targetRoot ".agents\skills") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $targetRoot "scripts") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $targetRoot "docs\ai\runs") -Force | Out-Null

foreach ($s in $skillDirs) {
  $skillDest = Join-Path $targetRoot (".agents\skills\" + $s.Name)
  if (Test-Path -LiteralPath $skillDest) { Remove-Item -LiteralPath $skillDest -Recurse -Force }
  Copy-Item -LiteralPath $s.FullName -Destination (Join-Path $targetRoot ".agents\skills") -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $repoRoot "scripts\ai-dev.sh") -Destination (Join-Path $targetRoot "scripts\ai-dev.sh") -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "scripts\ai-build.sh") -Destination (Join-Path $targetRoot "scripts\ai-build.sh") -Force

$gitkeep = Join-Path $targetRoot "docs\ai\runs\.gitkeep"
if (-not (Test-Path -LiteralPath $gitkeep)) { [System.IO.File]::WriteAllText($gitkeep, "", $utf8) }

Update-MarkdownGuide -Path (Join-Path $targetRoot "AGENTS.md") -Block (Get-AgentsBlock)
Update-MarkdownGuide -Path (Join-Path $targetRoot "CLAUDE.md") -Block (Get-ClaudeBlock)

Install-Updater

Write-Host "cc-pipe 설치 완료: $targetRoot"
Write-Host "  설치물: .agents/skills/dev-planner, scripts/ai-dev.sh, scripts/ai-build.sh, docs/ai/runs/"
Write-Host "  업데이터: .cc-pipe/ (update.sh, update.ps1, version.json)"
Write-Host "  가이드 블록 갱신: AGENTS.md, CLAUDE.md"
Write-Host ""
Write-Host "사용법: ./scripts/ai-dev.sh `"개발 요청 내용`""
