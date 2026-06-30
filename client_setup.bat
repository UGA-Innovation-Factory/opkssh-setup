@echo off
REM UGA Manufacturing Living Labs OPKSSH client setup launcher for Windows
REM This batch file launches the PowerShell script with appropriate parameters

setlocal enabledelayedexpansion

REM Check PowerShell availability
where powershell >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: PowerShell not found. Please install PowerShell 5.1 or later.
    exit /b 1
)

REM Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"

REM Launch PowerShell script with all arguments passed through
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%client_setup.ps1" %*

exit /b %ERRORLEVEL%
