# Architecture And Safety Reference

[Back to master README](../README.md)

## Control Model

The solution combines four control-plane controls:

| Control | Purpose |
|---|---|
| Management-group Policy | Blocks new indexed resource types and protects selected critical types from deletion. |
| Permanent Reader | Preserves audit and operational visibility. |
| PIM eligibility | Provides approval-gated User Access Administrator and Contributor recovery paths. |
| Subscription `ReadOnly` lock | Supplies the broad control-plane freeze. |

No single control is a complete quarantine:

- The built-in `Allowed resource types` Policy uses `Indexed` mode.
- RBAC is additive; Reader does not cancel existing write roles.
- Moving a subscription does not remove direct subscription or child-scope assignments.
- A management lock does not revoke data-plane credentials.

## Scope Boundary

The baseline controls Azure Resource Manager operations. It does not revoke:

- Storage keys or SAS tokens.
- SQL credentials.
- Key Vault data-plane access.
- VM local credentials.
- Application traffic.
- Other service-specific data-plane access.

A `ReadOnly` lock also blocks many POST/action operations, including VM start and restart. It can disrupt backup cleanup, Advisor, automation, monitoring configuration, and similar services. Test representative retained services in a disposable subscription.

## Deployment Stacks

| Scope | Stack | Managed resources |
|---|---|---|
| Management group | `tenant-decommission-governance` | Policy initiative, Policy assignment, Reader role assignments, and PIM eligibility requests. |
| Subscription | `tenant-decommission-quarantine-lock` | Subscription-level `ReadOnly` management lock. |

Both stacks use:

- `ActionOnUnmanage DeleteAll`
- `DenySettingsMode None`

Removing a resource from a template or deleting a stack can remove resources managed by that stack. Deployment-stack deny settings are deliberately disabled; this solution uses Policy, direct-RBAC cleanup, and the explicit lock.

Deployment stacks do not currently provide an Azure-side resource-level what-if through these scripts. Script `-WhatIf` output is an intent preview, not a comparison against deployed Azure state.

## Policy Modes

The Policy definitions retain `Deny` and `DenyAction` effects in both modes:

| Assignment mode | Behavior |
|---|---|
| `DoNotEnforce` | Evaluate and report without applying deny effects. |
| `Default` | Evaluate and enforce configured effects. |

The deployment defaults to `Default`. Use `DoNotEnforce` only for an explicitly approved evaluation-only deployment that must not apply deny effects.

## Access Inheritance

Root and parent management-group role assignments continue to inherit. Direct subscription, resource-group, and resource assignments remain after a management-group move. The readiness evidence records both overall RBAC context and direct write assignments that require an admission decision.

## Rehearsal Requirement

Before production use, rehearse:

1. Governance deployment with the default `Default` enforcement mode.
2. PIM activation.
3. Readiness and RBAC decisions.
4. Admission and lock deployment.
5. Verification and negative access tests.
6. Timed unlock and Policy exemption.
7. Relock and reverification.
8. Final destruction and evidence capture.
