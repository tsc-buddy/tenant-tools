# Step 5: Verify Enforcement

[Previous: Admit a subscription](04-admit-subscription.md) | [Back to master README](../README.md) | [Next: Recovery and destruction](06-recovery-and-destruction.md)

Verification confirms the expected configuration after Azure propagation.

## Run The Configuration Check

```powershell
./scripts/Test-SubscriptionQuarantine.ps1 `
  -SubscriptionId $subscriptionId `
  -ExpectedManagementGroupId $managementGroupId `
  -ApprovedWritePrincipalId $approvedWritePrincipalIds
```

The script checks:

| Check | Passing result |
|---|---|
| `ParentManagementGroup` | Subscription is directly under the expected quarantine management group. |
| `ReadOnlyLock` | Exactly one named quarantine lock exists and its level is `ReadOnly`. |
| `InheritedQuarantinePolicy` | The quarantine Policy assignment is visible at subscription scope. |
| `UnapprovedDirectWriteAssignments` | No direct write assignment exists outside the approved principal allowlist. |

The command fails if any check fails.

## Test Effective Behavior

Configuration inspection does not prove effective access for nested groups, cached tokens, data-plane credentials, or every Azure action. Test with former operator and automation identities that these control-plane operations fail:

- Create, update, and delete resources.
- Start or restart a VM.
- Create or remove role assignments.
- Create Policy exemptions.
- Remove the quarantine lock.

Also confirm the approved Reader group can inspect retained resources and the PIM activation paths work as designed.

## Verify Policy Enforcement

The governance deployment defaults to `Default`, which activates the Policy `Deny` and `DenyAction` effects. After Azure Policy propagation:

1. Confirm `enforcementMode` in `infra/subscription-quarantine/governance.bicepparam` is `Default`.
2. Verify the governance stack succeeded and the inherited assignment is visible.
3. Perform the negative access tests against a disposable admitted subscription.
4. Complete the rollback, relock, and destruction rehearsal before admitting production subscriptions.

Do not admit production subscriptions while the Policy is `DoNotEnforce` unless that exception is explicitly approved and documented.

## Completion Gate

The subscription is quarantined only when:

- Every configuration check passes.
- Negative access tests pass.
- Reader and PIM paths are tested.
- Evidence and results are attached to the change record.

**Stop if:** any test fails. Investigate and rerun verification; do not treat partial enforcement as successful quarantine.

For approved rollback or destruction, use [Recovery And Destruction](06-recovery-and-destruction.md).
