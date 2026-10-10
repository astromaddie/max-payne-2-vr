@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bindings\Fix-Index-Controls.ps1" > "%~dp0Index Grip Restore.log" 2>&1
set "mp2vrGripExit=%errorlevel%"
type "%~dp0Index Grip Restore.log"
if not "%mp2vrGripExit%"=="0" echo Could not complete. Please send the log shown above.
echo.
pause
exit /b %mp2vrGripExit%
