@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Gestisci-traduzione.ps1" -Action Install %*
set "_qd_exit=%errorlevel%"
echo.
pause
exit /b %_qd_exit%
