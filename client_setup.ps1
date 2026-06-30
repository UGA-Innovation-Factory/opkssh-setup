#Requires -Version 5.1

<#
.SYNOPSIS
    UGA Manufacturing Living Labs OPKSSH client setup for Windows
.DESCRIPTION
    Creates OPKSSH configuration and optionally updates SSH config with ProxyJump entries
.PARAMETER FactoryHost
    Public SSH bastion host (default: factory.uga.edu)
.PARAMETER FactoryAlias
    Local SSH alias for the bastion (default: factory)
.PARAMETER FactoryUser
    Remote user for the bastion (default: factory)
.PARAMETER InternalPattern
    Hosts reached through ProxyJump (default: *.factory.internal)
.PARAMETER RemoteUser
    Remote user for internal hosts (default: current username)
.PARAMETER LinuxUser
    Set both factory and internal remote users
.PARAMETER ServerAliveInterval
    Seconds between client keepalives (default: 20)
.PARAMETER ServerAliveCountMax
    Missed keepalives before disconnect (default: 6)
.PARAMETER NoSshConfig
    Only write OPKSSH config; skip SSH config update
.PARAMETER Help
    Show help message
.EXAMPLE
    .\client_setup.ps1
.EXAMPLE
    .\client_setup.ps1 -LinuxUser jdoe -FactoryHost factory.example.com
#>

[CmdletBinding()]
param(
    [string]$FactoryHost = "factory.uga.edu",
    [string]$FactoryAlias = "factory",
    [string]$FactoryUser = "factory",
    [string]$InternalPattern = "*.factory.internal",
    [string]$RemoteUser = $env:USERNAME,
    [string]$LinuxUser,
    [int]$ServerAliveInterval = 20,
    [int]$ServerAliveCountMax = 6,
    [switch]$NoSshConfig,
    [switch]$Help
)

# Color output functions
function Write-Info {
    param([string]$Message)
    Write-Host "==> " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "OK: " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warning {
    param([string]$Message)
    Write-Host "WARN: " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "ERROR: " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

# Show help if requested
if ($Help) {
    Get-Help $PSCommandPath -Detailed
    exit 0
}

# Handle LinuxUser parameter
if ($LinuxUser) {
    $FactoryUser = $LinuxUser
    $RemoteUser = $LinuxUser
}

# Set up paths using USERPROFILE (Windows equivalent of HOME)
$ConfigDir = Join-Path $env:USERPROFILE ".opk"
$ConfigFile = Join-Path $ConfigDir "config.yml"
$SshDir = Join-Path $env:USERPROFILE ".ssh"
$SshConfig = Join-Path $SshDir "config"

# Create config directory
Write-Info "Creating OPKSSH config directory"
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

# Set restrictive permissions on config directory (Windows equivalent of chmod 700)
$acl = Get-Acl $ConfigDir
$acl.SetAccessRuleProtection($true, $false)
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
    "FullControl",
    "ContainerInherit,ObjectInherit",
    "None",
    "Allow"
)
$acl.SetAccessRule($accessRule)
Set-Acl -Path $ConfigDir -AclObject $acl

Write-Success "Config directory ready: $ConfigDir"

# Backup existing config if present
if (Test-Path $ConfigFile) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupFile = "$ConfigFile.backup.$timestamp"
    Write-Warning "Existing config found. Backing it up to:"
    Write-Host "     $backupFile"
    Copy-Item $ConfigFile $backupFile
}

# Write OPKSSH config
Write-Info "Writing UGA ArchPass OPKSSH config"

$configContent = @"
---
default_provider: uga
providers:
  - alias: uga
    issuer: https://login.microsoftonline.com/a8216c1e-4d63-4352-8c3b-50fa1f1475b1/v2.0
    client_id: 7f331a0a-da1a-4e13-8df0-e9baba02ed86
    scopes: openid profile email offline_access
    access_type: offline
    prompt: consent
    redirect_uris:
      - http://localhost:3000/login-callback
      - http://localhost:10001/login-callback
      - http://localhost:11110/login-callback
"@

Set-Content -Path $ConfigFile -Value $configContent -Encoding UTF8

# Set restrictive permissions on config file (Windows equivalent of chmod 600)
$acl = Get-Acl $ConfigFile
$acl.SetAccessRuleProtection($true, $false)
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
    "FullControl",
    "None",
    "None",
    "Allow"
)
$acl.SetAccessRule($accessRule)
Set-Acl -Path $ConfigFile -AclObject $acl

Write-Success "Wrote config: $ConfigFile"

# Update SSH config if requested
if (-not $NoSshConfig) {
    Write-Info "Configuring SSH ProxyJump entries"
    
    # Create SSH directory if it doesn't exist
    if (-not (Test-Path $SshDir)) {
        New-Item -ItemType Directory -Path $SshDir -Force | Out-Null
    }
    
    # Set restrictive permissions on SSH directory
    $acl = Get-Acl $SshDir
    $acl.SetAccessRuleProtection($true, $false)
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )
    $acl.SetAccessRule($accessRule)
    Set-Acl -Path $SshDir -AclObject $acl
    
    # Create SSH config if it doesn't exist
    if (-not (Test-Path $SshConfig)) {
        New-Item -ItemType File -Path $SshConfig -Force | Out-Null
    }
    
    # Set restrictive permissions on SSH config
    $acl = Get-Acl $SshConfig
    $acl.SetAccessRuleProtection($true, $false)
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
        "FullControl",
        "None",
        "None",
        "Allow"
    )
    $acl.SetAccessRule($accessRule)
    Set-Acl -Path $SshConfig -AclObject $acl
    
    # Define markers for our section
    $startMarker = "# >>> UGA Manufacturing Living Labs OPKSSH"
    $endMarker = "# <<< UGA Manufacturing Living Labs OPKSSH"
    
    # Read existing config
    $existingContent = if (Test-Path $SshConfig) {
        Get-Content $SshConfig -Raw
    } else {
        ""
    }
    
    # Remove old OPKSSH section if present
    if ($existingContent -match [regex]::Escape($startMarker)) {
        $pattern = "(?s)$([regex]::Escape($startMarker)).*?$([regex]::Escape($endMarker))\r?\n?"
        $existingContent = $existingContent -replace $pattern, ""
    }
    
    # Build new SSH config section
    $sshConfigSection = @"
