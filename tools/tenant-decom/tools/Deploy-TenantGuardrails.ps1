[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ManagementGroupId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [guid[]]$SubscriptionId,

    [Parameter()]
    [ValidateSet('Default', 'DoNotEnforce')]
    [string]$EnforcementMode = 'DoNotEnforce',

    [Parameter()]
    [switch]$EnableRecoveryAccess,

    [Parameter()]
    [string]$RecoveryAdministratorsGroupId = '',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$EligibilityDuration = 'P365D',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LockName = 'decommission-quarantine',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LockNotes = 'Applied by the tenant-wide decommission guardrails deployment.',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DeploymentLocation = 'australiaeast'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path $PSScriptRoot -Parent
$commonModule = Join-Path $PSScriptRoot 'Quarantine.Common.psm1'
$guardrailsTemplate = Join-Path $projectRoot 'infra/tenant-wide/tenant-guardrails.bicep'
$lockTemplate = Join-Path $projectRoot 'infra/tenant-wide/subscription-lock.bicep'
$governanceStackName = 'tenant-wide-decommission-guardrails'
$lockStackName = 'tenant-decommission-quarantine-lock'
$subscriptionIds = @($SubscriptionId | Select-Object -Unique)
$createContributorEligibility = [bool]$EnableRecoveryAccess
$createUserAccessAdministratorEligibility = [bool]$EnableRecoveryAccess
$contributorEligibilityRequestId = [guid]::NewGuid().Guid
$userAccessAdministratorEligibilityRequestId = [guid]::NewGuid().Guid

if ($EnableRecoveryAccess -and [string]::IsNullOrWhiteSpace($RecoveryAdministratorsGroupId)) {
    throw '-RecoveryAdministratorsGroupId is required when -EnableRecoveryAccess is specified.'
}

if (-not $EnableRecoveryAccess -and -not [string]::IsNullOrWhiteSpace($RecoveryAdministratorsGroupId)) {
    throw '-RecoveryAdministratorsGroupId was supplied without -EnableRecoveryAccess.'
}

Import-Module $commonModule -Force
Assert-QuarantineAzModule

Write-Host ''
Write-Host 'Tenant-wide guardrails deployment'
Write-Host '---------------------------------'
Write-Host "Management group : $ManagementGroupId"
Write-Host "Policy enforcement: $EnforcementMode"
Write-Host "Subscription locks: $($subscriptionIds.Count)"
foreach ($id in $subscriptionIds) {
    Write-Host "  - $id"
}
Write-Host "Lock name        : $LockName"
if ($EnableRecoveryAccess) {
    Write-Host 'Recovery access  : Enabled'
    Write-Host "Recovery group   : $RecoveryAdministratorsGroupId"
    Write-Host "Eligibility      : $EligibilityDuration"
}
else {
    Write-Host 'Recovery access  : Disabled'
}
Write-Host ''
Write-Host 'Planned controls:'
Write-Host '  - Create or update the initiative and assignment at the management group.'
Write-Host '  - Apply a ReadOnly lock to each listed subscription.'
if ($EnableRecoveryAccess) {
    Write-Host '  - Create PIM eligibility for Contributor and User Access Administrator.'
}
else {
    Write-Host '  - Do not configure PIM recovery access.'
}
Write-Host '  - Do not move subscriptions or change existing RBAC assignments.'
Write-Host ''

if ($WhatIfPreference) {
    Write-Warning 'This is a local intent preview, not an Azure resource-level diff.'
    Write-Warning 'The deployment stacks use ActionOnUnmanage DeleteAll.'
}
else {
    Connect-QuarantineAzure -Verbose:($VerbosePreference -eq 'Continue')

    $managementGroup = Get-AzManagementGroup -GroupId $ManagementGroupId -ErrorAction Stop
    $currentTenantId = [string](Get-AzContext).Tenant.Id
    if ($EnableRecoveryAccess) {
        Get-AzADGroup -ObjectId $RecoveryAdministratorsGroupId -ErrorAction Stop | Out-Null

        $managementGroupScope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupId"
        $currentEligibility = @()
        foreach ($resourceType in @('roleEligibilitySchedules', 'roleEligibilityScheduleInstances')) {
            $eligibilityPath = "$managementGroupScope/providers/Microsoft.Authorization/$resourceType`?api-version=2020-10-01-preview"
            while (-not [string]::IsNullOrWhiteSpace($eligibilityPath)) {
                $eligibilityResponse = if ($eligibilityPath.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)) {
                    Invoke-AzRestMethod -Method GET -Uri $eligibilityPath -ErrorAction Stop
                }
                else {
                    Invoke-AzRestMethod -Method GET -Path $eligibilityPath -ErrorAction Stop
                }
                $eligibilityBody = $eligibilityResponse.Content | ConvertFrom-Json
                $currentEligibility += @($eligibilityBody.value | Where-Object {
                        $_.properties.principalId -eq $RecoveryAdministratorsGroupId
                    })
                $nextLinkProperty = $eligibilityBody.PSObject.Properties['nextLink']
                $eligibilityPath = if ($null -eq $nextLinkProperty) { '' } else { [string]$nextLinkProperty.Value }
            }
        }

        $createContributorEligibility = -not [bool]($currentEligibility | Where-Object {
                $_.properties.roleDefinitionId -match '/b24988ac-6180-42a0-ab88-20f7382dd24c$'
            })
        $createUserAccessAdministratorEligibility = -not [bool]($currentEligibility | Where-Object {
                $_.properties.roleDefinitionId -match '/18d7d88d-d35e-4fb5-a5c3-7773c20a72d9$'
            })

        Write-Host ''
        Write-Host 'Recovery access discovery:'
        Write-Host "  - Contributor             : $(if ($createContributorEligibility) { 'Missing; will create' } else { 'Current eligibility exists' })"
        Write-Host "  - User Access Administrator: $(if ($createUserAccessAdministratorEligibility) { 'Missing; will create' } else { 'Current eligibility exists' })"
    }
    foreach ($id in $subscriptionIds) {
        $subscription = Get-AzSubscription -SubscriptionId $id -ErrorAction Stop
        if ([string]$subscription.TenantId -ne $currentTenantId) {
            throw "Subscription '$id' is not in the current tenant '$currentTenantId'."
        }
    }

    Write-Verbose "Validated management group '$($managementGroup.Name)' and $($subscriptionIds.Count) subscription(s)."
}

