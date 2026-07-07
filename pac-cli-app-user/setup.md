# Azure Automation Runbook – Setup

This document describes the full setup sequence — from registering the SPN in Power Platform through configuring the Azure Automation Runbook and the Power Automate flow that triggers it.

---

## Overview

The runbook is triggered by a Power Automate flow via an HTTP webhook. When triggered, it authenticates to Power Platform as a service principal (SPN) and adds an Application User to one or more Dataverse environments automatically. The flow then polls the runbook job status and retrieves its output.

**Setup (one-time, done before the flow ever runs):**

```mermaid
flowchart TD
    A[Register SPN as Power Platform<br/>management application] --> B[Add SPN as Dataverse<br/>Application User per environment]
    B --> C[Create Azure Automation Account<br/>+ system-assigned managed identity]
    C --> D[Grant Key Vault access:<br/>managed identity, Dataverse SP, your user]
    D --> E[Create Runbook<br/>+ generate Webhook URL]
    E --> F[Store secrets as Dataverse<br/>environment variables]
```

**The Power Automate flow itself:**

```mermaid
flowchart TD
    A[Manual trigger] --> B[Get Webhook URL<br/>from environment variable]
    B --> C[HTTP POST to webhook<br/>→ triggers Runbook]
    C --> D[Get access token<br/>commercial Entra ID]
    D --> E[Get job status<br/>via ARM REST API]
    E --> F{Status =<br/>Completed?}
    F -->|No, wait & retry| E
    F -->|Yes| G[Get job output<br/>via ARM REST API]
```

> **Cloud clarification:** This customer's GCC tenant is **GCC (moderate)**, not GCC High or DoD. GCC moderate runs on **commercial Entra ID and ARM endpoints** (`login.microsoftonline.com`, `management.azure.com`) — not `.us` gov endpoints. However, PAC CLI and Power Platform Admin PowerShell still target GCC-specific Power Platform/Dataverse endpoints (`--cloud UsGov`, `-Endpoint usgov`, `.crm9.dynamics.com`). Do not assume these two things use the same cloud designation — verify which layer (Entra/ARM vs. Power Platform/Dataverse) you're authenticating to before picking an endpoint.

---

## 1. Register the SPN as a Power Platform Management Application

Run `1-add-management-app.ps1` interactively, signed in as a human Power Platform Administrator. This is a one-time step and cannot be run by the SPN itself.

---

## 2. Add the SPN as a Dataverse Application User

Run `2-add-app-user.ps1` interactively, signed in as a human Power Platform Administrator. Adds the SPN as an Application User with the System Administrator role in each target environment.

---

## 3. Resource Group

Create (or identify) an Azure Resource Group to contain the Automation Account and Key Vault used by this solution.

1. Azure portal → **Resource groups** → **Create**
2. Choose the subscription and a region (any commercial Azure region — GCC moderate does not require a GovCloud subscription)
3. Name it following your naming convention (e.g. `rg-nh-doit`)

---

## 4. Azure Automation Account

Create an Azure Automation Account in the Resource Group created above.

| Setting | Value |
|---|---|
| Runtime version | PowerShell 7.2 |
| Region | Same as the Resource Group |
| Managed Identity | System-assigned (required) |

Name it following your naming convention (e.g. `aa-nh-doit`).

---

## 5. Key Vault Access — Three Separate Grants Required

> **Prerequisite:** Before continuing, you should already have a Key Vault created using your naming convention (e.g. `kv-nh-doit`) with the following secrets:
> - `scrt-nh-doit-automation-account`
> - `scrt-nh-doit-client-id`
> - `scrt-nh-doit-client-secret`
> - `scrt-nh-doit-resource-group`
> - `scrt-nh-doit-subscription-id`
> - `scrt-nh-doit-tenant-id`
> - `scrt-nh-doit-webhook` (placeholder value for now — updated once the webhook is generated in Section 10)

Three different identities need access to this Key Vault, and each is granted separately. Missing any one of these produces a different failure at a different stage, so confirm all three.

| Who needs access | Role | Where to grant it |
|---|---|---|
| Automation Account's system-assigned managed identity | Key Vault Secrets User | Key Vault → Access control (IAM) |
| Dataverse service principal (appears as "Dataverse" — search by name, not App ID, as the App ID differs by tenant/cloud) | Key Vault Secrets User | Key Vault → Access control (IAM) |
| Your own user account (to create the environment variable in the Azure portal & Maker portals) | Key Vault Administrator | Key Vault → Access control (IAM) |

