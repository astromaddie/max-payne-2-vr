@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bindings\Test-Index-Grip.ps1" > "%~dp0Index Grip Test.log" 2>&1
set "mp2vrGripExit=%errorlevel%"
type "%~dp0Index Grip Test.log"
if not "%mp2vrGripExit%"=="0" echo Could not complete. Please send the log shown above.
echo.
pause
exit /b %mp2vrGripExit%
