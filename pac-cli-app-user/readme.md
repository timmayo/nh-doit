# PAC CLI App User Automation

Automates adding a Dataverse Application User to one or more GCC environments via an Azure Automation Runbook triggered by Power Automate.

---

## How It Works

A Power Automate flow triggers an Azure Automation Runbook via HTTP webhook. The runbook authenticates to Power Platform as a service principal (SPN) and adds the SPN as an Application User with the System Administrator role in each target environment. The flow then polls the runbook job and retrieves its output.

---

## Files

| File | Description |
|---|---|
| `1-register-management-app.ps1` | One-time setup. Registers the SPN as a Power Platform management application. Run interactively as a Power Platform Administrator. |
| `2-add-app-user.ps1` | One-time setup. Adds the SPN as a Dataverse Application User in each target environment. Run interactively as a Power Platform Administrator. |
| `3-runbook.ps1` | Paste this into the Azure Automation Runbook. |
| `docs/prerequisites.md` | Azure Automation Account setup instructions, IAM role assignments, and architecture diagrams. |
| `solution/src/` | Unpacked solution source (via `pac solution unpack`). Version controlled. |
| `solution/releases/NHDoIT_1_0_0_1_managed.zip` | Managed solution package for import into the customer's environment. |
| `solution/releases/NHDoIT_1_0_0_1_unmanaged.zip` | Unmanaged solution package, for development/customization. |

---

## Run Order

1. Review `docs/prerequisites.md` and ensure all Azure assets are in place
2. Run `1-register-management-app.ps1`
3. Run `2-add-app-user.ps1`
4. Create the Azure Automation Runbook, paste in `3-runbook.ps1`, and generate the webhook
5. Import the solution into the target Power Platform environment:
   - Use `NHDoIT_1_0_0_1_managed.zip` for the customer's environment
   - Use `NHDoIT_1_0_0_1_unmanaged.zip` for development/customization
6. Set the solution's environment variable values:

   | Environment Variable | Type | Value |
   |---|---|---|
   | `nh_ClientId` | Secret | SPN application (client) ID |
   | `nh_ClientSecret` | Secret | SPN client secret (Key Vault reference) |
   | `nh_WebhookUrl` | Secret | Webhook URL generated in Step 4 (Key Vault reference) |
   | `nh_TenantId` | Secret | Entra tenant ID |
   | `nh_SubscriptionId` | Secret | Azure subscription ID |
   | `nh_ResourceGroup` | Secret | Azure resource group name |
   | `nh_AutomationAccount` | Secret | Azure Automation Account name |

7. Test the Power Automate flow using the manual trigger

---

## Notes

- Scripts 1 and 2 are run locally and interactively — they are not pasted into the runbook
- `config.json` is generated on first run and stores non-sensitive values (TenantId, AppId, EnvironmentUrls). It is excluded from source control
- The client secret is never saved to disk — it is prompted each run and retrieved from Key Vault at runtime in the runbook
- GCC Dataverse environment URLs use `.crm9.dynamics.com`, not `.crm.dynamics.com`
- This customer's tenant is GCC (moderate) — Entra ID/ARM calls use commercial endpoints, while Power Platform/Dataverse calls use GCC-specific endpoints. See `docs/prerequisites.md` for the full explanation.