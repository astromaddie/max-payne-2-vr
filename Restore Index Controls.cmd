@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bindings\Fix-Index-Controls.ps1" -Restore > "%~dp0Index Controls Restore.log" 2>&1
set "mp2vrIndexExit=%errorlevel%"
type "%~dp0Index Controls Restore.log"
if not "%mp2vrIndexExit%"=="0" echo Could not complete. Please send Index Controls Restore.log.
pause
exit /b %mp2vrIndexExit%
