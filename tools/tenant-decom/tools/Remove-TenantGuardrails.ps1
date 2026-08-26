[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ManagementGroupId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [guid[]]$SubscriptionId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GovernanceStackName = 'tenant-wide-decommission-guardrails',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LockStackName = 'tenant-decommission-quarantine-lock',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LockName = 'decommission-quarantine'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Quarantine.Common.psm1') -Force
Assert-QuarantineAzModule

$subscriptionIds = @($SubscriptionId | Select-Object -Unique)

Write-Host ''
Write-Host 'Tenant-wide guardrails removal'
Write-Host '--------------------------------'
Write-Host "Management group stack: $GovernanceStackName"
Write-Host "Management group      : $ManagementGroupId"
Write-Host "Subscription locks    : $($subscriptionIds.Count)"
foreach ($id in $subscriptionIds) {
    Write-Host "  - $id"
}
Write-Host "Lock name             : $LockName"
Write-Host ''
Write-Host 'Removal order:'
Write-Host '  1. Delete each named subscription ReadOnly lock.'
Write-Host '  2. Delete each subscription deployment stack.'
Write-Host '  3. Delete the management-group stack, Policy assignment, and initiative.'
Write-Host ''

if ($WhatIfPreference) {
    Write-Warning 'This is a local intent preview. No Azure resources will be queried or changed.'
    Write-Warning 'Removal uses ActionOnUnmanage DeleteAll and deletes resources owned by these stacks.'
}
else {
    Connect-QuarantineAzure -Verbose:($VerbosePreference -eq 'Continue')
}

$results = foreach ($id in $subscriptionIds) {
    $target = "/subscriptions/$id"
    if ($WhatIfPreference) {
        $PSCmdlet.ShouldProcess($target, "Delete ReadOnly lock '$LockName'") | Out-Null
        $PSCmdlet.ShouldProcess($target, "Delete deployment stack '$LockStackName'") | Out-Null
    }
    else {
        Set-AzContext -SubscriptionId $id -ErrorAction Stop | Out-Null

        $locks = @(Get-QuarantineLock -SubscriptionId $id -LockName $LockName)
        if ($locks.Count -gt 1) {
            throw "Expected at most one at-scope lock named '$LockName' on subscription '$id'; found $($locks.Count). No resources were removed from this subscription."
        }

        if ($locks.Count -eq 1 -and $PSCmdlet.ShouldProcess($target, "Delete ReadOnly lock '$LockName'")) {
            Remove-AzResourceLock `
                -LockId $locks[0].LockId `
                -Force `
                -ErrorAction Stop
        }
        elseif ($locks.Count -eq 0) {
            Write-Warning "Lock '$LockName' is already absent from subscription '$id'; continuing with stack removal."
        }

        if ($PSCmdlet.ShouldProcess($target, "Delete deployment stack '$LockStackName'")) {
            foreach ($attempt in 1..5) {
                try {
                    $stackRemovalJob = Start-QuarantineAzRemovalJob `
                        -CommandName Remove-AzSubscriptionDeploymentStack `
                        -Parameters @{
                            Name             = $LockStackName
                            ActionOnUnmanage = 'DeleteAll'
                            Force            = $true
                            DefaultProfile   = Get-AzContext
                        }
                    Wait-QuarantineAzJob `
                        -Job $stackRemovalJob `
                        -Activity "Removing subscription stack from $id" | Out-Null
                    break
                }
                catch {
                    if ($attempt -eq 5 -or $_.Exception.Message -notmatch 'ScopeLocked') {
                        throw
                    }

                    Write-Warning "Subscription lock deletion is still propagating; retrying stack removal (attempt $($attempt + 1) of 5)."
                }
            }
        }
    }

    [pscustomobject]@{
        Scope       = $target
        StackName   = $LockStackName
        Resource    = 'ReadOnly lock'
        PlannedOnly = [bool]$WhatIfPreference
    }
}

$managementGroupScope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupId"
if ($PSCmdlet.ShouldProcess($managementGroupScope, "Delete deployment stack '$GovernanceStackName' and its managed Policy resources")) {
    $governanceRemovalJob = Start-QuarantineAzRemovalJob `
        -CommandName Remove-AzManagementGroupDeploymentStack `
        -Parameters @{
            ManagementGroupId = $ManagementGroupId
            Name              = $GovernanceStackName
            ActionOnUnmanage  = 'DeleteAll'
            Force             = $true
            DefaultProfile    = Get-AzContext
        }
    Wait-QuarantineAzJob `
        -Job $governanceRemovalJob `
        -Activity "Removing management-group stack from $ManagementGroupId" | Out-Null
}

if ($WhatIfPreference) {
    $results
    [pscustomobject]@{
        Scope       = $managementGroupScope
        StackName   = $GovernanceStackName
        Resource    = 'Policy initiative and assignment'
        PlannedOnly = $true
    }
    return
}

function Test-AzureObjectAbsent {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Query
    )

    try {
        $result = & $Query
        return $null -eq $result
    }
    catch {
        if ($_.Exception.Message -match 'could not be found|not found|404') {
            return $true
        }

        throw
    }
}

$policyAssignmentId = "$managementGroupScope/providers/Microsoft.Authorization/policyAssignments/decom-guardrails"
$managementGroupStackAbsent = Test-AzureObjectAbsent {
    Get-AzManagementGroupDeploymentStack `
        -ManagementGroupId $ManagementGroupId `
        -Name $GovernanceStackName `
        -ErrorAction Stop
}
$policyAssignmentAbsent = Test-AzureObjectAbsent {
    Get-AzPolicyAssignment -Id $policyAssignmentId -ErrorAction Stop
}
$policyInitiativeAbsent = Test-AzureObjectAbsent {
    Get-AzPolicySetDefinition `
        -ManagementGroupName $ManagementGroupId `
        -Name 'tenant-decommission-guardrails' `
        -ErrorAction Stop
}

Write-Host ''
Write-Host 'Cleanup verification'
Write-Host '--------------------'
foreach ($id in $subscriptionIds) {
    Set-AzContext -SubscriptionId $id -ErrorAction Stop | Out-Null
    $subscriptionScope = "/subscriptions/$id"
    $lockAbsent = @(Get-AzResourceLock -Scope $subscriptionScope -AtScope -ErrorAction SilentlyContinue |
            Where-Object Name -eq $LockName).Count -eq 0
    $subscriptionStackAbsent = Test-AzureObjectAbsent {
        Get-AzSubscriptionDeploymentStack -Name $LockStackName -ErrorAction Stop
    }

    [pscustomobject]@{
        SubscriptionId            = [string]$id
        LockAbsent                 = $lockAbsent
        SubscriptionStackAbsent    = $subscriptionStackAbsent
        ManagementGroupStackAbsent = $managementGroupStackAbsent
        PolicyAssignmentAbsent     = $policyAssignmentAbsent
        PolicyInitiativeAbsent     = $policyInitiativeAbsent
    }
}