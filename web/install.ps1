param(
  [string]$BaseUrl = $env:XIAOMA_HERMES_BASE_URL,
  [string]$FallbackBaseUrl = $env:XIAOMA_HERMES_FALLBACK_BASE_URL,
  [switch]$SkipOfficial
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  $BaseUrl = "http://47.121.138.43/hermes"
}
$BaseUrl = $BaseUrl.TrimEnd("/")
if ([string]::IsNullOrWhiteSpace($FallbackBaseUrl)) {
  $FallbackBaseUrl = "https://cdn.jsdelivr.net/gh/fresh-claw/hermes-cn@v2026.06.08.2"
}
$FallbackBaseUrl = $FallbackBaseUrl.TrimEnd("/")
$pinnedVersion = $env:XIAOMA_HERMES_PINNED_VERSION
if ([string]::IsNullOrWhiteSpace($pinnedVersion)) {
  $pinnedVersion = "v2026.06.08.2"
}
$downloadTimeoutSec = 60
if (-not [string]::IsNullOrWhiteSpace($env:XIAOMA_HERMES_DOWNLOAD_TIMEOUT_SEC)) {
  $downloadTimeoutSec = [Math]::Max(10, [int]$env:XIAOMA_HERMES_DOWNLOAD_TIMEOUT_SEC)
}
$officialInstallUrl = $env:XIAOMA_HERMES_OFFICIAL_INSTALL_URL
if ([string]::IsNullOrWhiteSpace($officialInstallUrl)) {
  $officialInstallUrl = "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1"
}

function Write-Step([string]$Message) {
  Write-Host "[Hermes 中文增强] $Message"
}

function Select-UniqueText([string[]]$Items) {
  $seen = @{}
  $result = New-Object System.Collections.Generic.List[string]
  foreach ($item in $Items) {
    if ([string]::IsNullOrWhiteSpace($item)) { continue }
    $clean = $item.Trim().TrimEnd("/")
    if (-not $seen.ContainsKey($clean)) {
      $seen[$clean] = $true
      [void]$result.Add($clean)
    }
  }
  return $result.ToArray()
}

function Get-InstallerBaseUrls {
  if (-not [string]::IsNullOrWhiteSpace($env:XIAOMA_HERMES_BASE_URLS)) {
    return Select-UniqueText ($env:XIAOMA_HERMES_BASE_URLS -split ",")
  }
  return Select-UniqueText @(
    $BaseUrl,
    $FallbackBaseUrl,
    "https://fastly.jsdelivr.net/gh/fresh-claw/hermes-cn@$pinnedVersion",
    "https://gcore.jsdelivr.net/gh/fresh-claw/hermes-cn@$pinnedVersion",
    "https://raw.githubusercontent.com/fresh-claw/hermes-cn/$pinnedVersion"
  )
}

function Get-OfficialInstallUrls {
  if (-not [string]::IsNullOrWhiteSpace($env:XIAOMA_HERMES_OFFICIAL_INSTALL_URLS)) {
    return Select-UniqueText ($env:XIAOMA_HERMES_OFFICIAL_INSTALL_URLS -split ",")
  }
  return Select-UniqueText @(
    "$BaseUrl/official-hermes-install.ps1",
    "$FallbackBaseUrl/official-hermes-install.ps1",
    "https://fastly.jsdelivr.net/gh/fresh-claw/hermes-cn@$pinnedVersion/official-hermes-install.ps1",
    "https://gcore.jsdelivr.net/gh/fresh-claw/hermes-cn@$pinnedVersion/official-hermes-install.ps1",
    "https://raw.githubusercontent.com/fresh-claw/hermes-cn/$pinnedVersion/official-hermes-install.ps1",
    $officialInstallUrl,
    "https://cdn.jsdelivr.net/gh/NousResearch/hermes-agent@main/scripts/install.ps1",
    "https://fastly.jsdelivr.net/gh/NousResearch/hermes-agent@main/scripts/install.ps1",
    "https://gcore.jsdelivr.net/gh/NousResearch/hermes-agent@main/scripts/install.ps1"
  )
}

