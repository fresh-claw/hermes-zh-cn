param(
  [string]$BaseUrl = $env:XIAOMA_HERMES_BASE_URL,
  [string]$FallbackBaseUrl = $env:XIAOMA_HERMES_FALLBACK_BASE_URL,
  [switch]$SkipOfficial
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  $BaseUrl = "https://useai.live/hermes"
}
$BaseUrl = $BaseUrl.TrimEnd("/")
if ([string]::IsNullOrWhiteSpace($FallbackBaseUrl)) {
  $FallbackBaseUrl = "https://cdn.jsdelivr.net/gh/fresh-claw/hermes-cn@v2026.06.05.2"
}
$FallbackBaseUrl = $FallbackBaseUrl.TrimEnd("/")
$officialInstallUrl = $env:XIAOMA_HERMES_OFFICIAL_INSTALL_URL
if ([string]::IsNullOrWhiteSpace($officialInstallUrl)) {
  $officialInstallUrl = "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1"
}

function Write-Step([string]$Message) {
  Write-Host "[Hermes 中文增强] $Message"
}

function Get-HermesHomePath {
  if (-not [string]::IsNullOrWhiteSpace($env:HERMES_HOME)) {
    return $env:HERMES_HOME
  }
  if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    return (Join-Path $env:LOCALAPPDATA "hermes")
  }
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    return (Join-Path $env:USERPROFILE ".hermes")
  }
  throw "无法确定 Hermes 配置目录，请设置 HERMES_HOME 后重试。"
}

function Backup-UserConfig([string]$HermesHomePath, [string]$BackupDir) {
  New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
  foreach ($name in @("config.yaml", ".env")) {
    $source = Join-Path $HermesHomePath $name
    if (Test-Path $source) {
      Copy-Item -Force $source (Join-Path $BackupDir $name)
    }
  }
}

function Restore-UserConfigIfMissing([string]$HermesHomePath, [string]$BackupDir) {
  foreach ($name in @("config.yaml", ".env")) {
    $backup = Join-Path $BackupDir $name
    $target = Join-Path $HermesHomePath $name
    if ((Test-Path $backup) -and -not (Test-Path $target)) {
      New-Item -ItemType Directory -Force -Path $HermesHomePath | Out-Null
      Copy-Item -Force $backup $target
      Write-Step "已恢复原有 $name。"
    }
  }
}

function Find-HermesCommand {
  $cmd = Get-Command hermes -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $hermesHome = Get-HermesHomePath
  $candidates = @(
    (Join-Path $hermesHome "hermes-agent\venv\Scripts\hermes.exe"),
    (Join-Path $hermesHome "hermes-agent\venv\Scripts\hermes.cmd"),
    (Join-Path $hermesHome "hermes-agent\hermes.exe"),
    (Join-Path $hermesHome "hermes-agent\hermes")
  )
  if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $candidates += (Join-Path $env:LOCALAPPDATA "hermes\hermes-agent\venv\Scripts\hermes.exe")
    $candidates += (Join-Path $env:LOCALAPPDATA "hermes\hermes-agent\venv\Scripts\hermes.cmd")
    $candidates += (Join-Path $env:LOCALAPPDATA "hermes\hermes-agent\hermes.exe")
    $candidates += (Join-Path $env:LOCALAPPDATA "hermes\hermes-agent\hermes")
  }
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $candidates += (Join-Path $env:USERPROFILE ".hermes\hermes-agent\venv\Scripts\hermes.exe")
    $candidates += (Join-Path $env:USERPROFILE ".hermes\hermes-agent\venv\Scripts\hermes.cmd")
    $candidates += (Join-Path $env:USERPROFILE ".hermes\hermes-agent\hermes.exe")
    $candidates += (Join-Path $env:USERPROFILE ".hermes\hermes-agent\hermes")
  }
  foreach ($item in $candidates) {
    if ($item -and (Test-Path $item)) { return $item }
  }
  return $null
}

