[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path $PSScriptRoot -Parent
$scriptFiles = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tools') -Include '*.ps1', '*.psm1' -Recurse)

foreach ($file in $scriptFiles) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null

    if ($errors.Count -gt 0) {
        throw "PowerShell parse failure in '$($file.Name)': $($errors.Message -join '; ')"
    }
}

$scriptContent = ($scriptFiles | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw
    }) -join "`n"
$forbiddenDeploymentCommands = @(
    'New-AzManagementGroupDeployment'
    'New-AzSubscriptionDeployment'
    'New-AzResourceGroupDeployment'
    'New-AzTenantDeployment'
)

foreach ($command in $forbiddenDeploymentCommands) {
    if ($scriptContent -match "(?m)\b$command\s") {
        throw "Conventional deployment command '$command' found. Bicep must be deployed through deployment stacks."
    }
}

$requiredStackCommands = @(
    'New-AzManagementGroupDeploymentStack'
    'Remove-AzManagementGroupDeploymentStack'
    'New-AzSubscriptionDeploymentStack'
    'Remove-AzSubscriptionDeploymentStack'
)

foreach ($command in $requiredStackCommands) {
    if ($scriptContent -notmatch "(?m)\b$command\b") {
        throw "Required deployment stack command '$command' was not found."
    }
}

$governanceDeploymentScript = Get-Content -LiteralPath (
    Join-Path $projectRoot 'tools/Deploy-QuarantineGovernance.ps1'
) -Raw
$requiredPreviewText = @(
    'Governance deployment preview'
    'Resources the stack will manage:'
    'local intent preview, not an Azure resource-level diff'
    'ActionOnUnmanage DeleteAll'
)

foreach ($previewText in $requiredPreviewText) {
    if ($governanceDeploymentScript -notmatch [regex]::Escape($previewText)) {
        throw "Governance deployment preview is missing required text '$previewText'."
    }
}

$commonModuleContent = Get-Content -LiteralPath (
    Join-Path $projectRoot 'tools/Quarantine.Common.psm1'
) -Raw
if ($commonModuleContent -match '(?m)^\s*Connect-AzAccount\b') {
    throw 'Guardrail scripts must not initiate interactive Azure authentication.'
}

foreach ($requiredRbacSafetyText in @('ConservativeFallback', 'attempt $attempt of 3', 'Do not approve RBAC removal')) {
    if ($commonModuleContent -notmatch [regex]::Escape($requiredRbacSafetyText)) {
        throw "RBAC discovery is missing required resilience text '$requiredRbacSafetyText'."
    }
}

$readinessScript = Get-Content -LiteralPath (
    Join-Path $projectRoot 'tools/Get-QuarantineReadiness.ps1'
) -Raw
$forbiddenFullEvidenceAssignments = @(
    'Resources                     = $resources'
    'RoleAssignments               = $roleAssignments'
    'PolicyAssignments             = $policyAssignments'
    'PolicyExemptions              = $policyExemptions'
)

foreach ($assignment in $forbiddenFullEvidenceAssignments) {
    if ($readinessScript.Contains($assignment)) {
        throw "Readiness evidence must not serialize full Azure objects: '$assignment'."
    }
}

foreach ($requiredSummary in @('ResourceTypeSummary', 'RoleAssignmentCount', 'PolicyExemptionCount')) {
    if ($readinessScript -notmatch "\b$requiredSummary\b") {
        throw "Readiness evidence is missing compact summary '$requiredSummary'."
    }
}

$tenantWideTemplate = Get-Content -LiteralPath (
    Join-Path $projectRoot 'infra/tenant-wide/tenant-guardrails.bicep'
) -Raw
$tenantWideAssignment = [regex]::Match(
    $tenantWideTemplate,
    "(?s)resource\s+tenantGuardrailsAssignment\s+'Microsoft\.Authorization/policyAssignments@[^']+'\s*=\s*\{.*?name:\s*'([^']+)'"
)
if (-not $tenantWideAssignment.Success) {
    throw 'Unable to identify the tenant-wide Policy assignment name.'
}

