@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Hermes 中文增强安装器

set "XIAOMA_HERMES_CMD_DIR=%~dp0"
set "BASE_URL=%XIAOMA_HERMES_BASE_URL%"
if "%BASE_URL%"=="" set "BASE_URL=https://useai.live/hermes"
set "FALLBACK_BASE_URL=%XIAOMA_HERMES_FALLBACK_BASE_URL%"
if "%FALLBACK_BASE_URL%"=="" set "FALLBACK_BASE_URL=https://cdn.jsdelivr.net/gh/fresh-claw/hermes-cn@v2026.06.05.2"
set "XIAOMA_HERMES_BASE_URL=%BASE_URL%"
set "XIAOMA_HERMES_FALLBACK_BASE_URL=%FALLBACK_BASE_URL%"

set "LAUNCHER=%TEMP%\xiaoma-hermes-windows-launcher.ps1"
break > "%LAUNCHER%"
>> "%LAUNCHER%" echo $ErrorActionPreference = 'Stop'
>> "%LAUNCHER%" echo try { [Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8 } catch { }
>> "%LAUNCHER%" echo $Host.UI.RawUI.WindowTitle = 'Hermes 中文增强安装器'
>> "%LAUNCHER%" echo $base = $env:XIAOMA_HERMES_BASE_URL
>> "%LAUNCHER%" echo if ([string]::IsNullOrWhiteSpace($base)) { $base = 'https://useai.live/hermes' }
>> "%LAUNCHER%" echo $fallback = $env:XIAOMA_HERMES_FALLBACK_BASE_URL
>> "%LAUNCHER%" echo if ([string]::IsNullOrWhiteSpace($fallback)) { $fallback = 'https://cdn.jsdelivr.net/gh/fresh-claw/hermes-cn@v2026.06.05.2' }
>> "%LAUNCHER%" echo $cmdDir = $env:XIAOMA_HERMES_CMD_DIR
>> "%LAUNCHER%" echo $localPs1 = Join-Path $cmdDir 'install.ps1'
>> "%LAUNCHER%" echo function Pause-Hermes { Write-Host ''; Read-Host '按回车关闭窗口' ^| Out-Null }
>> "%LAUNCHER%" echo Write-Host 'Hermes 中文增强安装器'
>> "%LAUNCHER%" echo Write-Host ''
>> "%LAUNCHER%" echo Write-Host '将安装官方桌面端并应用中文增强。'
>> "%LAUNCHER%" echo Write-Host ''
>> "%LAUNCHER%" echo try {
>> "%LAUNCHER%" echo   if (Test-Path $localPs1) {
>> "%LAUNCHER%" echo     ^& powershell -NoProfile -ExecutionPolicy Bypass -File $localPs1 -BaseUrl $base -FallbackBaseUrl $fallback
>> "%LAUNCHER%" echo   } else {
>> "%LAUNCHER%" echo     $tmp = Join-Path $env:TEMP 'xiaoma-hermes-install.ps1'
>> "%LAUNCHER%" echo     try {
>> "%LAUNCHER%" echo       Invoke-WebRequest -UseBasicParsing ($base.TrimEnd('/') + '/install.ps1') -OutFile $tmp
>> "%LAUNCHER%" echo       ^& powershell -NoProfile -ExecutionPolicy Bypass -File $tmp -BaseUrl $base -FallbackBaseUrl $fallback
>> "%LAUNCHER%" echo     } catch {
>> "%LAUNCHER%" echo       Write-Host '网站下载受限，改用备用入口。'
>> "%LAUNCHER%" echo       Invoke-WebRequest -UseBasicParsing ($fallback.TrimEnd('/') + '/install.ps1') -OutFile $tmp
>> "%LAUNCHER%" echo       ^& powershell -NoProfile -ExecutionPolicy Bypass -File $tmp -BaseUrl $fallback -FallbackBaseUrl $fallback
>> "%LAUNCHER%" echo     }
>> "%LAUNCHER%" echo   }
>> "%LAUNCHER%" echo   if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "安装器退出码: $LASTEXITCODE" }
>> "%LAUNCHER%" echo   Write-Host ''
>> "%LAUNCHER%" echo   Write-Host '完成。请重新打开 Hermes。'
>> "%LAUNCHER%" echo   Pause-Hermes
>> "%LAUNCHER%" echo } catch {
>> "%LAUNCHER%" echo   Write-Host ''
>> "%LAUNCHER%" echo   Write-Host '安装失败。请把这个窗口截图发给小马。' -ForegroundColor Yellow
>> "%LAUNCHER%" echo   Write-Host $_
>> "%LAUNCHER%" echo   Pause-Hermes
>> "%LAUNCHER%" echo   exit 1
>> "%LAUNCHER%" echo }

powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File "%LAUNCHER%"
