<#
.SYNOPSIS
    Test runbook - lists Dataverse environments accessible to the SPN.

.DESCRIPTION
    Paste this script into an Azure Automation Runbook (PowerShell 7.2).
    Triggered via HTTP webhook from a Power Automate flow.

    Verifies:
      - Key Vault secret retrieval works
      - pac auth create succeeds against GCC using client credentials
      - SPN is registered as a Power Platform management application

    Required Automation Account variables:
      - TenantId
      - AppId
      - KeyVaultName
      - KeyVaultSecretName

.NOTES
    GCC-specific:
      - pac auth create requires --cloud UsGov
      - Azure Automation native connector is NOT supported in GCC;
        trigger this runbook via HTTP webhook from Power Automate

    PAC CLI is installed at runtime via dotnet tool install.
    For production use, consider a Hybrid Runbook Worker with PAC CLI pre-installed.
#>

param(
    [Parameter(Mandatory = $false)]
    [object]$WebhookData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------
# REGION: Logging
# ------------------------------------------------------------------

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    Write-Output $line
}

# ------------------------------------------------------------------
# REGION: Main
# ------------------------------------------------------------------

# Authenticate using managed identity
Write-Log "Authenticating with managed identity..." INFO
Connect-AzAccount -Identity

# Load values from Automation Account variables
$tenantId           = Get-AutomationVariable -Name 'TenantId'
$appId              = Get-AutomationVariable -Name 'AppId'
$keyVaultName       = Get-AutomationVariable -Name 'KeyVaultName'
$keyVaultSecretName = Get-AutomationVariable -Name 'KeyVaultSecretName'

# Retrieve client secret from Key Vault
Write-Log "Retrieving client secret from Key Vault: $keyVaultName" INFO
try {
    $clientSecret = Get-AzKeyVaultSecret `
        -VaultName  $keyVaultName `
        -Name       $keyVaultSecretName `
        -AsPlainText
} catch {
    Write-Log "Failed to retrieve secret from Key Vault: $_" ERROR
    throw
}

# Install .NET 10
Write-Log "Installing .NET 10..." INFO
Invoke-WebRequest -Uri https://dot.net/v1/dotnet-install.ps1 -OutFile dotnet-install.ps1
./dotnet-install.ps1 -Channel 10.0 -InstallDir "$env:LOCALAPPDATA\Microsoft\dotnet"
$env:DOTNET_ROOT = "$env:LOCALAPPDATA\Microsoft\dotnet"
$env:PATH = "$env:DOTNET_ROOT;$env:DOTNET_ROOT\tools;$env:PATH"

# Install PAC CLI
Write-Log "Installing PAC CLI..." INFO
dotnet tool install --global Microsoft.PowerApps.CLI.Tool
$env:PATH = "$env:USERPROFILE\.dotnet\tools;$env:PATH"

# Authenticate pac CLI as the SPN
Write-Log "Authenticating pac CLI as SPN..." INFO
pac auth create `
    --applicationId $appId `
    --clientSecret  $clientSecret `
    --tenant        $tenantId `
    --cloud         UsGov

# List environments the SPN can see
Write-Log "Listing accessible environments..." INFO
pac admin list

# Clear auth profile
pac auth clear

Write-Log "Done." SUCCESS