$tenantWideAssignmentName = $tenantWideAssignment.Groups[1].Value
if ($tenantWideAssignmentName.Length -gt 24) {
    throw "Tenant-wide Policy assignment name '$tenantWideAssignmentName' exceeds the 24-character Azure limit."
}

foreach ($requiredRecoveryAccessText in @(
        'param enableRecoveryAccess bool = false'
    'param contributorEligibilityRequestId string'
    'param userAccessAdministratorEligibilityRequestId string'
        "roleEligibilityScheduleRequests@2020-10-01-preview"
        'builtInRoleDefinitionIds.contributor'
        'builtInRoleDefinitionIds.userAccessAdministrator'
    )) {
    if ($tenantWideTemplate -notmatch [regex]::Escape($requiredRecoveryAccessText)) {
        throw "Tenant-wide infrastructure is missing optional recovery access behavior '$requiredRecoveryAccessText'."
    }
}

$tenantWideDeploymentScript = Get-Content -LiteralPath (
    Join-Path $projectRoot 'tools/Deploy-TenantGuardrails.ps1'
) -Raw
foreach ($requiredRecoveryAccessSafetyText in @(
        '-RecoveryAdministratorsGroupId is required when -EnableRecoveryAccess is specified.'
        'Recovery access  : Disabled'
    'roleEligibilitySchedules'
    'roleEligibilityScheduleInstances'
    'Missing; will create'
    '-AsJob'
    'Wait-QuarantineAzJob'
    )) {
    if ($tenantWideDeploymentScript -notmatch [regex]::Escape($requiredRecoveryAccessSafetyText)) {
        throw "Tenant-wide deployment is missing recovery access safety behavior '$requiredRecoveryAccessSafetyText'."
    }
}

if ($tenantWideDeploymentScript -match 'roleEligibilityScheduleRequests') {
    throw 'Tenant-wide PIM discovery must use current schedules or instances, not request-history records.'
}

foreach ($requiredProgressText in @(
        'function Wait-QuarantineAzJob'
        'Elapsed $elapsed'
        'completed in $elapsed'
        'Write-Progress'
    )) {
    if ($commonModuleContent -notmatch [regex]::Escape($requiredProgressText)) {
        throw "Shared deployment progress is missing required behavior '$requiredProgressText'."
    }
}

$tenantWideRemovalScript = Get-Content -LiteralPath (
    Join-Path $projectRoot 'tools/Remove-TenantGuardrails.ps1'
) -Raw
foreach ($requiredRemovalSafetyText in @('Remove-AzResourceLock', 'ScopeLocked', 'already absent')) {
    if ($tenantWideRemovalScript -notmatch [regex]::Escape($requiredRemovalSafetyText)) {
        throw "Tenant-wide removal is missing required lock-first safety behavior '$requiredRemovalSafetyText'."
    }
}

foreach ($requiredRemovalProgressText in @(
        'Start-QuarantineAzRemovalJob'
        'Removing subscription stack from $id'
        'Removing management-group stack from $ManagementGroupId'
    )) {
    if ($tenantWideRemovalScript -notmatch [regex]::Escape($requiredRemovalProgressText)) {
        throw "Tenant-wide removal is missing progress behavior '$requiredRemovalProgressText'."
    }
}

foreach ($requiredVerificationField in @(
        'LockAbsent'
        'SubscriptionStackAbsent'
        'ManagementGroupStackAbsent'
        'PolicyAssignmentAbsent'
        'PolicyInitiativeAbsent'
    )) {
    if ($tenantWideRemovalScript -notmatch "\b$requiredVerificationField\b") {
        throw "Tenant-wide removal is missing verification field '$requiredVerificationField'."
    }
}

Import-Module (Join-Path $projectRoot 'tools/Quarantine.Common.psm1') -Force
$subscriptionId = [guid]'00000000-0000-0000-0000-000000000001'
$actualScope = Get-SubscriptionScope -SubscriptionId $subscriptionId
$expectedScope = '/subscriptions/00000000-0000-0000-0000-000000000001'

if ($actualScope -ne $expectedScope) {
    throw "Expected scope '$expectedScope'; got '$actualScope'."
}

Write-Output "Passed smoke tests for $($scriptFiles.Count) PowerShell files."