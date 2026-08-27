# Tenant Decommission Guardrails

Azure tenant decommissioning controls organized as reusable scripts, scenario-specific infrastructure, and operator runbooks.

## Overview

Tenant Decommission Guardrails helps operators protect Azure environments during tenant or subscription decommissioning. It combines Azure Policy, deployment stacks, subscription locks, RBAC inspection, and optional PIM recovery access into repeatable workflows.

### Key capabilities

- Apply tenant-wide governance controls at a management group and lock an explicit list of subscriptions.
- Assess and quarantine retained subscriptions with reusable PowerShell scripts and Bicep infrastructure.
- Preview changes, validate infrastructure locally, and remove managed controls through documented workflows.

The project does not initiate Azure sign-in, decide which subscriptions should be retained, or replace an organization's decommission plan and approval process.

## Getting Started

### Prerequisites

- PowerShell 7
- Azure CLI with Bicep support
- Azure PowerShell modules `Az.Accounts` and `Az.Resources`
- An existing Azure PowerShell context for the target tenant
- Permissions appropriate to the selected scenario and target scopes

Sign in and confirm the active tenant before running any project script:

```powershell
Connect-AzAccount -Tenant '<tenant-id>'
Get-AzContext
```

From the repository root, change to this project directory:

```powershell
cd ./tools/tenant-decom
```

Choose a scenario below and read its runbook before deployment. Start with the documented `-WhatIf` workflow to review local intent without changing Azure.

> [!IMPORTANT]
> Run commands from this project root so documented relative paths resolve consistently. Never commit credentials, tokens, or configuration containing secrets.

## Usage

### Choose a scenario

| Scenario | Use when |
|---|---|
| [Tenant-Wide Guardrails](scenarios/tenant-wide/README.md) | Assign the guardrail initiative at a selected management group and apply `ReadOnly` locks to an explicit subscription list. This is the simple deployment path. |
| [Subscription Quarantine](scenarios/subscription-quarantine/README.md) | Assess, move, govern, and lock retained subscriptions through a fuller lifecycle. Infrastructure and tools are included. |

The tenant-wide runbook contains the supported preview, deployment, enforcement, recovery-access, and removal commands. See the [scripts reference](scripts/README.md) for all reusable PowerShell entry points.

## Architecture

```text
scripts/                       Reusable PowerShell scripts and shared functions
infra/
  tenant-wide/                 Bicep for the simple tenant-wide scenario
  subscription-quarantine/     Bicep for the full quarantine scenario
scenarios/
  tenant-wide/                 Tenant-wide operator runbook
  subscription-quarantine/     Full lifecycle runbooks and architecture guidance
tests/                         Offline PowerShell safety and syntax checks
```

Policy and governance resources are deployed at management-group scope. Subscription-specific controls, including `ReadOnly` locks, are deployed only to subscriptions explicitly supplied to the scripts. Detailed scope behavior and removal semantics are documented in each published scenario runbook.

## Development

Keep changes focused on a scenario or shared script, update the corresponding runbook, and add offline coverage for safety-sensitive PowerShell behavior where practical.

### Validate

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

## Known Limitations

- `-WhatIf` previews local intent; it does not produce an Azure resource-level deployment diff.
- The scripts reuse the current Azure PowerShell context and never initiate sign-in.

## Security

Do not include credentials, access tokens, tenant exports, or unredacted logs in commits or public issues. Report suspected security vulnerabilities privately to the repository maintainers rather than disclosing them in a public issue.

Review all target scopes, subscription IDs, lock behavior, Policy enforcement settings, and PIM assignments before deployment. Use least-privileged operator access and preview supported operations with `-WhatIf` first.

## Support

For defects and feature requests, open an issue in this repository and include:

- A clear description of the problem or requested outcome
- Steps to reproduce, when applicable
- Relevant sanitized logs and command output
- PowerShell, Azure CLI, Bicep, and Azure module versions

## Contributing

Contributions are welcome. Before starting substantial work, open an issue to discuss the proposed change and confirm that it fits the project's scope.

1. Fork the repository and create a branch from the default branch.
2. Make a focused change and include or update tests where practical.
3. Run the validation commands documented above.
4. Update any affected scenario or script documentation.
5. Open a pull request that explains what changed and why.

## License

Licensed under the [MIT License](../../LICENSE).
