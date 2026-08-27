[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [guid]$SubscriptionId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ManagementGroupId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ChangeReference,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OwningTeam,

    [Parameter()]
    [ValidateRange(1, 365)]
    [int]$RetentionDays = 30,

    [Parameter()]
    [string[]]$ApprovedWritePrincipalId = @(),

    [Parameter()]
    [switch]$RemoveUnapprovedDirectWriteAssignments,

    [Parameter()]
    [string]$EvidenceDirectory = (Join-Path $PWD 'quarantine-evidence'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LockStackName = 'tenant-decommission-quarantine-lock',

    [Parameter()]
    [string]$DeploymentLocation = 'australiaeast'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Quarantine.Common.psm1') -Force
Assert-QuarantineAzModule
Connect-QuarantineAzure -Verbose:($VerbosePreference -eq 'Continue')

$timestamp = Get-Date -Format 'yyyyMMddHHmmss'
$evidencePath = Join-Path $EvidenceDirectory "$SubscriptionId-$timestamp.json"
$readinessScript = Join-Path $PSScriptRoot 'Get-QuarantineReadiness.ps1'
$readiness = & $readinessScript -SubscriptionId $SubscriptionId -OutputPath $evidencePath -Verbose:($VerbosePreference -eq 'Continue')
$writeAssignments = @(Get-DirectControlPlaneWriteAssignment -SubscriptionId $SubscriptionId)
$unapprovedAssignments = @($writeAssignments | Where-Object {
        $_.ObjectId -notin $ApprovedWritePrincipalId
    })

if ($unapprovedAssignments.Count -gt 0 -and -not $RemoveUnapprovedDirectWriteAssignments) {
    throw "$($unapprovedAssignments.Count) unapproved direct write assignment(s) remain. Review '$evidencePath', then rerun with -RemoveUnapprovedDirectWriteAssignments and an approved principal allowlist."
}

$scope = Get-SubscriptionScope -SubscriptionId $SubscriptionId
if ($PSCmdlet.ShouldProcess($scope, "Move subscription to management group '$ManagementGroupId'")) {
    New-AzManagementGroupSubscription `
        -GroupId $ManagementGroupId `
        -SubscriptionId $SubscriptionId `
        -ErrorAction Stop | Out-Null
}

foreach ($assignment in $unapprovedAssignments) {
    $target = "$($assignment.DisplayName) [$($assignment.RoleDefinitionName)] at $($assignment.Scope)"
    if ($PSCmdlet.ShouldProcess($target, 'Remove direct write-capable role assignment')) {
        Remove-AzRoleAssignment `
            -ObjectId $assignment.ObjectId `
            -RoleDefinitionId $assignment.RoleDefinitionId `
            -Scope $assignment.Scope `
            -ErrorAction Stop
    }
}

$quarantineDate = (Get-Date).ToUniversalTime()
$destroyAfter = $quarantineDate.AddDays($RetentionDays)
$notes = "Change $ChangeReference; quarantine $($quarantineDate.ToString('yyyy-MM-dd')); destroy after $($destroyAfter.ToString('yyyy-MM-dd')); owner $OwningTeam"
$templateFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'infra/subscription-quarantine/subscription-lock.bicep'
New-QuarantineLockDeployment `
    -SubscriptionId $SubscriptionId `
    -Notes $notes `
    -TemplateFile $templateFile `
    -StackName $LockStackName `
    -DeploymentLocation $DeploymentLocation `
    -WhatIf:$WhatIfPreference `
    -Confirm:$false `
    -Verbose:($VerbosePreference -eq 'Continue')

[pscustomobject]@{
    SubscriptionId              = [string]$SubscriptionId
    TargetManagementGroupId     = $ManagementGroupId
    EvidencePath                = $readiness.EvidencePath
    RemovedAssignmentCount      = if ($WhatIfPreference) { 0 } else { $unapprovedAssignments.Count }
    PlannedDestroyAfterUtc      = $destroyAfter.ToString('o')
    LockName                    = 'decommission-quarantine'
    LockStackName               = $LockStackName
}