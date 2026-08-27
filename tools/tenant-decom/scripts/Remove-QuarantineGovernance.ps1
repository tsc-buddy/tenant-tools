[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ManagementGroupId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$StackName = 'tenant-decommission-governance'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Quarantine.Common.psm1') -Force
Assert-QuarantineAzModule
Connect-QuarantineAzure -Verbose:($VerbosePreference -eq 'Continue')

$scope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupId"
if ($PSCmdlet.ShouldProcess($scope, "Delete deployment stack '$StackName' and all managed resources")) {
    Remove-AzManagementGroupDeploymentStack `
        -ManagementGroupId $ManagementGroupId `
        -Name $StackName `
        -ActionOnUnmanage DeleteAll `
        -Force `
        -ErrorAction Stop

    Write-Warning 'Verify both resulting PIM role eligibility schedules are revoked. Deleting an AdminAssign request is not a substitute for an AdminRemove request if eligibility remains active.'
}