function Find-HermesDesktop {
  $candidates = @()
  $hermesHome = Get-HermesHomePath
  if (-not [string]::IsNullOrWhiteSpace($hermesHome)) {
    $candidates += (Join-Path $hermesHome "hermes-agent\apps\desktop\release\win-unpacked\Hermes.exe")
    $candidates += (Join-Path $hermesHome "hermes-agent\apps\desktop\release\win-arm64-unpacked\Hermes.exe")
  }
  if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $candidates += (Join-Path $env:LOCALAPPDATA "hermes\hermes-agent\apps\desktop\release\win-unpacked\Hermes.exe")
    $candidates += (Join-Path $env:LOCALAPPDATA "hermes\hermes-agent\apps\desktop\release\win-arm64-unpacked\Hermes.exe")
    $candidates += (Join-Path $env:LOCALAPPDATA "Programs\Hermes\Hermes.exe")
  }
  if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
    $candidates += (Join-Path $env:ProgramFiles "Hermes\Hermes.exe")
  }
  $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
  if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
    $candidates += (Join-Path $programFilesX86 "Hermes\Hermes.exe")
  }
  foreach ($item in $candidates) {
    if ($item -and (Test-Path $item)) { return $item }
  }

  $releaseDirs = @((Join-Path $hermesHome "hermes-agent\apps\desktop\release"))
  if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $releaseDirs += (Join-Path $env:LOCALAPPDATA "hermes\hermes-agent\apps\desktop\release")
  }
  foreach ($releaseDir in $releaseDirs) {
    if (Test-Path $releaseDir) {
      $found = Get-ChildItem -Path $releaseDir -Recurse -Filter "Hermes.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($found) { return $found.FullName }
    }
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
  $hermesCmd = Find-HermesCommand
  $desktopExe = Find-HermesDesktop
  if ($hermesCmd -and $desktopExe) { return }
  if ($SkipOfficial) {
    throw "未检测到完整的 Hermes 桌面端。已设置 SkipOfficial，安装停止。"
  }

  if (-not $hermesCmd) {
    Write-Step "未检测到 Hermes，开始安装官方 Hermes 桌面端。"
  } else {
    Write-Step "检测到 Hermes 命令行，开始补装官方桌面端。"
  }

  $hermesHome = Get-HermesHomePath
  $configBackup = Join-Path ([System.IO.Path]::GetTempPath()) ("hermes-user-config-" + [guid]::NewGuid().ToString("N"))
  $officialInstaller = Join-Path ([System.IO.Path]::GetTempPath()) ("hermes-official-" + [guid]::NewGuid().ToString("N") + ".ps1")
  try {
    Backup-UserConfig -HermesHomePath $hermesHome -BackupDir $configBackup
    Invoke-WebRequest -Uri $officialInstallUrl -OutFile $officialInstaller -UseBasicParsing
    & powershell -NoProfile -ExecutionPolicy Bypass -File $officialInstaller -IncludeDesktop -NonInteractive
    if ($LASTEXITCODE -ne 0) {
      throw "官方 Hermes 桌面端安装失败，退出码 $LASTEXITCODE。"
    }
    Restore-UserConfigIfMissing -HermesHomePath $hermesHome -BackupDir $configBackup
  } finally {
    Remove-Item -Force $officialInstaller -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $configBackup -ErrorAction SilentlyContinue
  }

  if (-not (Find-HermesCommand)) {
    throw "官方 Hermes 安装后仍未检测到 hermes 命令，请打开新 PowerShell 后重试。"
  }
  if (-not (Find-HermesDesktop)) {
    throw "官方 Hermes 桌面端未生成，请确认 Node.js 可用后重试。"
  }
}

function Convert-ToBashPath([string]$Path, [string]$BashPath) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  $escaped = $Path.Replace("\", "\\").Replace("'", "'\''")
  $converted = & $BashPath -lc "cygpath -u '$escaped' 2>/dev/null || printf '%s' '$escaped'"
  if ($LASTEXITCODE -ne 0) { return $Path }
  return ($converted | Select-Object -First 1).Trim()
}

function Test-BashInstaller([string]$Path) {
  if (-not (Test-Path $Path)) { return $false }
  $firstLine = Get-Content -Path $Path -TotalCount 1 -ErrorAction SilentlyContinue
  return ($firstLine -like "#!*bash*" -or $firstLine -like "#!/usr/bin/env bash*")
}

function Download-Installer([string]$PrimaryBaseUrl, [string]$BackupBaseUrl, [string]$OutFile) {
  try {
    Invoke-WebRequest -Uri "$PrimaryBaseUrl/install.sh" -OutFile $OutFile -UseBasicParsing
    if (-not (Test-BashInstaller -Path $OutFile)) {
      throw "主入口返回的不是 Bash 安装脚本。"
    }
    return $PrimaryBaseUrl
  } catch {
    if (-not [string]::IsNullOrWhiteSpace($BackupBaseUrl) -and $BackupBaseUrl -ne $PrimaryBaseUrl) {
      Write-Step "网站下载受限，改用备用入口。"
      Invoke-WebRequest -Uri "$BackupBaseUrl/install.sh" -OutFile $OutFile -UseBasicParsing
      if (-not (Test-BashInstaller -Path $OutFile)) {
        throw "备用入口返回的不是 Bash 安装脚本。"
      }
      return $BackupBaseUrl
    }
    throw
  }
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
  $activeBaseUrl = Download-Installer -PrimaryBaseUrl $BaseUrl -BackupBaseUrl $FallbackBaseUrl -OutFile $installer

  $env:XIAOMA_HERMES_PLATFORM = "windows"
  $env:XIAOMA_HERMES_ENTRYPOINT = "windows-powershell"
  $env:XIAOMA_HERMES_BASE_URL = $activeBaseUrl
  $env:HERMES_HOME = Convert-ToBashPath -Path (Get-HermesHomePath) -BashPath $bash

  Write-Step "开始应用中文增强。"
  & $bash $installer
  if ($LASTEXITCODE -ne 0) {
    throw "中文增强安装失败，退出码 $LASTEXITCODE。"
  }

  Write-Step "完成。重新打开 Hermes 后检查中文界面。"
} finally {
  Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
}
