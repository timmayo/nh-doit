# PAC CLI App User Automation

Automates adding a Dataverse Application User to one or more GCC environments via an Azure Automation Runbook triggered by Power Automate.

---

## How It Works

A Power Automate flow triggers an Azure Automation Runbook via HTTP webhook. The runbook authenticates to Power Platform as a service principal (SPN) and adds the SPN as an Application User with the System Administrator role in each target environment.

---

## Files

| File | Description |
|---|---|
| `1-add-management-app.ps1` | One-time setup. Registers the SPN as a Power Platform management application. Run interactively as a Power Platform Administrator. |
| `2-add-app-user.ps1` | One-time setup. Adds the SPN as a Dataverse Application User in each target environment. Run interactively as a Power Platform Administrator. |
| `3-runbook.ps1` | Paste this into the Azure Automation Runbook. |
| `docs/prerequisites.md` | Azure Automation Account setup instructions. |

---

## Run Order

1. Review `docs/prerequisites.md` and ensure all Azure assets are in place
2. Run `1-add-management-app.ps1`
3. Run `2-add-app-user.ps1`
4. Create the Azure Automation Runbook and paste in `3-runbook.ps1`
5. Create the webhook and configure the Power Automate HTTP action

---

## Notes

- Scripts 1 and 2 are run locally and interactively — they are not pasted into the runbook
- `config.json` is generated on first run and stores non-sensitive values (TenantId, AppId, EnvironmentUrls). It is excluded from source control
- The client secret is never saved to disk — it is prompted each run and retrieved from Key Vault at runtime in the runbook
- GCC Dataverse environment URLs use `.crm9.dynamics.com`, not `.crm.dynamics.com`