# Tenant Decommission Guardrails

Azure tenant decommissioning controls organized as reusable tools, scenario-specific infrastructure, and operator runbooks.

## Choose A Scenario

| Scenario | Use when |
|---|---|
| [Tenant-Wide Guardrails](scenarios/tenant-wide/README.md) | Assign the guardrail initiative at a selected management group and apply `ReadOnly` locks to an explicit subscription list. This is the simple deployment path. |
| [Subscription Quarantine](scenarios/subscription-quarantine/README.md) | Move retained subscriptions into a quarantine management group, review direct RBAC, configure recovery access, lock subscriptions, and operate the full lifecycle. |

## Repository Layout

```text
tools/                         Reusable PowerShell scripts and shared functions
infra/
  tenant-wide/                 Bicep for the simple tenant-wide scenario
  subscription-quarantine/     Bicep for the full quarantine scenario
scenarios/
  tenant-wide/                 Tenant-wide operator runbook
  subscription-quarantine/     Full lifecycle runbooks and architecture guidance
tests/                         Offline PowerShell safety and syntax checks
```

Start with the README for the chosen scenario. Run commands from this project root so documented relative paths resolve consistently.

## Validate Everything

```powershell
az bicep build --file ./infra/tenant-wide/tenant-guardrails.bicep
az bicep build --file ./infra/tenant-wide/subscription-lock.bicep
az bicep build-params --file ./infra/tenant-wide/tenant-guardrails.bicepparam
az bicep build --file ./infra/subscription-quarantine/governance.bicep
az bicep build --file ./infra/subscription-quarantine/subscription-lock.bicep
az bicep build-params --file ./infra/subscription-quarantine/governance.example.bicepparam
az bicep build-params --file ./infra/subscription-quarantine/subscription-lock.example.bicepparam
./tests/Smoke.Tests.ps1
```
