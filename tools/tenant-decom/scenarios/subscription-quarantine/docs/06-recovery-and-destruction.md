# Recovery And Destruction

[Previous: Verify enforcement](05-verify-enforcement.md) | [Back to master README](../README.md) | [Next: Remove the solution](07-remove-solution.md)

Use this runbook for an approved temporary rollback or final destruction. Do not remove the management-group governance stack for subscription-level work.

## Preview Lock Removal

Activate the approved PIM role or roles required by the tenant access model, then run:

```powershell
./scripts/Exit-SubscriptionQuarantine.ps1 `
  -SubscriptionId $subscriptionId `
  -Mode Rollback `
  -ChangeReference 'CHG000001' `
  -WhatIf
```

Use `-Mode Destruction` for final destruction.

The script removes the `tenant-decommission-quarantine-lock` deployment stack with `ActionOnUnmanage DeleteAll`, which also removes its managed `ReadOnly` lock. It does not remove management-group Policy, Reader, or PIM controls.

**Stop if:** the subscription, mode, change reference, stack name, or lock name is wrong.

## Remove The Lock

Rerun the approved command without `-WhatIf`.

After lock removal:

1. Create a narrowly scoped Policy exemption only if required.
2. Give the exemption an explicit expiry and justification.
3. Activate Contributor only for the approved resource work.
4. Perform only the approved rollback or destruction actions.

Policy exemptions remain an explicit governance action because approval and parameter requirements vary by tenant.

## Close A Temporary Rollback

1. Stop or deallocate the workload as required.
2. Remove the temporary Policy exemption.
3. Reapply the subscription lock by rerunning the approved admission/relock process.
4. Deactivate privileged roles.
5. Rerun verification.
6. Archive updated evidence and results.

## Complete Final Destruction

1. Confirm approvals, dependencies, retention expiry, and legal or audit requirements.
2. Remove resources in dependency order.
3. Confirm no residual billable resources remain.
4. Confirm Policy exemptions and direct access created for destruction are removed.
5. Complete the subscription billing-cancellation process separately.
6. Preserve destruction evidence.

The scripts do not cancel subscriptions.