**Finding the Automation Account's managed identity:**
Automation Account → **Identity → System assigned** → copy the Object (principal) ID.

**Finding the Dataverse service principal:**
In the role assignment "Select members" search box, search **"Dataverse"**. Do not search by App ID — the well-known commercial App ID (`00000007-0000-0000-c000-000000000000`) does not necessarily match what appears in a GCC tenant. Confirm by name.

---

## 6. Required PowerShell Modules (Automation Account)

Install these modules in the Automation Account under **Shared Resources → Modules → Add a module → Browse the gallery**:

> When adding each module, set **Runtime version** to **7.2** to match the runbook's runtime.

| Module | Purpose |
|---|---|
| `Microsoft.PowerApps.Administration.PowerShell` | Registering the management application; PAC CLI is a separate executable (see Section 8) |
| `Az.Accounts` | `Connect-AzAccount -Identity` for managed identity auth |
| `Az.KeyVault` | `Get-AzKeyVaultSecret` |

---

## 7. Automation Account Variables

Create the following under **Shared Resources → Variables**:

| Variable Name | Type | Encrypted | Value |
|---|---|---|---|
| `TenantId` | String | No | Entra tenant ID (GUID) |
| `AppId` | String | No | SPN application (client) ID |
| `KeyVaultName` | String | No | Name of the Key Vault storing the SPN secret |
| `KeyVaultSecretName` | String | No | Name of the secret within the Key Vault |

The client secret itself is never stored as an Automation variable — it is retrieved from Key Vault at runtime using the managed identity.

---

## 8. PAC CLI in the Runbook

> **Informational only — no action required.** This section explains how the runbook handles PAC CLI at runtime; there is nothing to configure here.

PAC CLI is a standalone executable, not a PowerShell module, and is not available in the Azure Automation sandbox by default. The runbook installs it at runtime:

1. Installs .NET 10 via `dotnet-install.ps1`
2. Installs PAC CLI via `dotnet tool install --global Microsoft.PowerApps.CLI.Tool`

This adds roughly 1–2 minutes to each runbook execution. For frequent or production use, consider a **Hybrid Runbook Worker** with .NET and PAC CLI pre-installed instead of installing at runtime.

---

## 9. SPN Role Assignment on the Automation Account (for job status polling)

If the Power Automate flow polls the runbook's job status/output via the ARM REST API (rather than only firing the webhook and walking away), the SPN needs an RBAC role on the Automation Account itself — this is separate from anything configured in Power Platform or Key Vault.

**Automation Account → Access control (IAM) → Add role assignment**

| Field | Value |
|---|---|
| Role | Automation Job Operator |
| Assign access to | Service principal |
| Member | the SPN (search by app name or Client ID) |

Without this, polling fails with: `does not have authorization to perform action 'Microsoft.Automation/automationAccounts/jobs/read'`.

---

## 10. Webhook

> **Prerequisite:** You should already have a Runbook created (Runbook type is **PowerShell**) using your naming convention (e.g. `rb-nh-doit`).

1. Open the Runbook → **Edit in Portal** and paste in the contents of `3-runbook.ps1`
2. Runbook → **Webhooks** → **Add webhook**
3. Set an expiry date per your organization's policy
4. **Copy the webhook URL immediately** — it is shown only once
5. Store it as a Secret-type Dataverse environment variable (see Section 12) — never hardcode it in the flow

---

## 11. Register Microsoft.PowerPlatform Resource Provider

Before creating any Secret-type environment variable in Power Platform, register the `Microsoft.PowerPlatform` resource provider on the Azure subscription that hosts the Key Vault.

1. Azure portal → your subscription → **Resource providers**
2. Search for `Microsoft.PowerPlatform`
3. If status is not **Registered**, select it and click **Register**

> **Important:** If this provider is registered *after* an environment variable is created, the environment variable can appear to save successfully but silently fail to resolve the secret at runtime, producing an error like `Value cannot be null. Parameter name: input` when the flow runs. If you hit this error and later register the provider, delete and recreate the environment variable — re-registering the provider alone does not fix an already-broken reference.

