# Tools

Reusable PowerShell entry points and shared functions for the project scenarios.

| Tool | Scenario | Purpose |
|---|---|---|
| `Deploy-TenantGuardrails.ps1` | Tenant-wide | Assign the initiative at a management group and lock specified subscriptions. |
| `Remove-TenantGuardrails.ps1` | Tenant-wide | Remove specified subscription lock stacks, then remove the management-group Policy stack. |
| `Deploy-QuarantineGovernance.ps1` | Subscription quarantine | Deploy Policy, Reader access, and PIM eligibility. |
| `Get-QuarantineReadiness.ps1` | Subscription quarantine | Capture compact pre-change evidence. |
| `Enter-SubscriptionQuarantine.ps1` | Subscription quarantine | Move, optionally clean direct RBAC, and lock a subscription. |
| `Test-SubscriptionQuarantine.ps1` | Subscription quarantine | Verify placement and guardrails. |
| `Exit-SubscriptionQuarantine.ps1` | Subscription quarantine | Remove the managed lock for recovery or destruction. |
| `Remove-QuarantineGovernance.ps1` | Subscription quarantine | Remove the management-group governance stack. |
| `Quarantine.Common.psm1` | Shared | Common validation, RBAC discovery, and lock deployment functions. |

Run public tools from the project root. Tools reuse an existing Azure PowerShell context and never initiate sign-in.
