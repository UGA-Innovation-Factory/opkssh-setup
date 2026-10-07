# Windows Client Setup

The Windows setup uses one batch file. It does not use PowerShell or need administrator access.

## Requirements

- Windows OpenSSH Client
- winget for automatic OPKSSH installation

Run `ssh -V` to check for OpenSSH. Use Windows Optional Features if the command is missing.

The script checks for winget before it tries to install OPKSSH. Install App Installer from your approved software portal if winget is missing.

## Run the Setup

Open Command Prompt in the repository directory. Run:

```cmd
client_setup.bat
```

The script installs OPKSSH for the current user in this directory:

```text
%LOCALAPPDATA%\opkssh\bin
```

The script does not write the executable to Program Files or another machine-wide directory.

The winget command uses these options:

```text
--scope user
--location "%LOCALAPPDATA%\opkssh\bin"
--accept-source-agreements
--accept-package-agreements
--disable-interactivity
--force
```

The agreement options support computers that have not used winget before.

## Configuration Files

The script writes the OPKSSH client configuration here:

```text
%APPDATA%\.opk\config.yml
```

Current OPKSSH versions use this Windows client configuration path.

The script writes the SSH client configuration here:

```text
%USERPROFILE%\.ssh\config
```

Both paths belong to the current user. The script does not change machine-wide access control lists.

## Options

Show all options:

```cmd
client_setup.bat --help
```

Set both remote user names:

```cmd
client_setup.bat --linux-user jdoe
```

Set the bastion and internal host pattern:

```cmd
client_setup.bat --factory-host factory.example.com --factory-alias bastion --internal-pattern "*.lab.internal"
```

Skip the SSH configuration update:

```cmd
client_setup.bat --no-ssh-config
```

## Use OPKSSH

Run the path that the setup output shows. The default path is:

```cmd
"%LOCALAPPDATA%\opkssh\bin\opkssh.exe" login uga
ssh factory
```

winget can also add OPKSSH to the user PATH. Open a new Command Prompt before you run `opkssh` by name.

## winget Is Missing

The script stops with an error if winget is unavailable. It still creates the OPKSSH and SSH configuration files.

Install winget from this Microsoft page:

```text
https://aka.ms/winget-install
```

You can also download `opkssh.exe` from the official releases page. Put the file in `%LOCALAPPDATA%\opkssh\bin`.

```text
https://github.com/openpubkey/opkssh/releases
```

## OpenSSH Is Missing

Open Windows Settings. Go to Apps, Optional Features, and install OpenSSH Client.

Open a new Command Prompt after the installation. Run `ssh -V` to check it.
