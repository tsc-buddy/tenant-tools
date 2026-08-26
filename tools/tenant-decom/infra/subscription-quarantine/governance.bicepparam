using './governance.bicep'

param groups = {
  readers: [
    '7bcf407b-f8e6-49c7-9118-8dc2d18c2760'
  ]
  recoveryAdministrators: '3a99c3a1-b0c1-4aab-b6c7-38e08086470c'
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