Also confirm the Key Vault's networking allows access:
- **Networking → Allow public access from all networks**, or
- If using a firewall, explicitly allow Power Platform IP ranges (Power Platform is not covered by "Trusted Services Only")

---

## 12. Secrets in Power Automate Flows

Never hardcode Client ID, Client Secret, Tenant ID, or webhook URLs directly in flow actions. Use Dataverse environment variables instead.

| Value | Environment Variable | Type |
|---|---|---|
| Webhook URL | `nh_WebhookUrl` | Secret |
| SPN Client Secret | `nh_SpnClientSecret` | Secret |
| SPN App ID | `nh_SpnAppId` | Secret |

**Retrieving Secret-type variables:**
Dataverse connector → **Perform an unbound action** → Action Name `RetrieveEnvironmentVariableSecretValue`, passing the schema name as `EnvironmentVariableName`. This requires Section 11 (resource provider registration) and Section 5 (Key Vault access for the Dataverse service principal) to already be in place.

**Additional steps:**
- Enable **Secure Inputs/Outputs** (action Settings tab) on any HTTP action that references a secret, even indirectly, so values don't appear in run history.

---

## 13. Power Automate Flow — Token Acquisition for ARM Calls (GCC moderate)

If the flow calls the ARM REST API (job status/output polling), acquire the token manually rather than relying on the built-in **Active Directory OAuth** authentication type, unless you've confirmed it works with commercial endpoints for your tenant. Since GCC moderate uses commercial Entra ID/ARM, use:

| Field | Value |
|---|---|
| Token URI | `https://login.microsoftonline.com/{tenantId}/oauth2/token` |
| Body | `grant_type=client_credentials&client_id={appId}&client_secret={secret}&resource=https://management.azure.com/` |

Subsequent ARM calls (job status, job output) use:
- Authentication type: **Raw**
- Value: `Bearer {access_token}`
- URIs use `management.azure.com`, not `management.usgovcloudapi.net`

---

## 14. Power Automate Flow — HTTP Action to Trigger the Webhook

The flow must call the webhook using the **HTTP** action (not the Azure Automation connector, which is not supported in GCC).

| Setting | Value |
|---|---|
| Method | POST |
| URI | webhook URL, retrieved from `nh_WebhookUrl` (see Section 12) |
| Headers | `Content-Type: application/json` |
| Body | `{}` (or environment payload, depending on runbook version) |

> GCC Dataverse environment URLs use `.crm9.dynamics.com`, not `.crm.dynamics.com` (commercial).

---

## 15. Do Until Loop Logic (Job Status Polling)

If polling for job completion, the **Loop until** condition must be:

`JobStatus` **is equal to** `Completed`

Not "is not equal to" — a Do Until loop runs until the condition becomes **true**, so an incorrect operator here causes the loop to exit after a single iteration without actually waiting for the job to finish.

---

## Summary Checklist

- [ ] SPN registered as Power Platform management application (`1-add-management-app.ps1`)
- [ ] SPN added as Dataverse Application User in each target environment (`2-add-app-user.ps1`)
- [ ] Resource Group created
- [ ] Azure Automation Account created (PowerShell 7.2, system-assigned managed identity)
- [ ] Key Vault Secrets User granted to: Automation Account managed identity, Dataverse service principal, your own user
- [ ] Required PowerShell modules installed in Automation Account
- [ ] Automation Account variables created (`TenantId`, `AppId`, `KeyVaultName`, `KeyVaultSecretName`)
- [ ] Automation Job Operator role granted to SPN on the Automation Account (for job polling)
- [ ] Runbook created (`3-runbook.ps1` pasted in) and webhook generated
- [ ] `Microsoft.PowerPlatform` resource provider registered on the subscription
- [ ] Key Vault networking allows Power Platform access
- [ ] Webhook URL stored as Secret-type environment variable (`nh_WebhookUrl`)
- [ ] SPN Client Secret and App ID stored as environment variables (`nh_SpnClientSecret`, `nh_SpnAppId`)
- [ ] Power Automate HTTP action configured to trigger webhook
- [ ] Power Automate token-acquisition + ARM polling actions configured with commercial endpoints (GCC moderate)
- [ ] Do Until loop condition set to "is equal to Completed"