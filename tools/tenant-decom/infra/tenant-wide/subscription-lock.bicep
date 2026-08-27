targetScope = 'subscription'

@sys.description('Name of the subscription-level ReadOnly lock.')
@minLength(1)
param lockName string = 'decommission-quarantine'

@sys.description('Operational context stored on the lock.')
@minLength(1)
param lockNotes string

resource subscriptionLock 'Microsoft.Authorization/locks@2016-09-01' = {
  name: lockName
  properties: {
    level: 'ReadOnly'
    notes: lockNotes
  }
}

@sys.description('Resource ID of the subscription-level lock.')
output lockId string = subscriptionLock.id
