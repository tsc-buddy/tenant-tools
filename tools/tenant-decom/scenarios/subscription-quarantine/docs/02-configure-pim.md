# Step 2: Configure PIM

[Previous: Deploy governance](01-deploy-governance.md) | [Back to master README](../README.md) | [Next: Assess a subscription](03-assess-subscription.md)

The governance template creates eligible assignments. It does not configure PIM activation policies.

## Find The Eligible Assignments

Use the [Microsoft Entra admin center](https://entra.microsoft.com), not the management group's **Access control (IAM)** page:

1. Browse to **ID Governance** > **Privileged Identity Management** > **Azure resources**.
2. In the resource selector, choose **Management group**.
3. Select the quarantine management group, then select **Select** to open it in PIM.
4. Under **Manage**, open **Roles**.
5. Open the **Eligible roles** tab.

The Recovery Administrators group should have separate eligible assignments for **User Access Administrator** and **Contributor**.

## Configure Both Roles

With the quarantine management group still open in PIM:

1. Under **Manage**, open **Settings**.
2. Select **User Access Administrator**, then edit its activation settings.
3. Select **Contributor** and configure it separately.

Recommended activation controls:

- Require approval.
- Require MFA.
- Require justification and a change reference where supported.
- Set a short maximum activation duration, such as one to four hours.
- Configure notifications.
- Configure recurring access reviews.

## Role Purposes

| Role | Intended use |
|---|---|
| User Access Administrator | Approved Azure RBAC administration. |
| Contributor | Approved resource recovery or destruction work. |

Members should activate only the role required for the approved task. Keeping the roles eligible avoids standing privileged access.

## Test PIM

Sign in as a member of Recovery Administrators and confirm both roles appear under **PIM > My roles > Azure resources**. Test the approval and activation flow in a non-production context.

**Stop if:** either role is missing, activation bypasses required controls, approval fails, or eligibility expiration does not match policy.

PIM eligibility is created through `AdminAssign` schedule requests. During final teardown, verify the resulting role eligibility schedules are gone; deleting a request record alone is not proof of revocation.

When both activation paths are tested, continue to [Step 3: Assess A Subscription](03-assess-subscription.md).