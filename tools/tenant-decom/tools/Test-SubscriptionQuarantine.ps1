[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [guid]$SubscriptionId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedManagementGroupId,

    [Parameter()]
    [string[]]$ApprovedWritePrincipalId = @(),

    [Parameter()]
    [string]$LockName = 'decommission-quarantine'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Quarantine.Common.psm1') -Force
Assert-QuarantineAzModule
Connect-QuarantineAzure -Verbose:($VerbosePreference -eq 'Continue')
Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null

$parentManagementGroupId = Get-SubscriptionParentManagementGroupId -SubscriptionId $SubscriptionId
$locks = @(Get-QuarantineLock -SubscriptionId $SubscriptionId -LockName $LockName)
$writeAssignments = @(Get-DirectControlPlaneWriteAssignment -SubscriptionId $SubscriptionId)
$unapprovedAssignments = @($writeAssignments | Where-Object {
        $_.ObjectId -notin $ApprovedWritePrincipalId
    })
$scope = Get-SubscriptionScope -SubscriptionId $SubscriptionId
$policyAssignment = Get-AzPolicyAssignment -Scope $scope -ErrorAction Stop |
    Where-Object DisplayName -eq 'Enforce subscription quarantine guardrails' |
    Select-Object -First 1

$checks = @(
    [pscustomobject]@{
        Check   = 'ParentManagementGroup'
        Passed  = $parentManagementGroupId -eq "/providers/Microsoft.Management/managementGroups/$ExpectedManagementGroupId"
        Detail  = $parentManagementGroupId
    }
    [pscustomobject]@{
        Check   = 'ReadOnlyLock'
        Passed  = $locks.Count -eq 1 -and [string]$locks[0].Properties.Level -eq 'ReadOnly'
        Detail  = if ($locks.Count -eq 0) { 'Missing' } else { [string]$locks[0].Properties.Level }
    }
    [pscustomobject]@{
        Check   = 'InheritedQuarantinePolicy'
        Passed  = $null -ne $policyAssignment
        Detail  = if ($null -eq $policyAssignment) { 'Missing' } else { [string]$policyAssignment.PolicyAssignmentId }
    }
    [pscustomobject]@{
        Check   = 'UnapprovedDirectWriteAssignments'
        Passed  = $unapprovedAssignments.Count -eq 0
        Detail  = "$($unapprovedAssignments.Count) found"
    }
)

$checks | Format-Table -AutoSize | Out-Host
if ($checks.Passed -contains $false) {
    throw 'One or more quarantine checks failed.'
}

$checks