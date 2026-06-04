param(
  [string]$BaseUrl = $env:XIAOMA_HERMES_BASE_URL,
  [switch]$SkipOfficial
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  $BaseUrl = "https://useai.live/hermes"
}
$BaseUrl = $BaseUrl.TrimEnd("/")
$officialInstallUrl = $env:XIAOMA_HERMES_OFFICIAL_INSTALL_URL
if ([string]::IsNullOrWhiteSpace($officialInstallUrl)) {
  $officialInstallUrl = "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1"
}

function Write-Step([string]$Message) {
  Write-Host "[Hermes 中文增强] $Message"
}

function Find-HermesCommand {
  $cmd = Get-Command hermes -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA "hermes\hermes-agent\hermes.exe"),
    (Join-Path $env:LOCALAPPDATA "hermes\hermes-agent\hermes"),
    (Join-Path $env:USERPROFILE ".hermes\hermes-agent\hermes.exe"),
    (Join-Path $env:USERPROFILE ".hermes\hermes-agent\hermes")
  )
  foreach ($item in $candidates) {
    if ($item -and (Test-Path $item)) { return $item }
  }
  return $null
}

function Find-Bash {
  $cmd = Get-Command bash -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA "hermes\git\bin\bash.exe"),
    (Join-Path $env:LOCALAPPDATA "hermes\git\cmd\bash.exe"),
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
  )
  foreach ($item in $candidates) {
    if ($item -and (Test-Path $item)) { return $item }
  }
  return $null
}

function Invoke-OfficialInstall {
  if (Find-HermesCommand) { return }
  if ($SkipOfficial) {
    throw "未检测到 Hermes。已设置 SkipOfficial，安装停止。"
  }

  Write-Step "未检测到 Hermes，开始安装官方 Hermes Agent。"
  $script = Invoke-RestMethod -Uri $officialInstallUrl
  Invoke-Expression $script
}

function Convert-ToBashPath([string]$Path, [string]$BashPath) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  $escaped = $Path.Replace("\", "\\").Replace("'", "'\''")
  $converted = & $BashPath -lc "cygpath -u '$escaped' 2>/dev/null || printf '%s' '$escaped'"
  if ($LASTEXITCODE -ne 0) { return $Path }
  return ($converted | Select-Object -First 1).Trim()
}

Invoke-OfficialInstall

$bash = Find-Bash
if (-not $bash) {
  throw "未找到 Git Bash。请先安装官方 Hermes，或安装 Git for Windows 后重试。"
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("xiaoma-hermes-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
$installer = Join-Path $tempDir "install.sh"

try {
  Write-Step "下载中文增强安装器。"
  Invoke-WebRequest -Uri "$BaseUrl/install.sh" -OutFile $installer -UseBasicParsing

  $env:XIAOMA_HERMES_PLATFORM = "windows"
  $env:XIAOMA_HERMES_ENTRYPOINT = "windows-powershell"
  if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $hermesHomeWin = Join-Path $env:LOCALAPPDATA "hermes"
    $env:HERMES_HOME = Convert-ToBashPath -Path $hermesHomeWin -BashPath $bash
  }

  Write-Step "开始应用中文增强。"
  & $bash $installer
  if ($LASTEXITCODE -ne 0) {
    throw "中文增强安装失败，退出码 $LASTEXITCODE。"
  }

  Write-Step "完成。重新打开 Hermes 后检查中文界面。"
} finally {
  Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
}
