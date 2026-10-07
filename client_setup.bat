@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "FACTORY_HOST=factory.uga.edu"
set "FACTORY_ALIAS=factory"
set "FACTORY_USER=factory"
set "INTERNAL_PATTERN=*.factory.internal"
set "REMOTE_USER=%USERNAME%"
set "SERVER_ALIVE_INTERVAL=20"
set "SERVER_ALIVE_COUNT_MAX=6"
set "UPDATE_SSH_CONFIG=1"
set "OPKSSH_HOME=%LOCALAPPDATA%\opkssh"
set "OPKSSH_BIN=%OPKSSH_HOME%\bin"
set "OPKSSH_EXE=%OPKSSH_BIN%\opkssh.exe"
set "CONFIG_DIR=%APPDATA%\.opk"
set "CONFIG_FILE=%CONFIG_DIR%\config.yml"
set "SSH_DIR=%USERPROFILE%\.ssh"
set "SSH_CONFIG=%SSH_DIR%\config"

:parse_args
if "%~1"=="" goto setup
if /I "%~1"=="--help" goto help
if /I "%~1"=="-h" goto help
if /I "%~1"=="--no-ssh-config" (
    set "UPDATE_SSH_CONFIG=0"
    shift
    goto parse_args
)
if /I "%~1"=="--factory-host" (
    set "OPTION=FACTORY_HOST"
    goto read_value
)
if /I "%~1"=="--factory-alias" (
    set "OPTION=FACTORY_ALIAS"
    goto read_value
)
if /I "%~1"=="--factory-user" (
    set "OPTION=FACTORY_USER"
    goto read_value
)
if /I "%~1"=="--internal-pattern" (
    set "OPTION=INTERNAL_PATTERN"
    goto read_value
)
if /I "%~1"=="--remote-user" (
    set "OPTION=REMOTE_USER"
    goto read_value
)
if /I "%~1"=="--server-alive-interval" (
    set "OPTION=SERVER_ALIVE_INTERVAL"
    goto read_value
)
if /I "%~1"=="--server-alive-count" (
    set "OPTION=SERVER_ALIVE_COUNT_MAX"
    goto read_value
)
if /I "%~1"=="--linux-user" goto read_linux_user
echo ERROR: Unknown argument: %~1
echo.
goto help_error

:read_value
if "%~2"=="" (
    echo ERROR: %~1 requires a value.
    exit /b 1
)
set "%OPTION%=%~2"
shift
shift
goto parse_args

:read_linux_user
if "%~2"=="" (
    echo ERROR: %~1 requires a value.
    exit /b 1
)
set "FACTORY_USER=%~2"
set "REMOTE_USER=%~2"
shift
shift
goto parse_args

:setup
echo ==^> Creating the OPKSSH client configuration
if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%" 2>nul
if not exist "%CONFIG_DIR%\" (
    echo ERROR: Could not create "%CONFIG_DIR%".
    exit /b 1
)
if exist "%CONFIG_FILE%" (
    copy /Y "%CONFIG_FILE%" "%CONFIG_FILE%.backup" >nul
    echo WARN: Existing configuration backed up to "%CONFIG_FILE%.backup".
)
call :write_opkssh_config || exit /b 1
echo OK: Wrote "%CONFIG_FILE%".
if "%UPDATE_SSH_CONFIG%"=="1" (
    call :write_ssh_config
    if errorlevel 1 exit /b 1
)

call :find_opkssh
if defined FOUND_OPKSSH goto complete
echo ==^> OPKSSH is not installed. Checking for winget
where winget.exe >nul 2>&1
if errorlevel 1 goto no_winget
if not exist "%OPKSSH_BIN%" mkdir "%OPKSSH_BIN%" 2>nul
if not exist "%OPKSSH_BIN%\" (
    echo ERROR: Could not create "%OPKSSH_BIN%".
    exit /b 1
)

echo ==^> Installing OPKSSH for this user in "%OPKSSH_BIN%"
winget install --id OpenPubKey.opkssh --exact --source winget --scope user --location "%OPKSSH_BIN%" --accept-source-agreements --accept-package-agreements --disable-interactivity --force
if errorlevel 1 (
    echo ERROR: winget could not install OPKSSH.
    echo The configuration files were created successfully.
    exit /b 1
)
call :find_opkssh
if not defined FOUND_OPKSSH if exist "%OPKSSH_EXE%" set "FOUND_OPKSSH=%OPKSSH_EXE%"
if not defined FOUND_OPKSSH (
    echo ERROR: winget completed, but opkssh.exe was not found.
    exit /b 1
)
goto complete

:no_winget
echo ERROR: winget is not available on this computer.
echo Install App Installer from your organization's approved software portal,
echo or download OPKSSH manually into "%OPKSSH_BIN%".
echo https://aka.ms/winget-install
echo https://github.com/openpubkey/opkssh/releases
exit /b 1

:complete
echo.
echo Setup complete.
echo OPKSSH: %FOUND_OPKSSH%
echo.
echo Next step:
echo   "%FOUND_OPKSSH%" login uga
echo.
echo Example jump usage:
echo   ssh -J %FACTORY_ALIAS% %REMOTE_USER%@internal-host
echo   ssh %REMOTE_USER%@^<host matching %INTERNAL_PATTERN%^>
exit /b 0

