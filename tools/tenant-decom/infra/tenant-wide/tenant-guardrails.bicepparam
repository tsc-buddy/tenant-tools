using './tenant-guardrails.bicep'

param enforcementMode = 'Default'
param enableRecoveryAccess = false
param recoveryAdministratorsGroupId = ''
param createContributorEligibility = false
param createUserAccessAdministratorEligibility = false
param contributorEligibilityRequestId = '00000000-0000-0000-0000-000000000001'
param userAccessAdministratorEligibilityRequestId = '00000000-0000-0000-0000-000000000002'
param eligibilityDuration = 'P365D'

param protectedResourceTypes = [
  'Microsoft.Compute/virtualMachines'
  'Microsoft.Compute/disks'
  'Microsoft.Network/virtualNetworks'
  'Microsoft.Network/networkInterfaces'
  'Microsoft.Network/publicIPAddresses'
  'Microsoft.RecoveryServices/vaults'
  'Microsoft.Storage/storageAccounts'
]
