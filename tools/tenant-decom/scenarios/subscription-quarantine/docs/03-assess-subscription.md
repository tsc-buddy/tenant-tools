# Step 3: Assess A Subscription

[Previous: Configure PIM](02-configure-pim.md) | [Back to master README](../README.md) | [Next: Admit a subscription](04-admit-subscription.md)

This step is read-only. It creates compact evidence for an admission decision and does not move, modify, or lock the subscription.

## Collect Evidence

```powershell
$subscriptionId = '<subscription-id>'
$evidencePath = ".\quarantine-evidence\$subscriptionId.json"

./scripts/Get-QuarantineReadiness.ps1 `
  -SubscriptionId $subscriptionId `
  -OutputPath $evidencePath
```

The JSON contains counts and short records rather than full Azure resource objects.

## Command Output

| Field | Meaning | Action |
|---|---|---|
| `SubscriptionId` | Assessed subscription. | Confirm it is the intended subscription. |
| `ResourceCount` | Total discovered resources. | Compare with retained-estate records. |
| `DirectWriteAssignmentCount` | Direct assignments classified as write-capable or requiring conservative review. | Review every corresponding JSON row. |
| `LockCount` | Subscription-scope locks found. | Confirm each lock's owner and purpose. |
| `PolicyAssignmentCount` | Policy assignments returned for the scope. | Review assignments and exemptions for conflicts. |
| `EvidencePath` | Generated JSON path. | Retain it with the approved change record. |

## Review The JSON

| Section | Decision |
|---|---|
| `Subscription` and `ParentManagementGroupId` | Confirm identity, tenant, and current placement. Record the parent for rollback. |
| `ResourceCount` and `ResourceTypeSummary` | Confirm the retained estate broadly matches migration and destruction records. Use a separate inventory if item-level resources are required. |
| `RoleAssignments` | Review overall access context, including inherited assignments that admission does not remove. |
| `DirectControlPlaneWriteRoles` | Mark every row as **remove**, **approve to remain**, or **investigate**. Record principal object ID, role, scope, and decision in the change ticket. |
| `Locks` | Confirm ownership and whether a lock conflicts with admission. Do not remove locks without approval. |
| `PolicyAssignments` and `PolicyExemptions` | Resolve unexplained exemptions and conflicting Policy behavior. |

Inspect the direct assignment decision list:

```powershell
$evidence = Get-Content $evidencePath -Raw | ConvertFrom-Json

$evidence.DirectControlPlaneWriteRoles |
  Select-Object DisplayName, ObjectId, RoleDefinitionName, Scope, ClassificationBasis |
  Format-Table -AutoSize
```

## Classification Safety

- `RoleDefinitionActions` means Azure returned the role definition and the script inspected its actions.
- `ConservativeFallback` means role-definition lookup failed. The script excluded only built-in Reader and listed every other direct role for review.

**Do not use automatic RBAC removal if any row uses `ConservativeFallback`.** Resolve role-definition lookup, rerun readiness, and make removal decisions from an authoritative `RoleDefinitionActions` result.

## Build The Allowlist

Only include exceptional direct write principals that have formal approval to remain:

```powershell
$approvedWritePrincipalIds = @(
  '<approved-principal-object-id>'
)
```

Use an empty array when none may remain:

```powershell
$approvedWritePrincipalIds = @()
```

Do not add Reader or Recovery Administrators merely because they are part of this solution. Prefer inherited PIM access over retained direct write access.

## Readiness Gate

Before admission, confirm:

- Migration acceptance and retained dependencies.
- Workloads are in the approved retained state.
- Rollback artifacts and Activity Log evidence are preserved.
- Every direct write assignment has a documented decision.
- Locks, Policy assignments, and exemptions are reviewed.
- Retention date, owning team, change reference, and destruction ticket are recorded.
- The JSON is stored with the change record.

**Stop if:** any item is unresolved or classification used `ConservativeFallback` for an assignment being considered for removal.

When approved, continue to [Step 4: Admit A Subscription](04-admit-subscription.md).
