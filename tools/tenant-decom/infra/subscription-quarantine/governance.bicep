targetScope = 'managementGroup'

type governanceGroups = {
  @description('Microsoft Entra group object IDs receiving permanent Reader access.')
  readers: string[]

  @description('Microsoft Entra group object ID eligible for User Access Administrator and Contributor through PIM.')
  recoveryAdministrators: string
}

@sys.description('Microsoft Entra groups used to operate quarantined subscriptions.')
param groups governanceGroups

@sys.description('Resource types protected from deletion when the ReadOnly lock is temporarily removed.')
param protectedResourceTypes string[] = [
  'Microsoft.Compute/virtualMachines'
  'Microsoft.Compute/disks'
  'Microsoft.Network/virtualNetworks'
  'Microsoft.Network/networkInterfaces'
  'Microsoft.Network/publicIPAddresses'
  'Microsoft.RecoveryServices/vaults'
  'Microsoft.Storage/storageAccounts'
]

@sys.description('Whether the quarantine policy assignment is enforced.')
param enforcementMode 'Default' | 'DoNotEnforce' = 'Default'

@sys.description('ISO 8601 duration for Recovery Administrator PIM eligibility. Must comply with the tenant PIM policy.')
@minLength(1)
param eligibilityDuration string = 'P365D'

var builtInPolicyDefinitionIds = {
  allowedResourceTypes: tenantResourceId('Microsoft.Authorization/policyDefinitions', 'a08ec900-254a-4555-9bf5-e42af04b5c5c')
  denyResourceTypeDeletion: tenantResourceId('Microsoft.Authorization/policyDefinitions', '78460a36-508a-49a4-b2b2-2f5ec564f4bb')
}

var builtInRoleDefinitionIds = {
  contributor: tenantResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  reader: tenantResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  userAccessAdministrator: tenantResourceId('Microsoft.Authorization/roleDefinitions', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')
}

resource quarantineInitiative 'Microsoft.Authorization/policySetDefinitions@2023-04-01' = {
  name: 'subscription-quarantine'
  properties: {
    displayName: 'Subscription Quarantine Guardrails'
    description: 'Defense-in-depth controls for subscriptions retained temporarily during tenant decommissioning.'
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

resource quarantinePolicyAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'subscription-quarantine'
  location: 'global'
  properties: {
    displayName: 'Enforce subscription quarantine guardrails'
    description: 'Inherited by subscriptions placed beneath this quarantine management group.'
    policyDefinitionId: quarantineInitiative.id
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

resource readerAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principalId in groups.readers: {
  name: guid(managementGroup().id, principalId, builtInRoleDefinitionIds.reader)
  properties: {
    principalId: principalId
    principalType: 'Group'
    roleDefinitionId: builtInRoleDefinitionIds.reader
    description: 'Permanent read-only access to quarantined subscriptions.'
  }
}]

resource recoveryAdministratorUserAccessEligibility 'Microsoft.Authorization/roleEligibilityScheduleRequests@2020-10-01-preview' = {
  name: guid(managementGroup().id, groups.recoveryAdministrators, builtInRoleDefinitionIds.userAccessAdministrator, 'eligible')
  properties: {
    principalId: groups.recoveryAdministrators
    roleDefinitionId: builtInRoleDefinitionIds.userAccessAdministrator
    requestType: 'AdminAssign'
    justification: 'Eligible access for subscription quarantine role and lock administration.'
    scheduleInfo: {
      expiration: {
        type: 'AfterDuration'
        duration: eligibilityDuration
      }
    }
  }
}

resource recoveryAdministratorContributorEligibility 'Microsoft.Authorization/roleEligibilityScheduleRequests@2020-10-01-preview' = {
  name: guid(managementGroup().id, groups.recoveryAdministrators, builtInRoleDefinitionIds.contributor, 'eligible')
  properties: {
    principalId: groups.recoveryAdministrators
    roleDefinitionId: builtInRoleDefinitionIds.contributor
    requestType: 'AdminAssign'
    justification: 'Eligible recovery access for approved rollback or final destruction.'
    scheduleInfo: {
      expiration: {
        type: 'AfterDuration'
        duration: eligibilityDuration
      }
    }
  }
}

@sys.description('Resource ID of the quarantine policy initiative.')
output policySetDefinitionId string = quarantineInitiative.id

@sys.description('Resource ID of the quarantine policy assignment.')
output policyAssignmentId string = quarantinePolicyAssignment.id
