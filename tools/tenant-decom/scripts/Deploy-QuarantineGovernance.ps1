[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ManagementGroupId,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ParameterFile,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$StackName = 'tenant-decommission-governance',

    [Parameter()]
    [string]$DeploymentLocation = 'australiaeast'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Quarantine.Common.psm1') -Force
Assert-QuarantineAzModule

$templateFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'infra/subscription-quarantine/governance.bicep'
$resolvedParameterFile = (Resolve-Path -LiteralPath $ParameterFile).Path

if ($WhatIfPreference) {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'Azure CLI with Bicep is required to generate the governance deployment preview.'
    }

    $originalWhatIfPreference = $WhatIfPreference
    $WhatIfPreference = $false
    $errorFilePath = [System.IO.Path]::GetTempFileName()
    try {
        $buildOutput = az bicep build-params `
            --file $resolvedParameterFile `
            --stdout `
            --no-restore 2> $errorFilePath

        if ($LASTEXITCODE -ne 0) {
            $buildError = Get-Content -LiteralPath $errorFilePath -Raw
            throw "Unable to compile parameter file '$resolvedParameterFile'. $buildError"
        }

        $buildResult = $buildOutput | ConvertFrom-Json -ErrorAction Stop
        $compiledParameters = $buildResult.parametersJson | ConvertFrom-Json -ErrorAction Stop
        $parameterValues = $compiledParameters.parameters
        $readerIds = @($parameterValues.groups.value.readers)
        $recoveryAdministratorId = [string]$parameterValues.groups.value.recoveryAdministrators
        $protectedResourceTypes = @($parameterValues.protectedResourceTypes.value)
        $enforcementMode = [string]$parameterValues.enforcementMode.value
        $eligibilityDuration = [string]$parameterValues.eligibilityDuration.value
    }
    finally {
        Remove-Item -LiteralPath $errorFilePath -Force -ErrorAction SilentlyContinue
        $WhatIfPreference = $originalWhatIfPreference
    }

    Write-Host ''
    Write-Host 'Governance deployment preview'
    Write-Host '-----------------------------'
    Write-Host "Target management group : $ManagementGroupId"
    Write-Host "Deployment stack        : $StackName"
    Write-Host "Deployment location     : $DeploymentLocation"
    Write-Host "Parameter file          : $resolvedParameterFile"
    Write-Host "Policy enforcement      : $enforcementMode"
    Write-Host "PIM eligibility duration: $eligibilityDuration"
    Write-Host "Reader groups           : $($readerIds.Count)"
    foreach ($readerId in $readerIds) {
        Write-Host "  - $readerId"
    }
    Write-Host "Recovery administrators : $recoveryAdministratorId"
    Write-Host "Protected resource types: $($protectedResourceTypes.Count)"
    foreach ($resourceType in $protectedResourceTypes) {
        Write-Host "  - $resourceType"
    }

    Write-Host ''
    Write-Host 'Resources the stack will manage:'
    Write-Host '  - Custom Policy initiative: Subscription Quarantine Guardrails'
    Write-Host "  - Policy assignment with enforcement mode '$enforcementMode'"
    Write-Host "  - $($readerIds.Count) permanent Reader role assignment(s)"
    Write-Host "  - PIM eligibility for User Access Administrator ($eligibilityDuration)"
    Write-Host "  - PIM eligibility for Contributor ($eligibilityDuration)"
    Write-Host ''
    Write-Warning 'This is a local intent preview, not an Azure resource-level diff.'
    Write-Warning 'The stack uses ActionOnUnmanage DeleteAll. A later template update or stack removal can delete resources managed by this stack.'
    Write-Host ''
}

if (-not $WhatIfPreference) {
    Connect-QuarantineAzure -Verbose:($VerbosePreference -eq 'Continue')
}

if ($PSCmdlet.ShouldProcess(
        "/providers/Microsoft.Management/managementGroups/$ManagementGroupId",
        "Create or update deployment stack '$StackName'"
    )) {
    New-AzManagementGroupDeploymentStack `
        -Name $StackName `
        -ManagementGroupId $ManagementGroupId `
        -Location $DeploymentLocation `
        -ActionOnUnmanage DeleteAll `
        -DenySettingsMode None `
        -TemplateFile $templateFile `
        -TemplateParameterFile $resolvedParameterFile `
        -Description 'Tenant decommission quarantine Policy, RBAC, and PIM eligibility.' `
        -Force `
        -ErrorAction Stop
}