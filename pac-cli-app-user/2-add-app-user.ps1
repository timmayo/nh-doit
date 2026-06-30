<#
.SYNOPSIS
    Adds a Dataverse Application User to one or more GCC environments.

.DESCRIPTION
    Run this script interactively, signed in as a human Power Platform Administrator.
    The SPN is added as an Application User with the System Administrator role
    in each target environment.

    Configuration is loaded from config.json in the same directory.
    On first run, missing values are prompted and saved to config.json for future use.

.NOTES
    GCC-specific:
      - pac auth create requires --cloud UsGov
      - Dataverse environment URLs use .crm9.dynamics.com
    
    Prerequisites:
      - SPN registered as a Power Platform management application
        (see 1-register-management-app.ps1)
      - pac CLI installed
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------
# REGION: Config
# ------------------------------------------------------------------

$ScriptDir  = $PSScriptRoot
$ConfigPath = Join-Path $ScriptDir 'config.json'

function Get-Config {
    $defaults = [ordered]@{
        TenantId        = ''
        AppId           = ''
        SpnCredential   = ''
        EnvironmentUrls = @()
    }

    # Load existing config if present
    if (Test-Path $ConfigPath) {
        $loaded = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        foreach ($key in $defaults.Keys) {
            if ($null -ne $loaded.$key -and $loaded.$key -ne '') {
                $defaults[$key] = $loaded.$key
            }
        }
    }

    # Prompt for any missing scalar values
    $prompted = $false
    foreach ($key in @('TenantId', 'AppId')) {
        if (-not $defaults[$key]) {
            $defaults[$key] = Read-Host "Enter $key"
            $prompted = $true
        }
    }

    # Always prompt for SPN credential - never persist to disk
    $secure = Read-Host "Enter SPN credential" -AsSecureString
    $defaults['SpnCredential'] = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    )

    if ($defaults['EnvironmentUrls'].Count -eq 0) {
        Write-Host "Enter Dataverse environment URLs (one per line, blank line to finish):"
        $urls = @()
        do {
            $url = Read-Host "  URL"
            if ($url) { $urls += $url }
        } while ($url)
        $defaults['EnvironmentUrls'] = $urls
        $prompted = $true
    }

    # Save back if anything was prompted - never save SPN credential
    if ($prompted) {
        $existing = if (Test-Path $ConfigPath) {
            Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
        } else { @{} }

        foreach ($key in $defaults.Keys) {
            if ($key -ne 'SpnCredential') {
                $existing[$key] = $defaults[$key]
            }
        }

        $existing | ConvertTo-Json -Depth 3 | Set-Content $ConfigPath
        Write-Host "Configuration saved to config.json (SPN credential not saved)" -ForegroundColor Green
    }

    return $defaults
}

# ------------------------------------------------------------------
# REGION: Main
# ------------------------------------------------------------------

$config          = Get-Config
$tenantId        = $config.TenantId
$appId           = $config.AppId
$spnCredential   = $config.SpnCredential
$environmentUrls = $config.EnvironmentUrls
$securityRole    = "System Administrator"

# Authenticate pac CLI once as the human admin
Write-Host "`nAuthenticating to Power Platform..." -ForegroundColor Cyan
pac auth create --cloud UsGov

foreach ($envUrl in $environmentUrls) {
    Write-Host "`nProcessing: $envUrl" -ForegroundColor Cyan

    pac admin assign-user `
        --environment      $envUrl `
        --user             $appId `
        --role             $securityRole `
        --application-user

    Write-Host "Done: $envUrl" -ForegroundColor Green
}

# Clear auth profile after all environments are processed
pac auth clear

Write-Host "`nAll environments processed." -ForegroundColor Cyan