function Invoke-DownloadWithSources([string[]]$Urls, [string]$OutFile, [string]$Label) {
  foreach ($url in $Urls) {
    if ([string]::IsNullOrWhiteSpace($url)) { continue }
    Write-Step "正在下载$Label：$url"
    try {
      Invoke-WebRequest -Uri $url -OutFile $OutFile -UseBasicParsing -TimeoutSec $downloadTimeoutSec
      return $url
    } catch {
      Write-Step "当前入口不可用或过慢，正在切换下一个入口。"
    }
  }
  throw "$Label 下载失败，请稍后重试。"
}

function Test-OfficialInstallerPs1([string]$Path) {
  if (-not (Test-Path $Path)) { return $false }
  $text = Get-Content -Raw -Path $Path -ErrorAction SilentlyContinue
  return ($text -and $text.Contains("param(") -and $text.Contains("IncludeDesktop") -and $text.Contains("hermes-agent"))
}

function Download-OfficialInstaller([string]$OutFile) {
  foreach ($url in (Get-OfficialInstallUrls)) {
    if ([string]::IsNullOrWhiteSpace($url)) { continue }
    Write-Step "正在下载官方 Hermes 安装器：$url"
    try {
      Invoke-WebRequest -Uri $url -OutFile $OutFile -UseBasicParsing -TimeoutSec $downloadTimeoutSec
      if (-not (Test-OfficialInstallerPs1 -Path $OutFile)) {
        throw "当前入口返回的不是官方安装器脚本。"
      }
      return $url
    } catch {
      Write-Step "当前入口不可用或过慢，正在切换下一个入口。"
    }
  }
  throw "官方 Hermes 安装器下载失败，请稍后重试。"
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

function Select-UniquePaths([string[]]$Items) {
  $seen = @{}
  $result = New-Object System.Collections.Generic.List[string]
  foreach ($item in $Items) {
    if ([string]::IsNullOrWhiteSpace($item)) { continue }
    $clean = $item.Trim().TrimEnd("\")
    if (-not $seen.ContainsKey($clean)) {
      $seen[$clean] = $true
      [void]$result.Add($clean)
    }
  }
  return $result.ToArray()
}

function Get-HermesAgentSourcePaths {
  $items = @()
  $hermesHome = Get-HermesHomePath
  if (-not [string]::IsNullOrWhiteSpace($hermesHome)) {
    $items += (Join-Path $hermesHome "hermes-agent")
  }
  if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $items += (Join-Path $env:LOCALAPPDATA "hermes\hermes-agent")
  }
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $items += (Join-Path $env:USERPROFILE ".hermes\hermes-agent")
  }
  return Select-UniquePaths $items
}

function Move-HermesAgentSourceAside([string]$Reason) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $moved = $false
  foreach ($path in (Get-HermesAgentSourcePaths)) {
    if (-not (Test-Path $path)) { continue }
    $target = "$path.backup-$stamp"
    try {
      Move-Item -Force -Path $path -Destination $target
      Write-Step "已备份异常官方 Hermes 源码目录：$target"
      $moved = $true
    } catch {
      Write-Step "无法备份官方 Hermes 源码目录：$($_.Exception.Message)"
    }
  }
  if (-not $moved) {
    Write-Step "未找到可备份的官方 Hermes 源码目录。"
  }
}

function Invoke-OfficialInstallerOnce([string]$InstallerPath) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $InstallerPath -IncludeDesktop -NonInteractive
  if ($LASTEXITCODE -ne 0) {
    throw "官方 Hermes 桌面端安装失败，退出码 $LASTEXITCODE。"
  }
}

