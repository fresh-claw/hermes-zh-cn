@echo off
setlocal
title Hermes 中文增强 Windows 验证
set "BASE_URL=https://useai.live/hermes"
set "SCRIPT=%TEMP%\xiaoma-hermes-verify-windows.ps1"

echo Hermes 中文增强 Windows 验证
echo.
echo 正在下载验证脚本...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%BASE_URL%/scripts/verify-windows.ps1' -OutFile '%SCRIPT%'"
if errorlevel 1 (
  echo.
  echo 下载验证脚本失败。
  pause
  exit /b 1
)

echo.
echo 正在运行验证...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -BaseUrl "%BASE_URL%"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" (
  echo 验证通过。
) else (
  echo 验证失败，退出码：%EXIT_CODE%
)
echo.
pause
exit /b %EXIT_CODE%
