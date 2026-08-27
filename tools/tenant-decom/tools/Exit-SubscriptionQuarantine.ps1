[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [guid]$SubscriptionId,

    [Parameter(Mandatory)]
    [ValidateSet('Rollback', 'Destruction')]
    [string]$Mode,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ChangeReference,

    [Parameter()]
    [string]$LockName = 'decommission-quarantine',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LockStackName = 'tenant-decommission-quarantine-lock'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Quarantine.Common.psm1') -Force
Assert-QuarantineAzModule
Connect-QuarantineAzure -Verbose:($VerbosePreference -eq 'Continue')
Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null

$lock = @(Get-QuarantineLock -SubscriptionId $SubscriptionId -LockName $LockName)
if ($lock.Count -ne 1) {
    throw "Expected one lock named '$LockName'; found $($lock.Count)."
}

$target = "subscription $SubscriptionId for $Mode under change $ChangeReference"
if ($PSCmdlet.ShouldProcess($target, "Delete deployment stack '$LockStackName' and its ReadOnly lock")) {
    Remove-AzSubscriptionDeploymentStack `
        -Name $LockStackName `
        -ActionOnUnmanage DeleteAll `
        -Force `
        -ErrorAction Stop
}

[pscustomobject]@{
    SubscriptionId  = [string]$SubscriptionId
    Mode            = $Mode
    ChangeReference = $ChangeReference
    LockRemoved     = -not $WhatIfPreference
    LockStackName   = $LockStackName
    NextAction      = 'Create a time-bound quarantine policy exemption before performing recovery or destruction writes.'
}