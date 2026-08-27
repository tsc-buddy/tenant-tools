# Step 1: Deploy Governance

[Previous: Prerequisites](00-prerequisites.md) | [Back to master README](../README.md) | [Next: Configure PIM](02-configure-pim.md)

This step creates the shared governance baseline at the existing quarantine management group. It does not move or lock subscriptions.

## What Gets Deployed

The `tenant-decommission-governance` management-group deployment stack manages:

- A custom Policy initiative containing two built-in policies.
- A Policy assignment inherited by subscriptions below the management group.
- Permanent Reader assignments for the configured Reader groups.
- PIM eligibility for User Access Administrator and Contributor for Recovery Administrators.

The Policy blocks creation of new indexed resource types and protects selected resource types from deletion. It defaults to `Default`, which applies its deny effects to subscriptions beneath the quarantine management group.

## Configure The Parameter File

Copy `infra/subscription-quarantine/governance.example.bicepparam` to `infra/subscription-quarantine/governance.bicepparam` if the deployment file does not exist. Replace every placeholder object ID.

| Parameter | Purpose | Guidance |
|---|---|---|
| `groups.readers` | Groups receiving permanent Reader at management-group scope. | Use Microsoft Entra group object IDs. Add only approved audit or operations groups. |
| `groups.recoveryAdministrators` | Group eligible for User Access Administrator and Contributor through PIM. | Use the dedicated privileged group object ID. Keep membership minimal. |
| `protectedResourceTypes` | Resource types protected from deletion when the broad lock is removed. | Start with the supplied list. Add critical retained types only after testing. |
| `enforcementMode` | Enables or suppresses Policy enforcement. | Keep the default `Default` to enforce deny effects. Use `DoNotEnforce` only when evaluation without blocking is explicitly required. |
| `eligibilityDuration` | Duration of PIM eligibility in ISO 8601 format. | `P365D` means 365 days. The value must comply with tenant PIM policy. |

Validate the deployment parameter file:

```powershell
az bicep build-params --file $parameterFile
```

## Preview

```powershell
./scripts/Deploy-QuarantineGovernance.ps1 `
  -ManagementGroupId $managementGroupId `
  -ParameterFile $parameterFile `
  -WhatIf
```

The local preview shows the target, stack name, Policy enforcement, PIM duration, group IDs, protected resource types, and intended resources. It is not an Azure resource-level diff.

**Stop if:** the management-group ID, stack name, identities, enforcement mode, or protected types are wrong.

## Deploy

```powershell
./scripts/Deploy-QuarantineGovernance.ps1 `
  -ManagementGroupId $managementGroupId `
  -ParameterFile $parameterFile
```

Confirm only after checking the target management-group ID. Long-running Azure stack calls may be quiet until completion.

The stack uses `ActionOnUnmanage DeleteAll` and `DenySettingsMode None`. Removing a resource from the template or deleting the stack can delete resources managed by the stack.

## Verify The Stack

```powershell
$governanceStack = Get-AzManagementGroupDeploymentStack `
  -ManagementGroupId $managementGroupId `
  -Name 'tenant-decommission-governance'

$governanceStack | Select-Object Name, ProvisioningState
$governanceStack.Resources | Select-Object ResourceId, Status
```

Expected result:

- Stack name is `tenant-decommission-governance`.
- Provisioning state is `Succeeded`.
- Managed resources include the Policy initiative, Policy assignment, Reader assignments, and two PIM eligibility requests.

**Stop if:** the stack failed or its managed resources are incomplete.

## PIM Expiration Errors

If Azure reports `ExpirationRule - The policy does not allow permanent assignment`, ensure the current template uses `AfterDuration` and that `eligibilityDuration` is finite. If `P365D` exceeds the tenant maximum, reduce it, preview, and redeploy the same stack.

Confirm that `enforcementMode` is `Default`, then continue to [Step 2: Configure PIM](02-configure-pim.md). Perform the full lifecycle rehearsal with a disposable subscription before admitting production subscriptions.
