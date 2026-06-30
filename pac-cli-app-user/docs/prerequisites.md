# Azure Automation Runbook – Prerequisites

This document describes everything that must be in place before the runbook can be created and run. The runbook itself will be provided separately as a PowerShell script.

---

## Overview

The runbook is triggered by a Power Automate flow via an HTTP webhook. When triggered, it authenticates to Power Platform as a service principal (SPN) and adds an Application User to one or more Dataverse environments automatically.

The flow is:

```
Power Automate (GCC)
  → HTTP action → POST to Azure Automation webhook
    → PowerShell Runbook
      → Authenticates to Power Platform as SPN
        → Adds Application User + assigns security role per environment
```

---

## 1. Azure Automation Account

Create an Azure Automation Account in your Azure subscription.

| Setting | Value |
|---|---|
| Runtime version | PowerShell 7.2 |
| Region | Match your GCC tenant region (e.g. USGov Virginia, USGov Arizona) |
| Managed Identity | System-assigned (recommended) |

> **Note:** The Automation Account does not need to be in a GovCloud Azure subscription. A commercial Azure subscription works fine for hosting the runbook — the GCC distinction applies to the Power Platform endpoints the runbook calls, not where the Automation Account lives.

---

## 2. Required PowerShell Modules

The following modules must be installed in the Automation Account. In the Azure portal, go to your Automation Account → **Modules** → **Add a module** → browse the gallery.

| Module | Source |
|---|---|
| `Microsoft.PowerApps.Administration.PowerShell` | PowerShell Gallery |
| `Microsoft.Xrm.Tooling.CrmConnector.PowerShell` | PowerShell Gallery (dependency) |

> The PAC CLI (`pac`) is a standalone executable, not a PowerShell module. See Section 4 for how to handle this in the runbook.

---

## 3. Key Vault (Recommended)

Store the SPN client secret in an Azure Key Vault rather than as a plaintext Automation variable.

1. Create an Azure Key Vault (or use an existing one).
2. Add the client secret as a **Secret** (e.g. name it `nh-doit-pac-spn-secret`).
3. Grant the Automation Account's managed identity the **Key Vault Secrets User** role on the Key Vault.

If Key Vault is not available, the secret can be stored as an **Encrypted Variable** in the Automation Account instead (**Automation Account → Shared Resources → Variables**). This is less preferred but acceptable.

---

## 4. Automation Account Variables

Create the following variables in the Automation Account under **Shared Resources → Variables**:

| Variable Name | Type | Encrypted | Value |
|---|---|---|---|
| `TenantId` | String | No | Your Entra tenant ID (GUID) |
| `AppId` | String | No | The SPN application (client) ID |
| `ClientSecret` | String | **Yes** | SPN client secret (only if not using Key Vault) |

---

## 5. SPN Prerequisites

The SPN used by the runbook must have two things in place before the runbook will work. These are covered by separate scripts provided alongside this document.

| Prerequisite | Script | Who runs it |
|---|---|---|
| Registered as a Power Platform management application | `1-add-management-app.ps1` | Human Power Platform Administrator, run once |
| Added as a Dataverse Application User with System Administrator role in each target environment | `2-add-app-user.ps1` | Human Power Platform Administrator, run once per environment set |

---

## 6. Webhook

Once the Automation Account and runbook are created, a webhook must be created to allow Power Automate to trigger it.

1. In the Azure portal, open the runbook → **Webhooks** → **Add webhook**.
2. Set an expiry date appropriate for your organization's policy.
3. **Copy the webhook URL immediately** — it is only shown once.
4. Store the webhook URL in an Azure Key Vault secret or a Power Automate environment variable. Do not hardcode it in the flow.

> The webhook URL contains the authentication token. Treat it as a secret.

---

## 7. Power Automate Flow (HTTP Action)

The Power Automate flow must call the webhook using the **HTTP** action (not the Azure Automation connector, which is not supported in GCC).

| Setting | Value |
|---|---|
| Method | POST |
| URI | The webhook URL from Section 6 |
| Headers | `Content-Type: application/json` |
| Body | See below |

Example body:
```json
{
  "EnvironmentUrls": [
    "https://your-org.crm9.dynamics.com"
  ]
}
```

> GCC Dataverse environment URLs use `.crm9.dynamics.com`, not `.crm.dynamics.com` (commercial).

---

## Summary Checklist

- [ ] Azure Automation Account created (PowerShell 7.2)
- [ ] Required PowerShell modules installed in Automation Account
- [ ] Key Vault configured and Automation Account managed identity granted access
- [ ] Automation Account variables created (`TenantId`, `AppId`, `ClientSecret`)
- [ ] SPN registered as Power Platform management application (`1-add-management-app.ps1`)
- [ ] SPN added as Dataverse Application User in each target environment (`2-add-app-user.ps1`)
- [ ] Runbook created and webhook generated
- [ ] Webhook URL stored securely
- [ ] Power Automate HTTP action configured