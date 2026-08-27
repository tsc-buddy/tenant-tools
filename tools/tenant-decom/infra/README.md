# Infrastructure

Bicep artifacts are separated by deployment scenario.

| Directory | Purpose |
|---|---|
| `tenant-wide/` | Management-group initiative and assignment plus the subscription `ReadOnly` lock used by the simple tenant-wide deployment. |
| `subscription-quarantine/` | Management-group Policy, Reader and PIM recovery access, plus the subscription lock used by the full quarantine lifecycle. |

Each scenario owns its Bicep parameters. Operator commands and deployment order are documented under the matching directory in `scenarios/`.
