@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bindings\Fix-Index-Controls.ps1" > "%~dp0Index Controls Fix.log" 2>&1
set "mp2vrIndexExit=%errorlevel%"
type "%~dp0Index Controls Fix.log"
if not "%mp2vrIndexExit%"=="0" (
  echo.
    echo The fix could not complete. Please send Index Controls Fix.log.
)
pause
exit /b %mp2vrIndexExit%
