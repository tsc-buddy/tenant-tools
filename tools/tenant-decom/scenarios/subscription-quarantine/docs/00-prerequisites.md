# Step 0: Prerequisites And Setup

[Back to master README](../README.md) | [Next: Deploy governance](01-deploy-governance.md)

Complete this step once before deploying the solution.

## Requirements

- PowerShell 7 recommended.
- Azure CLI with Bicep.
- Azure PowerShell 12.0.0 or later, including `Az.Accounts` and `Az.Resources`.
- An existing quarantine management group with no inherited write access except approved governance paths.
- A Microsoft Entra Readers security group.
- A Microsoft Entra Recovery Administrators security group.
- PIM licensing and governance approval.
- Permissions to deploy at management-group scope and manage Policy, RBAC, PIM, subscription placement, and locks.

The solution does not create or delete the quarantine management group.

## Open The Project

Open PowerShell 7 at the project directory:

```powershell
Set-Location ./projects/tenant-decommission-guardrails
```

Set the deployment values for the current session:

```powershell
$tenantId = '<tenant-id>'
$managementGroupId = '<existing-quarantine-management-group-id>'
$parameterFile = './infra/subscription-quarantine/governance.bicepparam'
```

## Authenticate And Confirm The Target

```powershell
Connect-AzAccount -Tenant $tenantId
Get-AzContext | Select-Object Account, Tenant, Subscription
```

The scripts never initiate an interactive login. Run them in the same terminal where `Connect-AzAccount` completed.

Confirm that the existing management group is visible:

```powershell
Get-AzManagementGroup -GroupId $managementGroupId |
  Select-Object Name, DisplayName
```

**Stop if:** the tenant is wrong, the management group is missing, or it is not the intended quarantine target.

## Validate The Project

```powershell
az bicep build --file ./infra/subscription-quarantine/governance.bicep
az bicep build --file ./infra/subscription-quarantine/subscription-lock.bicep
az bicep build-params --file ./infra/subscription-quarantine/governance.example.bicepparam
az bicep build-params --file ./infra/subscription-quarantine/subscription-lock.example.bicepparam
./tests/Smoke.Tests.ps1
```

Successful Bicep commands complete without errors. The smoke test ends with `Passed smoke tests for <n> PowerShell files.` These checks validate local syntax, not Azure permissions.

## Important Access Behavior

- Root and parent management-group role assignments continue to inherit.
- Direct subscription, resource-group, and resource assignments remain after a management-group move.
- Assigning Reader does not cancel existing Contributor, Owner, or custom write roles.
- The readiness and admission steps explicitly review direct write-capable assignments.

When all checks pass, continue to [Step 1: Deploy Governance](01-deploy-governance.md).