$startMarker
Host $FactoryAlias
  HostName $FactoryHost
  User $FactoryUser
  IdentitiesOnly yes
  IdentityFile ~/.ssh/id_ecdsa
  PreferredAuthentications publickey
  PubkeyAuthentication yes
  PasswordAuthentication no
  KbdInteractiveAuthentication no
  BatchMode yes
  ServerAliveInterval $ServerAliveInterval
  ServerAliveCountMax $ServerAliveCountMax

Host $InternalPattern
  User $RemoteUser
  ProxyJump $FactoryAlias
  IdentitiesOnly yes
  IdentityFile ~/.ssh/id_ecdsa
  PreferredAuthentications publickey
  PubkeyAuthentication yes
  PasswordAuthentication no
  KbdInteractiveAuthentication no
  BatchMode yes
  ServerAliveInterval $ServerAliveInterval
  ServerAliveCountMax $ServerAliveCountMax
$endMarker
"@
    
    # Combine content
    $newContent = if ($existingContent.Trim()) {
        $existingContent.TrimEnd() + "`n`n" + $sshConfigSection
    } else {
        $sshConfigSection
    }
    
    Set-Content -Path $SshConfig -Value $newContent -Encoding UTF8 -NoNewline
    
    Write-Success "Updated SSH config: $SshConfig"
}

# Check for opkssh on PATH
Write-Info "Checking for opkssh on PATH"

$opksshPath = Get-Command opkssh -ErrorAction SilentlyContinue

if ($opksshPath) {
    Write-Success "Found opkssh: $($opksshPath.Source)"
    
    Write-Host ""
    Write-Host "Setup complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next step:"
    Write-Host "  opkssh login uga"
    Write-Host ""
    Write-Host "Example jump usage:"
    Write-Host "  ssh -J $FactoryAlias $RemoteUser@internal-host"
    Write-Host "  ssh $RemoteUser@<host matching $InternalPattern>"
} else {
    Write-Warning "opkssh was not found on your PATH."
    
    # Try to install with winget
    $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
    
    if ($wingetPath) {
        Write-Info "Attempting to install opkssh using winget..."
        
        try {
            # Search for opkssh package
            $searchResult = winget search opkssh 2>&1
            
            if ($LASTEXITCODE -eq 0 -and $searchResult -match "opkssh") {
                Write-Host "Found opkssh in winget repository. Installing..."
                
                # Install opkssh
                winget install opkssh --accept-source-agreements --accept-package-agreements
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "opkssh installed successfully!"
                    Write-Host ""
                    Write-Host "Please restart your terminal to refresh your PATH, then run:" -ForegroundColor Yellow
                    Write-Host "  opkssh login uga"
                    Write-Host ""
                    Write-Host "Setup complete." -ForegroundColor Green
                } else {
                    Write-Warning "winget install command failed."
                    Write-Host ""
                    Write-Host "Install OPKSSH manually:" -ForegroundColor Cyan
                    Write-Host "  https://github.com/openpubkey/opkssh"
                    Write-Host ""
                    Write-Host "Config was still created successfully." -ForegroundColor Yellow
                }
            } else {
                Write-Warning "opkssh package not found in winget repository."
                Write-Host ""
                Write-Host "Install OPKSSH manually:" -ForegroundColor Cyan
                Write-Host "  https://github.com/openpubkey/opkssh"
                Write-Host ""
                Write-Host "After installing, open a new terminal and run:"
                Write-Host "  opkssh login uga"
                Write-Host ""
                Write-Host "Config was still created successfully." -ForegroundColor Yellow
            }
        } catch {
            Write-Warning "Failed to install opkssh via winget: $_"
            Write-Host ""
            Write-Host "Install OPKSSH manually:" -ForegroundColor Cyan
            Write-Host "  https://github.com/openpubkey/opkssh"
            Write-Host ""
            Write-Host "Config was still created successfully." -ForegroundColor Yellow
        }
    } else {
        Write-Warning "winget is not available on this system."
        Write-Host ""
        Write-Host "Install OPKSSH manually:" -ForegroundColor Cyan
        Write-Host "  https://github.com/openpubkey/opkssh"
        Write-Host "  https://github.com/openpubkey/opkssh/releases"
        Write-Host ""
        Write-Host "Or install winget (Windows Package Manager) first:"
        Write-Host "  https://aka.ms/winget-install"
        Write-Host ""
        Write-Host "After installing, open a new terminal and run:"
        Write-Host "  opkssh login uga"
        Write-Host ""
        Write-Host "Config was still created successfully." -ForegroundColor Yellow
    }
}