function New-HermesDesktopShortcut {
  $desktopExe = Find-HermesDesktop
  if (-not $desktopExe) {
    Write-Step "未找到 Hermes 桌面程序，暂时无法创建桌面快捷方式。"
    return
  }

  try {
    $desktopDir = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    if ([string]::IsNullOrWhiteSpace($desktopDir)) {
      $desktopDir = Join-Path $env:USERPROFILE "Desktop"
    }
    if ([string]::IsNullOrWhiteSpace($desktopDir)) {
      Write-Step "未找到桌面目录，暂时无法创建快捷方式。"
      return
    }

    New-Item -ItemType Directory -Force -Path $desktopDir | Out-Null
    $shortcutPath = Join-Path $desktopDir "Hermes 中文增强版.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $desktopExe
    $shortcut.WorkingDirectory = Split-Path -Parent $desktopExe
    $shortcut.IconLocation = "$desktopExe,0"
    $shortcut.Description = "Hermes 中文增强版"
    $shortcut.Save()

    Write-Step "已在桌面创建快捷方式：Hermes 中文增强版。"
  } catch {
    Write-Step "创建桌面快捷方式未完成：$($_.Exception.Message)"
  }
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
    Download-OfficialInstaller -OutFile $officialInstaller | Out-Null

    try {
      Invoke-OfficialInstallerOnce -InstallerPath $officialInstaller
    } catch {
      $firstError = $_.Exception.Message
      Write-Step "官方安装未完成：$firstError"
      Write-Step "正在修复官方 Hermes 源码目录并重试。"
      Restore-UserConfigIfMissing -HermesHomePath $hermesHome -BackupDir $configBackup
      Move-HermesAgentSourceAside -Reason $firstError
      Invoke-OfficialInstallerOnce -InstallerPath $officialInstaller
    }

    Restore-UserConfigIfMissing -HermesHomePath $hermesHome -BackupDir $configBackup

    if (-not (Find-HermesDesktop)) {
      Write-Step "官方 Hermes 桌面端未生成，正在清理官方源码目录后再试一次。"
      Move-HermesAgentSourceAside -Reason "desktop missing"
      Invoke-OfficialInstallerOnce -InstallerPath $officialInstaller
      Restore-UserConfigIfMissing -HermesHomePath $hermesHome -BackupDir $configBackup
    }
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
  if (-not ($firstLine -like "#!*bash*" -or $firstLine -like "#!/usr/bin/env bash*")) { return $false }
  $text = Get-Content -Raw -Path $Path -ErrorAction SilentlyContinue
  return ($text -and $text.Contains('PACKAGE_VERSION="2026.06.08.2"'))
}

function Download-Installer([string]$OutFile) {
  foreach ($base in (Get-InstallerBaseUrls)) {
    if ([string]::IsNullOrWhiteSpace($base)) { continue }
    $url = if ($base.EndsWith("/install.sh")) { $base } else { "$($base.TrimEnd('/'))/install.sh" }
    try {
      Invoke-DownloadWithSources -Urls @($url) -OutFile $OutFile -Label "中文增强安装器" | Out-Null
      if (-not (Test-BashInstaller -Path $OutFile)) {
        throw "当前入口返回的不是 Bash 安装脚本。"
      }
      if ($base.EndsWith("/install.sh")) {
        return ($base.Substring(0, $base.Length - "/install.sh".Length)).TrimEnd("/")
      }
      return $base.TrimEnd("/")
    } catch {
      Write-Step "当前入口不可用或过慢，正在切换下一个入口。"
    }
  }
  throw "中文增强安装器下载失败，请稍后重试。"
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
  $activeBaseUrl = Download-Installer -OutFile $installer

  $env:XIAOMA_HERMES_PLATFORM = "windows"
  $env:XIAOMA_HERMES_ENTRYPOINT = "windows-powershell"
  $env:XIAOMA_HERMES_BASE_URL = $activeBaseUrl
  $env:HERMES_HOME = Convert-ToBashPath -Path (Get-HermesHomePath) -BashPath $bash

  Write-Step "开始应用中文增强。"
  & $bash $installer
  if ($LASTEXITCODE -ne 0) {
    throw "中文增强安装失败，退出码 $LASTEXITCODE。"
  }

  New-HermesDesktopShortcut
  Write-Step "完成。重新打开 Hermes 后检查中文界面。"
} finally {
  Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
}
