targetScope = 'subscription'

@sys.description('Name of the subscription-level quarantine lock.')
@minLength(1)
param lockName string = 'decommission-quarantine'

@sys.description('Operational context stored on the lock, including ticket and planned destruction date.')
@minLength(1)
param lockNotes string

resource quarantineLock 'Microsoft.Authorization/locks@2016-09-01' = {
  name: lockName
  properties: {
    level: 'ReadOnly'
    notes: lockNotes
  }
}

@sys.description('Resource ID of the subscription-level quarantine lock.')
output lockId string = quarantineLock.id