:find_opkssh
set "FOUND_OPKSSH="
if exist "%OPKSSH_EXE%" (
    set "FOUND_OPKSSH=%OPKSSH_EXE%"
    exit /b 0
)
if exist "%OPKSSH_BIN%\" for /R "%OPKSSH_BIN%" %%I in (opkssh.exe) do if not defined FOUND_OPKSSH set "FOUND_OPKSSH=%%~fI"
exit /b 0

:write_opkssh_config
>"%CONFIG_FILE%" (
    echo ---
    echo default_provider: uga
    echo providers:
    echo   - alias: uga
    echo     issuer: https://login.microsoftonline.com/a8216c1e-4d63-4352-8c3b-50fa1f1475b1/v2.0
    echo     client_id: 7f331a0a-da1a-4e13-8df0-e9baba02ed86
    echo     scopes: openid profile email offline_access
    echo     access_type: offline
    echo     prompt: consent
    echo     redirect_uris:
    echo       - http://localhost:3000/login-callback
    echo       - http://localhost:10001/login-callback
    echo       - http://localhost:11110/login-callback
)
exit /b %ERRORLEVEL%

:write_ssh_config
echo ==^> Configuring SSH ProxyJump entries
if not exist "%SSH_DIR%" mkdir "%SSH_DIR%" 2>nul
if not exist "%SSH_DIR%\" (
    echo ERROR: Could not create "%SSH_DIR%".
    exit /b 1
)
set "SSH_TEMP=%TEMP%\opkssh-ssh-config-%RANDOM%-%RANDOM%.tmp"
if exist "%SSH_CONFIG%" (call :remove_managed_ssh_section "%SSH_CONFIG%" "%SSH_TEMP%") else (type nul >"%SSH_TEMP%")
if errorlevel 1 exit /b 1
>>"%SSH_TEMP%" echo # ^>^>^> UGA Manufacturing Living Labs OPKSSH
>>"%SSH_TEMP%" echo Host %FACTORY_ALIAS%
>>"%SSH_TEMP%" echo   HostName %FACTORY_HOST%
>>"%SSH_TEMP%" echo   User %FACTORY_USER%
>>"%SSH_TEMP%" echo   IdentitiesOnly yes
>>"%SSH_TEMP%" echo   IdentityFile ~/.ssh/id_ecdsa
>>"%SSH_TEMP%" echo   PreferredAuthentications publickey
>>"%SSH_TEMP%" echo   PubkeyAuthentication yes
>>"%SSH_TEMP%" echo   PasswordAuthentication no
>>"%SSH_TEMP%" echo   KbdInteractiveAuthentication no
>>"%SSH_TEMP%" echo   BatchMode yes
>>"%SSH_TEMP%" echo   ServerAliveInterval %SERVER_ALIVE_INTERVAL%
>>"%SSH_TEMP%" echo   ServerAliveCountMax %SERVER_ALIVE_COUNT_MAX%
>>"%SSH_TEMP%" echo.
>>"%SSH_TEMP%" echo Host %INTERNAL_PATTERN%
>>"%SSH_TEMP%" echo   User %REMOTE_USER%
>>"%SSH_TEMP%" echo   ProxyJump %FACTORY_ALIAS%
>>"%SSH_TEMP%" echo   IdentitiesOnly yes
>>"%SSH_TEMP%" echo   IdentityFile ~/.ssh/id_ecdsa
>>"%SSH_TEMP%" echo   PreferredAuthentications publickey
>>"%SSH_TEMP%" echo   PubkeyAuthentication yes
>>"%SSH_TEMP%" echo   PasswordAuthentication no
>>"%SSH_TEMP%" echo   KbdInteractiveAuthentication no
>>"%SSH_TEMP%" echo   BatchMode yes
>>"%SSH_TEMP%" echo   ServerAliveInterval %SERVER_ALIVE_INTERVAL%
>>"%SSH_TEMP%" echo   ServerAliveCountMax %SERVER_ALIVE_COUNT_MAX%
>>"%SSH_TEMP%" echo # ^<^<^< UGA Manufacturing Living Labs OPKSSH
move /Y "%SSH_TEMP%" "%SSH_CONFIG%" >nul
if errorlevel 1 (
    echo ERROR: Could not update "%SSH_CONFIG%".
    exit /b 1
)
echo OK: Updated "%SSH_CONFIG%".
exit /b 0

:remove_managed_ssh_section
setlocal EnableDelayedExpansion
set "SKIP=0"
>"%~2" (
    for /F "usebackq delims=" %%L in (`findstr /N "^" "%~1"`) do (
        set "LINE=%%L"
        set "LINE=!LINE:*:=!"
        if "!LINE!"=="# >>> UGA Manufacturing Living Labs OPKSSH" set "SKIP=1"
        if "!SKIP!"=="0" echo(!LINE!
        if "!LINE!"=="# <<< UGA Manufacturing Living Labs OPKSSH" set "SKIP=0"
    )
)
endlocal
exit /b 0

:help
echo Usage: %~nx0 [options]
echo.
echo Options:
echo   --factory-host HOST       Public SSH bastion host
echo   --factory-alias ALIAS     Local SSH alias for the bastion
echo   --factory-user USER       Remote user for the bastion
echo   --internal-pattern GLOB   Hosts reached through ProxyJump
echo   --remote-user USER        Remote user for internal hosts
echo   --linux-user USER         Set both remote usernames
echo   --server-alive-interval N Seconds between client keepalives
echo   --server-alive-count N    Missed keepalives before disconnect
echo   --no-ssh-config           Only write the OPKSSH config
echo   -h, --help                Show this help message
exit /b 0

:help_error
call :help
exit /b 1
