#
# cc-pipe updater (Windows) — 설치된 프로젝트의 .cc-pipe/ 안에 배치된다.
#   version.json 을 읽어 원격 ref 의 최신 커밋과 비교하고, 필요 시 재설치한다.
#
#   .\.cc-pipe\update.ps1                 # 확인 + y/N 프롬프트 + 적용
#   .\.cc-pipe\update.ps1 -CheckOnly      # 확인만
#   .\.cc-pipe\update.ps1 -Force          # 프롬프트 없이 적용
#   .\.cc-pipe\update.ps1 -Auto           # 자동: 있으면 무프롬프트 적용, 실패는 fail-open
#
# 종료 코드(-Auto): 0 = 최신/스킵, 10 = 업데이트 적용됨
#
param(
  [switch]$Force,
  [switch]$CheckOnly,
  [switch]$Auto
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$targetRoot = Split-Path -Parent $scriptRoot
$versionPath = Join-Path $scriptRoot "version.json"

# -Auto 모드에서는 어떤 실패도 파이프라인을 막지 않는다(fail-open).
function Fail([string]$Message) {
  if ($Auto) {
    Write-Warning "cc-pipe 자동 업데이트: $Message — 업데이트를 건너뛰고 계속합니다."
    exit 0
  }
  Write-Error $Message
  exit 1
}

if (-not (Test-Path -LiteralPath $versionPath)) {
  Fail "version.json 을 찾을 수 없습니다: $versionPath"
}

try {
  $version = Get-Content -Raw -LiteralPath $versionPath | ConvertFrom-Json
} catch {
  Fail "version.json 파싱 실패: $versionPath"
}

$repo = $version.repo
$ref = $version.ref
$installedCommit = $version.installedCommit

if ([string]::IsNullOrWhiteSpace($repo)) { Fail "version.json 에 repo 가 없습니다." }
if ([string]::IsNullOrWhiteSpace($ref)) { $ref = "main" }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "git 을 찾을 수 없습니다." }

$remoteLine = ""
try {
  $remoteLine = (git ls-remote $repo "refs/heads/$ref") -join "`n"
} catch {
  $remoteLine = ""
}
if ([string]::IsNullOrWhiteSpace($remoteLine)) {
  Fail "원격 ref '$ref' 를 $repo 에서 찾지 못했습니다(오프라인?)."
}

$remoteCommit = ($remoteLine -split "\s+")[0]

if ($installedCommit -eq $remoteCommit) {
  if (-not $Auto) { Write-Output "cc-pipe 는 이미 최신입니다: $installedCommit" }
  exit 0
}

Write-Output "cc-pipe 업데이트 가능: $installedCommit -> $remoteCommit"

if ($CheckOnly) { exit 0 }

if (-not $Force -and -not $Auto) {
  $answer = Read-Host "지금 업데이트할까요? [y/N]"
  if ($answer -notin @("y", "Y", "yes", "YES", "Yes")) {
    Write-Host "업데이트를 건너뛰었습니다."
    exit 0
  }
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-pipe-update-" + [guid]::NewGuid())

try {
  git clone --depth 1 --branch $ref $repo $tmp | Out-Null
  # 전체 재설치. 재실행 루프 방지를 위해 자동업데이트는 끈다.
  $env:CC_PIPE_NO_UPDATE = "1"
  & (Join-Path $tmp "install.ps1") -TargetPath $targetRoot -Force
  Write-Output "cc-pipe 업데이트 완료: $remoteCommit"
} catch {
  Fail "cc-pipe 업데이트 실패: $($_.Exception.Message)"
} finally {
  if (Test-Path -LiteralPath $tmp) {
    Remove-Item -LiteralPath $tmp -Recurse -Force
  }
}

if ($Auto) { exit 10 }
exit 0
