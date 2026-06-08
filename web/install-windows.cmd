@echo off
setlocal
chcp 65001 >nul
title Hermes 中文增强安装器

set "BASE_URL=%XIAOMA_HERMES_BASE_URL%"
if "%BASE_URL%"=="" set "BASE_URL=http://47.121.138.43/hermes"
set "FALLBACK_BASE_URL=%XIAOMA_HERMES_FALLBACK_BASE_URL%"
if "%FALLBACK_BASE_URL%"=="" set "FALLBACK_BASE_URL=https://cdn.jsdelivr.net/gh/fresh-claw/hermes-cn@v2026.06.08.1"
set "XIAOMA_HERMES_BASE_URL=%BASE_URL%"
set "XIAOMA_HERMES_FALLBACK_BASE_URL=%FALLBACK_BASE_URL%"

echo Hermes 中文增强安装器
echo.
echo 将安装官方桌面端并应用中文增强。
echo.

set "LOCAL_PS1=%~dp0install.ps1"
if exist "%LOCAL_PS1%" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCAL_PS1%" -BaseUrl "%BASE_URL%" -FallbackBaseUrl "%FALLBACK_BASE_URL%"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $base=$env:XIAOMA_HERMES_BASE_URL; $fallback=$env:XIAOMA_HERMES_FALLBACK_BASE_URL; $tmp=Join-Path $env:TEMP 'xiaoma-hermes-install.ps1'; try { Invoke-WebRequest -UseBasicParsing ($base.TrimEnd('/') + '/install.ps1') -OutFile $tmp; & powershell -NoProfile -ExecutionPolicy Bypass -File $tmp -BaseUrl $base -FallbackBaseUrl $fallback } catch { Invoke-WebRequest -UseBasicParsing ($fallback.TrimEnd('/') + '/install.ps1') -OutFile $tmp; & powershell -NoProfile -ExecutionPolicy Bypass -File $tmp -BaseUrl $fallback -FallbackBaseUrl $fallback }"
)

if errorlevel 1 (
  echo.
  echo 安装失败。请把上方报错截图发给小马。
  pause
  exit /b 1
)

echo.
echo 完成。请重新打开 Hermes。
pause
