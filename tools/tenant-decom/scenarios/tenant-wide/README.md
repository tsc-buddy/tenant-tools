# Tenant-Wide Guardrails

This scenario deploys decommissioning guardrails with two required inputs:

1. A management group where the Policy initiative is created and assigned.
2. One or more subscriptions that receive a `ReadOnly` lock.

By default, it does not move subscriptions, remove RBAC assignments, or configure PIM.

PIM recovery access is available as an optional final control and is disabled by default.

## Prerequisites

- PowerShell 7
- Azure PowerShell modules `Az.Accounts` and `Az.Resources`
- Bicep CLI available as `bicep` on `PATH`
- An existing Azure PowerShell context for the target tenant
- Permission to deploy Policy at the management group and locks at every listed subscription
- When recovery access is enabled, permission to read and create PIM role eligibility at the management group

The scripts never initiate Azure sign-in. Sign in first and verify the context:

```powershell
Connect-AzAccount -Tenant '<tenant-id>'
Get-AzContext
```

## Preview

Run from the project root:

```powershell
./scripts/Deploy-TenantGuardrails.ps1 `
  -ManagementGroupId 'contoso-platform' `
  -SubscriptionId @(
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222'
  ) `
  -EnforcementMode Default `
  -WhatIf
```

The preview is local intent only. It does not contact Azure or produce an Azure resource-level diff. Including `-EnforcementMode Default` confirms that the subsequent deployment is intended to enforce the Policy deny effects.

## Deploy

```powershell
./scripts/Deploy-TenantGuardrails.ps1 `
  -ManagementGroupId 'contoso-platform' `
  -SubscriptionId @(
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222'
  ) `
  -EnforcementMode Default
```

> [!WARNING]
> `-EnforcementMode Default` activates the Policy deny effects for subscriptions beneath the management group. Rehearse the deployment against disposable subscriptions and review the target management-group hierarchy before using it in production.

During deployment, PowerShell displays an elapsed-time progress indicator for the management-group stack and then for each subscription lock. Each phase prints its completion time before the next phase starts. If Azure fails a deployment, the progress indicator closes and the original Azure error is returned.

The deployment tool compiles each local Bicep template to a temporary ARM JSON template before starting the asynchronous Azure job. The temporary file is removed when that phase finishes.

The script defaults to `Default`, which enforces the Policy deny effects. The examples specify `-EnforcementMode Default` explicitly so the intended behavior is clear. Use `-EnforcementMode DoNotEnforce` only when evaluation without blocking resource operations is intentional.

```powershell
./scripts/Deploy-TenantGuardrails.ps1 `
  -ManagementGroupId 'contoso-platform' `
  -SubscriptionId @('11111111-1111-1111-1111-111111111111') `
  -EnforcementMode Default
```

## Parameters

| Parameter | Required | Purpose |
|---|---:|---|
| `ManagementGroupId` | Yes | Existing management group where the initiative is created and assigned. |
| `SubscriptionId` | Yes | One or more subscriptions that receive a `ReadOnly` lock. |
| `EnforcementMode` | No | Defaults to `Default`, which enforces the Policy deny effects. Use `DoNotEnforce` only to evaluate compliance without blocking operations. |
| `EnableRecoveryAccess` | No | Enables PIM eligibility for Contributor and User Access Administrator. Disabled by default. |
| `RecoveryAdministratorsGroupId` | When PIM is enabled | Microsoft Entra object ID of the Recovery Administrators group. |
| `EligibilityDuration` | No | Finite ISO 8601 eligibility duration. Defaults to `P365D`. |
| `LockName` | No | Lock name; defaults to `decommission-quarantine`. |
| `LockNotes` | No | Operational context stored on every lock. |
| `DeploymentLocation` | No | Location for deployment-stack metadata. |

## Scope Behavior

Policy and locks are independent:

- Subscriptions beneath the selected management group inherit the initiative assignment.
- Every listed subscription receives a lock, regardless of its management-group placement.
- The script does not move subscriptions into the selected management group.
- Optional PIM recovery roles are assigned at the selected management group and are inherited only by subscriptions beneath it.

## Optional Recovery Access

Enable recovery access only for a dedicated, tightly controlled Microsoft Entra group:

```powershell
./scripts/Deploy-TenantGuardrails.ps1 `
  -ManagementGroupId 'contoso-platform' `
  -SubscriptionId @('11111111-1111-1111-1111-111111111111') `
  -EnforcementMode Default `
  -EnableRecoveryAccess `
  -RecoveryAdministratorsGroupId '22222222-2222-2222-2222-222222222222' `
  -EligibilityDuration 'P365D'
```

This creates separate eligible assignments for the built-in **Contributor** and **User Access Administrator** roles. It does not create custom roles or configure approval, MFA, activation duration, approvers, or notification settings in the PIM role policy.

Before deployment, the tool queries the current PIM eligibility schedules and schedule instances for the group at the selected management group. It reports each role as either `Current eligibility exists` or `Missing; will create`. Existing current eligibility is retained; a missing role is submitted with a fresh PIM request ID. Historical `Provisioned` request records are not treated as proof that eligibility is still current.

An eligible assignment is not an active role assignment. A group member must activate the required role through PIM, subject to the management group's PIM role settings.

## Managed Resources

The script creates one management-group deployment stack named `tenant-wide-decommission-guardrails`. It creates one subscription deployment stack named `tenant-decommission-quarantine-lock` in each listed subscription.

All stacks use `ActionOnUnmanage DeleteAll`. Removing a managed resource from a template or deleting a stack can delete the underlying Policy or lock.

A pre-existing subscription `ReadOnly` lock can block Azure from creating or updating the subscription deployment stack, including a lock left by an interrupted or earlier deployment. Remove the old lock before redeploying. Use the removal tool when the lock belongs to this scenario.

## Remove The Scenario

Use the same management group and complete subscription list used for deployment. Preview first:

```powershell
./scripts/Remove-TenantGuardrails.ps1 `
  -ManagementGroupId 'contoso-platform' `
  -SubscriptionId @(
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222'
  ) `
  -WhatIf
```

Remove the controls after reviewing the preview:

```powershell
./scripts/Remove-TenantGuardrails.ps1 `
  -ManagementGroupId 'contoso-platform' `
  -SubscriptionId @(
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222'
  )
```

The removal tool explicitly deletes each named `ReadOnly` lock before deleting its subscription deployment stack. Azure otherwise blocks the stack from deleting itself because the subscription scope is locked. The tool then deletes the management-group stack, Policy assignment, and initiative. Interrupted cleanup can be rerun safely when the named lock is already absent. It does not move subscriptions, change ordinary RBAC assignments, or explicitly revoke PIM eligibility. Review or remove recovery eligibility separately when it is no longer required.

During removal, PowerShell displays the same spinner and elapsed-time progress used for deployment while each subscription stack and the management-group stack are deleted. Lock deletion and final absence checks normally complete quickly and run synchronously.

After a real removal, the tool queries Azure and prints `LockAbsent`, `SubscriptionStackAbsent`, `ManagementGroupStackAbsent`, `PolicyAssignmentAbsent`, and `PolicyInitiativeAbsent` for each supplied subscription. All five values should be `True`. `-WhatIf` does not query Azure and therefore prints planned actions instead of this verification summary.

## Validate Locally

```powershell
az bicep build --file ./infra/tenant-wide/tenant-guardrails.bicep
az bicep build --file ./infra/tenant-wide/subscription-lock.bicep
az bicep build-params --file ./infra/tenant-wide/tenant-guardrails.bicepparam
./tests/Smoke.Tests.ps1
```
