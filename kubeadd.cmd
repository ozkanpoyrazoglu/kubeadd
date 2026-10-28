@echo off
rem Windows launcher for kubeadd.py (works from cmd.exe and PowerShell).
setlocal
where py >nul 2>&1
if %ERRORLEVEL%==0 (
    py -3 "%~dp0kubeadd.py" %*
) else (
    python "%~dp0kubeadd.py" %*
)
exit /b %ERRORLEVEL%