$managementGroupScope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupId"
if ($PSCmdlet.ShouldProcess($managementGroupScope, "Create or update deployment stack '$governanceStackName'")) {
    $compiledGuardrailsTemplate = Export-QuarantineArmTemplate -TemplateFile $guardrailsTemplate
    try {
        $governanceJob = New-AzManagementGroupDeploymentStack `
            -Name $governanceStackName `
            -ManagementGroupId $ManagementGroupId `
            -Location $DeploymentLocation `
            -ActionOnUnmanage DeleteAll `
            -DenySettingsMode None `
            -TemplateFile $compiledGuardrailsTemplate `
            -TemplateParameterObject @{
                enforcementMode               = $EnforcementMode
                enableRecoveryAccess           = [bool]$EnableRecoveryAccess
                recoveryAdministratorsGroupId = $RecoveryAdministratorsGroupId
                createContributorEligibility   = $createContributorEligibility
                createUserAccessAdministratorEligibility = $createUserAccessAdministratorEligibility
                contributorEligibilityRequestId = $contributorEligibilityRequestId
                userAccessAdministratorEligibilityRequestId = $userAccessAdministratorEligibilityRequestId
                eligibilityDuration            = $EligibilityDuration
            } `
            -Description 'Tenant-wide decommission Policy, optional recovery access, and subscription guardrails.' `
            -Force `
            -AsJob `
            -ErrorAction Stop

        Wait-QuarantineAzJob `
            -Job $governanceJob `
            -Activity "Deploying management-group guardrails to $ManagementGroupId" | Out-Null
    }
    finally {
        Remove-Item -LiteralPath $compiledGuardrailsTemplate -Force -ErrorAction SilentlyContinue
    }
}

$results = foreach ($id in $subscriptionIds) {
    New-QuarantineLockDeployment `
        -SubscriptionId $id `
        -Notes $LockNotes `
        -TemplateFile $lockTemplate `
        -LockName $LockName `
        -StackName $lockStackName `
        -DeploymentLocation $DeploymentLocation `
        -WhatIf:$WhatIfPreference `
        -Confirm:$false `
        -Verbose:($VerbosePreference -eq 'Continue')

    [pscustomobject]@{
        SubscriptionId = [string]$id
        LockName        = $LockName
        LockStackName   = $lockStackName
        PlannedOnly     = [bool]$WhatIfPreference
    }
}

$results
