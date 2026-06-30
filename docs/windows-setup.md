# Windows Client Setup Guide

This guide provides Windows-specific instructions for setting up OPKSSH for UGA Manufacturing Living Labs.

## Prerequisites

1. **PowerShell 5.1 or later** (included with Windows 10/11)
2. **OpenSSH Client** (included with Windows 10 1809+ and Windows 11)
   - To check: `ssh -V` in PowerShell or Command Prompt
   - If not installed, enable via: Settings → Apps → Optional Features → OpenSSH Client
3. **OPKSSH binary** for Windows
   - The setup script will attempt to install it automatically using winget if not found
   - Manual installation: Download from https://github.com/openpubkey/opkssh
   - Place `opkssh.exe` in your PATH (e.g., `C:\Program Files\opkssh\` or `C:\Users\<username>\bin\`)
4. **winget (Windows Package Manager)** - Optional but recommended
   - Included with Windows 11 and recent Windows 10 versions
   - Used for automatic opkssh installation
   - If not available: https://aka.ms/winget-install

## Running the Setup Script

### Option 1: PowerShell (Recommended)

Open PowerShell and navigate to the repository directory:

```powershell
cd path\to\opkssh-setup
.\client_setup.ps1
```

If you get an execution policy error, you can bypass it for this session:

```powershell
powershell -ExecutionPolicy Bypass -File .\client_setup.ps1
```

### Option 2: Command Prompt

Open Command Prompt and navigate to the repository directory:

```cmd
cd path\to\opkssh-setup
client_setup.bat
```

## Configuration Files

The setup script creates:

- **OPKSSH config**: `%USERPROFILE%\.opk\config.yml`
  - Typically: `C:\Users\<username>\.opk\config.yml`
- **SSH config**: `%USERPROFILE%\.ssh\config`
  - Typically: `C:\Users\<username>\.ssh\config`

Both files are created with restrictive permissions (accessible only by your Windows user account).

## Common Customization Options

### Setting Your Linux Username

If your Windows username differs from your Linux username on the remote hosts:

```powershell
.\client_setup.ps1 -LinuxUser jdoe
```

### Custom Bastion Host

```powershell
.\client_setup.ps1 -FactoryHost custom-bastion.example.com -FactoryAlias bastion
```

### Custom Internal Host Pattern

```powershell
.\client_setup.ps1 -InternalPattern "*.lab.internal"
```

### Skip SSH Config Update

To only create the OPKSSH config without modifying SSH config:

```powershell
.\client_setup.ps1 -NoSshConfig
```

## Using OPKSSH After Setup

1. **Login to the UGA provider:**
   ```powershell
   opkssh login uga
   ```
   This will open your browser for authentication via UGA Entra ID.

2. **Connect to the bastion:**
   ```powershell
   ssh factory
   ```

3. **Connect to internal hosts via ProxyJump:**
   ```powershell
   ssh dev@cnc-controller-01.lab
   ```
   Or explicitly:
   ```powershell
   ssh -J factory dev@cnc-controller-01.lab
   ```

## Troubleshooting

### SSH Client Not Found

If `ssh` is not recognized:

1. Open Settings → Apps → Optional Features
2. Click "Add a feature"
3. Search for "OpenSSH Client"
4. Install it
5. Restart PowerShell/Command Prompt

### OPKSSH Not Found

The setup script will automatically attempt to install opkssh using winget if it's not found on your PATH.

**If automatic installation succeeds:**
- Restart your PowerShell/Command Prompt window to refresh the PATH
- Run `opkssh login uga` to begin using it

**If automatic installation fails or winget is not available:**

Ensure `opkssh.exe` is in a directory listed in your PATH:

1. Download opkssh from the official repository: https://github.com/openpubkey/opkssh/releases
2. Place it in a directory like `C:\Program Files\opkssh\`
3. Add that directory to your PATH:
   - Settings → System → About → Advanced system settings
   - Environment Variables → System variables → Path → Edit
   - New → Add the directory path → OK

Or place it in an existing PATH directory like:
- `C:\Windows\System32\` (requires admin rights)
- `C:\Users\<username>\bin\` (create this directory and add it to your user PATH)

**Installing winget:**

If you don't have winget and want automatic installation support:
- Download from: https://aka.ms/winget-install
- Or install "App Installer" from Microsoft Store

### Permission Denied Errors

If you encounter permission errors when SSH tries to use the config files:

1. Check that `%USERPROFILE%\.ssh\config` exists
2. Verify file permissions (should be readable only by you)
3. Try running PowerShell as Administrator when running the setup script

### ProxyJump Not Working

Ensure you're using OpenSSH 7.3 or later:

```powershell
ssh -V
```

Older versions may require using `-o ProxyCommand` instead of `-J`.

### Certificate/Key Issues

If OPKSSH fails to generate or use certificates:

1. Ensure `%USERPROFILE%\.ssh` directory exists with proper permissions
2. Check that `opkssh login uga` completed successfully
3. Verify the certificate with: `opkssh whoami`

### Windows Defender Firewall

If connections fail, ensure Windows Firewall allows outbound SSH connections (port 22). This is usually allowed by default.

## Differences from Linux/macOS Version

The PowerShell script (`client_setup.ps1`) provides equivalent functionality to the bash script (`client_setup`):

- Uses Windows paths (`%USERPROFILE%` instead of `$HOME`)
- Uses Windows ACLs for file permissions (instead of chmod)
- Uses PowerShell parameter syntax (`-Parameter Value` instead of `--parameter value`)
- Supports both PowerShell and Command Prompt execution (via `.bat` wrapper)

## Getting Help

View all available options:

```powershell
Get-Help .\client_setup.ps1 -Detailed
```

Or:

```powershell
.\client_setup.ps1 -Help
```

## Advanced: Using WSL (Windows Subsystem for Linux)

If you have WSL installed, you can alternatively use the bash version:

```bash
wsl
cd /mnt/c/path/to/opkssh-setup
./client_setup
```

Note: WSL uses a separate SSH configuration from native Windows SSH. Certificates and configs from the PowerShell setup won't be accessible in WSL and vice versa unless you manually configure file sharing.
