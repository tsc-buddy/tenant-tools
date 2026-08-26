targetScope = 'managementGroup'

@sys.description('Whether the tenant guardrails Policy assignment is enforced.')
param enforcementMode 'Default' | 'DoNotEnforce' = 'DoNotEnforce'

@sys.description('Whether to create PIM-eligible recovery roles at the selected management group.')
param enableRecoveryAccess bool = false

@sys.description('Microsoft Entra group object ID eligible for Contributor and User Access Administrator. Required when recovery access is enabled.')
param recoveryAdministratorsGroupId string = ''

@sys.description('Whether the Contributor PIM eligibility request must be created. Set by the deployment tool after checking existing eligibility.')
param createContributorEligibility bool = false

@sys.description('Whether the User Access Administrator PIM eligibility request must be created. Set by the deployment tool after checking existing eligibility.')
param createUserAccessAdministratorEligibility bool = false

@sys.description('Unique request ID used when creating Contributor PIM eligibility.')
param contributorEligibilityRequestId string

@sys.description('Unique request ID used when creating User Access Administrator PIM eligibility.')
param userAccessAdministratorEligibilityRequestId string

@sys.description('ISO 8601 duration for Recovery Administrators PIM eligibility. Must comply with the tenant PIM policy.')
@minLength(1)
param eligibilityDuration string = 'P365D'

@sys.description('Resource types protected from deletion.')
param protectedResourceTypes string[] = [
  'Microsoft.Compute/virtualMachines'
  'Microsoft.Compute/disks'
  'Microsoft.Network/virtualNetworks'
  'Microsoft.Network/networkInterfaces'
  'Microsoft.Network/publicIPAddresses'
  'Microsoft.RecoveryServices/vaults'
  'Microsoft.Storage/storageAccounts'
]

var builtInPolicyDefinitionIds = {
  allowedResourceTypes: tenantResourceId('Microsoft.Authorization/policyDefinitions', 'a08ec900-254a-4555-9bf5-e42af04b5c5c')
  denyResourceTypeDeletion: tenantResourceId('Microsoft.Authorization/policyDefinitions', '78460a36-508a-49a4-b2b2-2f5ec564f4bb')
}

var builtInRoleDefinitionIds = {
  contributor: tenantResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  userAccessAdministrator: tenantResourceId('Microsoft.Authorization/roleDefinitions', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')
}

resource tenantGuardrailsInitiative 'Microsoft.Authorization/policySetDefinitions@2023-04-01' = {
  name: 'tenant-decommission-guardrails'
  properties: {
    displayName: 'Tenant Decommission Guardrails'
    description: 'Prevents new resource creation and protects selected resource types from deletion.'
    metadata: {
      category: 'Decommissioning'
      version: '1.0.0'
    }
    policyType: 'Custom'
    parameters: {
      protectedResourceTypes: {
        type: 'Array'
        metadata: {
          displayName: 'Resource types protected from deletion'
        }
      }
    }
    policyDefinitions: [
      {
        policyDefinitionReferenceId: 'deny-new-indexed-resource-types'
        policyDefinitionId: builtInPolicyDefinitionIds.allowedResourceTypes
        parameters: {
          listOfResourceTypesAllowed: {
            value: []
          }
          effect: {
            value: 'Deny'
          }
        }
      }
      {
        policyDefinitionReferenceId: 'protect-critical-resource-types-from-deletion'
        policyDefinitionId: builtInPolicyDefinitionIds.denyResourceTypeDeletion
        parameters: {
          listOfResourceTypesDisallowedForDeletion: {
            value: '[parameters(\'protectedResourceTypes\')]'
          }
          effect: {
            value: 'DenyAction'
          }
        }
      }
    ]
  }
}

resource tenantGuardrailsAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'decom-guardrails'
  location: 'global'
  properties: {
    displayName: 'Tenant Decommission Guardrails'
    description: 'Guardrails inherited by subscriptions beneath this management group.'
    policyDefinitionId: tenantGuardrailsInitiative.id
    enforcementMode: enforcementMode
    parameters: {
      protectedResourceTypes: {
        value: protectedResourceTypes
      }
    }
    metadata: {
      category: 'Decommissioning'
    }
  }
}

resource recoveryAdministratorUserAccessEligibility 'Microsoft.Authorization/roleEligibilityScheduleRequests@2020-10-01-preview' = if (enableRecoveryAccess && createUserAccessAdministratorEligibility) {
  name: userAccessAdministratorEligibilityRequestId
  properties: {
    principalId: recoveryAdministratorsGroupId
    roleDefinitionId: builtInRoleDefinitionIds.userAccessAdministrator
    requestType: 'AdminAssign'
    justification: 'Eligible access for tenant decommission RBAC and lock administration.'
    scheduleInfo: {
      expiration: {
        type: 'AfterDuration'
        duration: eligibilityDuration
      }
    }
  }
}

resource recoveryAdministratorContributorEligibility 'Microsoft.Authorization/roleEligibilityScheduleRequests@2020-10-01-preview' = if (enableRecoveryAccess && createContributorEligibility) {
  name: contributorEligibilityRequestId
  properties: {
    principalId: recoveryAdministratorsGroupId
    roleDefinitionId: builtInRoleDefinitionIds.contributor
    requestType: 'AdminAssign'
    justification: 'Eligible recovery access for approved tenant decommission operations.'
    scheduleInfo: {
      expiration: {
        type: 'AfterDuration'
        duration: eligibilityDuration
      }
    }
  }
}

@sys.description('Resource ID of the tenant guardrails initiative.')
output policySetDefinitionId string = tenantGuardrailsInitiative.id

@sys.description('Resource ID of the tenant guardrails assignment.')
output policyAssignmentId string = tenantGuardrailsAssignment.id
