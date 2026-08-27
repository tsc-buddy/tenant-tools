# Step 4: Admit A Subscription

[Previous: Assess a subscription](03-assess-subscription.md) | [Back to master README](../README.md) | [Next: Verify enforcement](05-verify-enforcement.md)

Admission captures fresh evidence, checks direct write access, moves the subscription into the quarantine management group, optionally removes unapproved direct write assignments, and deploys a subscription-level `ReadOnly` lock.

## Before Starting

Confirm that:

- The readiness review is approved and attached to the change record.
- Every direct assignment has a documented decision.
- No removal decision relies on `ConservativeFallback` classification.
- `$subscriptionId`, `$managementGroupId`, and `$approvedWritePrincipalIds` are set.
- The executing identity will retain the access required after RBAC cleanup and the management-group move.

## Parameter Reference

| Parameter | Required | Default | Meaning and guidance |
|---|---|---|---|
| `SubscriptionId` | Yes | None | GUID of the subscription being admitted. Confirm it matches the approved readiness evidence and change record. |
| `ManagementGroupId` | Yes | None | ID, not display name, of the existing quarantine management group. The script moves the subscription directly beneath this group. |
| `ChangeReference` | Yes | None | Approved change, incident, or destruction-ticket reference. It is written into the lock notes for operational traceability. |
| `OwningTeam` | Yes | None | Team accountable for the retained subscription during quarantine. It is written into the lock notes. |
| `RetentionDays` | No | `30` | Number of days from admission until the planned destruction date recorded in the lock notes. Valid range is 1 to 365. This records intent; it does not schedule automatic deletion. |
| `ApprovedWritePrincipalId` | No | Empty array | Microsoft Entra object IDs of exceptional direct write-capable principals formally approved to remain. Any direct write assignment belonging to one of these principals is excluded from removal. Build this list from `DirectControlPlaneWriteRoles` in the approved readiness JSON. Do not supply role-assignment IDs, role-definition IDs, names, application/client IDs, Reader groups, or the inherited Recovery Administrators group. Prefer an empty array and inherited PIM access where possible. |
| `RemoveUnapprovedDirectWriteAssignments` | No | Off | Authorizes removal of direct write-capable assignments whose principal object ID is not in `ApprovedWritePrincipalId`. Without this switch, the script stops if any unapproved direct write assignment exists. Never use it when readiness classification is `ConservativeFallback` or assignment removal is not explicitly approved. |
| `EvidenceDirectory` | No | `./quarantine-evidence` under the current directory | Directory for the fresh timestamped readiness JSON captured immediately before admission. Preserve this evidence with the change record. |
| `LockStackName` | No | `tenant-decommission-quarantine-lock` | Stable subscription deployment-stack name managing the quarantine lock. Keep the default unless the subscription already has a deliberately different solution instance. |
| `DeploymentLocation` | No | `australiaeast` | Azure region that stores deployment-stack metadata. The subscription lock itself is not a regional resource. Use an approved region if deployment metadata residency requires a different location. |

`ApprovedWritePrincipalId` and `RemoveUnapprovedDirectWriteAssignments` work together:

| Allowlist/removal choice | Result |
|---|---|
| Empty allowlist, removal switch omitted | Admission stops if any direct write assignment exists. Nothing is removed. |
| Populated allowlist, removal switch omitted | Admission stops if a direct write assignment exists for any principal outside the allowlist. Nothing is removed. |
| Empty allowlist, removal switch present | Every direct write assignment identified by the authoritative readiness check is removed. |
| Populated allowlist, removal switch present | Assignments for allowlisted principals remain; all other identified direct write assignments are removed. |

Example allowlist:

```powershell
$approvedWritePrincipalIds = @(
  '<approved-microsoft-entra-object-id>'
)
```

Use an empty array when no direct write principal is approved to remain:

```powershell
$approvedWritePrincipalIds = @()
```

## Preview Admission

```powershell
./scripts/Enter-SubscriptionQuarantine.ps1 `
  -SubscriptionId $subscriptionId `
  -ManagementGroupId $managementGroupId `
  -ChangeReference 'CHG000000' `
  -OwningTeam 'Cloud Operations' `
  -ApprovedWritePrincipalId $approvedWritePrincipalIds `
  -RemoveUnapprovedDirectWriteAssignments `
  -WhatIf
```

The allowlist uses principal object IDs. It applies to exceptional direct write access on this subscription, not inherited Reader or PIM groups.

The script refuses admission when unapproved direct write assignments remain unless `-RemoveUnapprovedDirectWriteAssignments` is supplied. Include that switch only when removal is explicitly approved.

The preview should describe these intended actions:

1. Capture fresh readiness evidence.
2. Move the subscription to the quarantine management group.
3. Remove each unapproved direct write assignment when the removal switch is present.
4. Create or update the `tenant-decommission-quarantine-lock` stack.
5. Create the `decommission-quarantine` subscription `ReadOnly` lock.

**Stop if:** the subscription, management group, removal list, owner, change reference, or planned retention period is wrong.

## Admit The Subscription

Rerun the reviewed command without `-WhatIf`:

```powershell
./scripts/Enter-SubscriptionQuarantine.ps1 `
  -SubscriptionId $subscriptionId `
  -ManagementGroupId $managementGroupId `
  -ChangeReference 'CHG000000' `
  -OwningTeam 'Cloud Operations' `
  -ApprovedWritePrincipalId $approvedWritePrincipalIds `
  -RemoveUnapprovedDirectWriteAssignments
```

Omit `-RemoveUnapprovedDirectWriteAssignments` when no removal is approved or required. If unapproved assignments exist, the script will stop rather than continue.

## Expected Outcome

The result includes:

- Target management-group ID.
- Fresh evidence path.
- Removed-assignment count.
- Planned destruction date.
- Lock and lock-stack names.

The lock notes contain the change reference, quarantine date, planned destruction date, and owning team.

Allow time for management-group, RBAC, token, and Policy propagation. Do not assume immediate consistency.

**Stop if:** any operation fails. Do not manually complete only part of admission without reviewing the resulting state and change record.

Continue to [Step 5: Verify Enforcement](05-verify-enforcement.md).
