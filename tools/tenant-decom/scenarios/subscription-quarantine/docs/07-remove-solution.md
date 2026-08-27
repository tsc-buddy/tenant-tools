# Remove The Solution

[Previous: Recovery and destruction](06-recovery-and-destruction.md) | [Back to master README](../README.md)

Remove shared governance only after no subscription depends on it.

## Removal Gate

Confirm every quarantined subscription has completed destruction, rollback, transfer, or replacement governance. For each remaining subscription:

1. Remove its quarantine lock stack through `Exit-SubscriptionQuarantine.ps1`.
2. Remove or relocate direct subscription and child-scope assignments according to the approved offboarding record.
3. Verify no retained subscription still inherits required controls from the quarantine management group.

## Inspect Managed Governance Resources

```powershell
(Get-AzManagementGroupDeploymentStack `
  -ManagementGroupId $managementGroupId `
  -Name 'tenant-decommission-governance').Resources
```

The stack uses `ActionOnUnmanage DeleteAll`. Removing it asks Azure to delete its managed Policy initiative, Policy assignment, Reader assignments, and PIM eligibility request resources.

## Preview Governance Removal

```powershell
./scripts/Remove-QuarantineGovernance.ps1 `
  -ManagementGroupId $managementGroupId `
  -WhatIf
```

**Stop if:** any active subscription still depends on these controls or the target stack is wrong.

## Remove Governance

Run the same command without `-WhatIf`.

Then verify the stack is absent:

```powershell
Get-AzManagementGroupDeploymentStack `
  -ManagementGroupId $managementGroupId `
  -Name 'tenant-decommission-governance' `
  -ErrorAction SilentlyContinue
```

No output means the named stack is absent.

## Verify Subscription Stacks

For each former quarantine subscription:

```powershell
Set-AzContext -SubscriptionId $subscriptionId
Get-AzSubscriptionDeploymentStack `
  -Name 'tenant-decommission-quarantine-lock' `
  -ErrorAction SilentlyContinue
```

No output means the named lock stack is absent.

## Verify PIM

In Microsoft Entra PIM, confirm the Recovery Administrators group no longer has eligible User Access Administrator or Contributor assignments at the management-group scope. Submit `AdminRemove` requests for effective eligibility that remains.

The solution does not delete the pre-existing management group and does not cancel subscriptions.
