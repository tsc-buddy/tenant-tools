using './governance.bicep'

param groups = {
  readers: [
    '11111111-1111-1111-1111-111111111111'
  ]
  recoveryAdministrators: '22222222-2222-2222-2222-222222222222'
}

param protectedResourceTypes = [
  'Microsoft.Compute/virtualMachines'
  'Microsoft.Compute/disks'
  'Microsoft.Network/virtualNetworks'
  'Microsoft.Network/networkInterfaces'
  'Microsoft.Network/publicIPAddresses'
  'Microsoft.RecoveryServices/vaults'
  'Microsoft.Storage/storageAccounts'
]

param enforcementMode = 'DoNotEnforce'
param eligibilityDuration = 'P365D'
