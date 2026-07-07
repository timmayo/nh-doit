<#
.SYNOPSIS
    Registers an Entra ID app registration as a Power Platform management application.

.DESCRIPTION
    Run this script interactively, signed in as a human Power Platform Administrator.
    This is a one-time step and cannot be run by the SPN itself.

    Configuration is loaded from config.json in the same directory.
    On first run, missing values are prompted and saved to config.json for future use.

.NOTES
    Docs: https://learn.microsoft.com/en-us/powershell/module/microsoft.powerapps.administration.powershell/new-powerappmanagementapp
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------
# REGION: Config
# ------------------------------------------------------------------

$ScriptDir  = $PSScriptRoot
$ConfigPath = Join-Path $ScriptDir 'config.json'

function Test-IsGuid {
    param([string]$Value)
    return $Value -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
}

function Get-Config {
    $defaults = [ordered]@{
        TenantId = ''
        AppId    = ''
    }

    # Load existing config if present
    if (Test-Path $ConfigPath) {
        $loaded = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        foreach ($key in @($defaults.Keys)) {
            if ($loaded.PSObject.Properties.Name -contains $key -and $null -ne $loaded.$key -and (Test-IsGuid $loaded.$key)) {
                $defaults[$key] = $loaded.$key
            }
        }
    }

    # Prompt for any missing values
    $prompted = $false
    foreach ($key in @($defaults.Keys)) {
        if (-not $defaults[$key]) {
            $defaults[$key] = Read-Host "Enter $key"
            $prompted = $true
        }
    }

    # Save back if anything was prompted
    if ($prompted) {
        # Merge with any existing config to preserve values from other scripts
        $existing = if (Test-Path $ConfigPath) {
            Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
        } else { @{} }

        foreach ($key in @($defaults.Keys)) {
            $existing[$key] = $defaults[$key]
        }

        $existing | ConvertTo-Json -Depth 3 | Set-Content $ConfigPath
        Write-Host "Configuration saved to config.json" -ForegroundColor Green
    }

    return $defaults
}

# ------------------------------------------------------------------
# REGION: Main
# ------------------------------------------------------------------

$config   = Get-Config
$tenantId = $config.TenantId
$appId    = $config.AppId

# Sign in as a Power Platform Administrator (interactive, human account)
Write-Host "`nSigning in as Power Platform Administrator..." -ForegroundColor Cyan
Add-PowerAppsAccount -Endpoint usgov -TenantID $tenantId

# Register the SPN as a Power Platform management application
Write-Host "`nRegistering management application..." -ForegroundColor Cyan
New-PowerAppManagementApp -ApplicationId $appId

Write-Host "`nDone. $appId is now registered as a Power Platform management application." -ForegroundColor Green