Set-StrictMode -Version Latest

function Assert-QuarantineAzModule {
    [CmdletBinding()]
    param()

    $requiredModules = @('Az.Accounts', 'Az.Resources')
    $missingModules = @($requiredModules | Where-Object {
            -not (Get-Module -ListAvailable -Name $_)
        })

    if ($missingModules.Count -gt 0) {
        throw "Missing required module(s): $($missingModules -join ', '). Install with: Install-Module Az -Scope CurrentUser"
    }

    $requiredStackCommands = @(
        'New-AzManagementGroupDeploymentStack'
        'Remove-AzManagementGroupDeploymentStack'
        'New-AzSubscriptionDeploymentStack'
        'Remove-AzSubscriptionDeploymentStack'
    )
    $missingStackCommands = @($requiredStackCommands | Where-Object {
            -not (Get-Command $_ -ErrorAction SilentlyContinue)
        })

    if ($missingStackCommands.Count -gt 0) {
        throw "The installed Az.Resources module does not provide: $($missingStackCommands -join ', '). Update with: Update-Module Az.Resources"
    }
}

function Connect-QuarantineAzure {
    [CmdletBinding()]
    param()

    $context = Get-AzContext -ErrorAction SilentlyContinue
    if ($null -eq $context -or $null -eq $context.Account) {
        throw 'No Azure PowerShell context is available in this session. Run Connect-AzAccount -Tenant <tenant-id>, verify Get-AzContext, and rerun the command.'
    }

    Write-Verbose "Using Azure context for account '$($context.Account.Id)' in tenant '$($context.Tenant.Id)'."
}

function Wait-QuarantineAzJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Job]$Job,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Activity
    )

    $spinner = @('|', '/', '-', '\')
    $spinnerIndex = 0
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        while ($Job.State -in @('NotStarted', 'Running')) {
            $elapsed = $stopwatch.Elapsed.ToString('hh\:mm\:ss')
            Write-Progress `
                -Activity $Activity `
                -Status "$($spinner[$spinnerIndex % $spinner.Count]) Elapsed $elapsed" `
                -PercentComplete -1
            $spinnerIndex++
            Wait-Job -Job $Job -Timeout 1 | Out-Null
        }

        $result = Receive-Job -Job $Job -Wait -ErrorAction Stop
        if ($Job.State -ne 'Completed') {
            throw "$Activity ended with job state '$($Job.State)'."
        }

        $elapsed = $stopwatch.Elapsed.ToString('hh\:mm\:ss')
        Write-Host "$Activity completed in $elapsed."
        return $result
    }
    finally {
        $stopwatch.Stop()
        Write-Progress -Activity $Activity -Completed
        Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
    }
}

function Start-QuarantineAzRemovalJob {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Job])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Remove-AzSubscriptionDeploymentStack', 'Remove-AzManagementGroupDeploymentStack')]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [hashtable]$Parameters
    )

    if (-not (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)) {
        throw 'Start-ThreadJob is required to display progress during deployment-stack removal.'
    }

    return Start-ThreadJob -ArgumentList $CommandName, $Parameters -ScriptBlock {
        param($RemovalCommand, $RemovalParameters)

        Import-Module Az.Resources -ErrorAction Stop
        & $RemovalCommand @RemovalParameters -ErrorAction Stop
    }
}

function Export-QuarantineArmTemplate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$TemplateFile
    )

    $bicepCommand = Get-Command bicep -ErrorAction SilentlyContinue
    if ($null -eq $bicepCommand) {
        throw 'The Bicep CLI is required for deployment progress. Install Bicep and ensure bicep.exe is available on PATH.'
    }

    $compiledTemplate = Join-Path ([System.IO.Path]::GetTempPath()) "$([System.IO.Path]::GetRandomFileName()).json"
    & $bicepCommand.Source build $TemplateFile --outfile $compiledTemplate
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $compiledTemplate -PathType Leaf)) {
        Remove-Item -LiteralPath $compiledTemplate -Force -ErrorAction SilentlyContinue
        throw "Bicep compilation failed for '$TemplateFile'."
    }

    return $compiledTemplate
}

function Get-SubscriptionScope {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [guid]$SubscriptionId
    )

    return "/subscriptions/$SubscriptionId"
}

function Get-SubscriptionParentManagementGroupId {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [guid]$SubscriptionId
    )

    $path = "/subscriptions/$SubscriptionId/providers/Microsoft.Management/managementGroupSubscriptions/default?api-version=2020-05-01"
    $response = Invoke-AzRestMethod -Method GET -Path $path -ErrorAction Stop
    $content = $response.Content | ConvertFrom-Json
    return [string]$content.properties.parent.id
}

function Test-ControlPlaneWriteRole {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        $RoleDefinition
    )

    foreach ($action in @($RoleDefinition.Actions)) {
        if ($action -eq '*' -or $action -notmatch '/read$') {
            return $true
        }
    }

    return $false
}

function Get-DirectControlPlaneWriteAssignment {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [guid]$SubscriptionId
    )

    $subscriptionScope = Get-SubscriptionScope -SubscriptionId $SubscriptionId
    $assignments = @(Get-AzRoleAssignment -Scope $subscriptionScope -ErrorAction Stop)
    $roleCache = @{}
    $roleDefinitions = @()
    $roleDefinitionError = $null

    foreach ($attempt in 1..3) {
        try {
            $roleDefinitions = @(Get-AzRoleDefinition -ErrorAction Stop)
            $roleDefinitionError = $null
            break
        }
        catch {
            $roleDefinitionError = $_
            Write-Warning "Role-definition lookup attempt $attempt of 3 failed: $($_.Exception.Message)"
        }
    }

    $classificationBasis = 'RoleDefinitionActions'
    if ($null -ne $roleDefinitionError) {
        $classificationBasis = 'ConservativeFallback'
        Write-Warning 'Azure role definitions could not be retrieved. Readiness will exclude only the built-in Reader role and flag every other direct assignment for review. Do not approve RBAC removal until each flagged role has been verified.'
    }
    else {
        foreach ($roleDefinition in $roleDefinitions) {
            $roleCache[[string]$roleDefinition.Id] = $roleDefinition
        }
    }

    $readerRoleDefinitionId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
    foreach ($assignment in $assignments) {
        if (-not $assignment.Scope.StartsWith($subscriptionScope, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $roleDefinitionId = [string]$assignment.RoleDefinitionId
        if ($classificationBasis -eq 'RoleDefinitionActions') {
            if (-not $roleCache.ContainsKey($roleDefinitionId)) {
                throw "Role definition '$roleDefinitionId' referenced by assignment '$($assignment.RoleAssignmentId)' was not returned by Azure."
            }
            $requiresReview = Test-ControlPlaneWriteRole -RoleDefinition $roleCache[$roleDefinitionId]
        }
        else {
            $requiresReview = $roleDefinitionId -ne $readerRoleDefinitionId
        }

        if ($requiresReview) {
            [pscustomobject]@{
                ObjectId           = [string]$assignment.ObjectId
                DisplayName        = [string]$assignment.DisplayName
                ObjectType         = [string]$assignment.ObjectType
                RoleDefinitionId   = $roleDefinitionId
                RoleDefinitionName = [string]$assignment.RoleDefinitionName
                Scope              = [string]$assignment.Scope
                ClassificationBasis = $classificationBasis
            }
        }
    }
}

function Get-QuarantineLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [guid]$SubscriptionId,

        [Parameter()]
        [string]$LockName = 'decommission-quarantine'
    )

    $scope = Get-SubscriptionScope -SubscriptionId $SubscriptionId
    return Get-AzResourceLock -Scope $scope -AtScope -ErrorAction SilentlyContinue |
        Where-Object Name -eq $LockName
}

function New-QuarantineLockDeployment {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [guid]$SubscriptionId,

        [Parameter(Mandatory)]
        [string]$Notes,

        [Parameter(Mandatory)]
        [string]$TemplateFile,

        [Parameter()]
        [string]$LockName = 'decommission-quarantine',

        [Parameter()]
        [string]$StackName = 'tenant-decommission-quarantine-lock',

        [Parameter()]
        [string]$DeploymentLocation = 'australiaeast'
    )

    if ($PSCmdlet.ShouldProcess($SubscriptionId, "Apply ReadOnly lock '$LockName'")) {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        $compiledTemplate = Export-QuarantineArmTemplate -TemplateFile $TemplateFile
        try {
            $deploymentJob = New-AzSubscriptionDeploymentStack `
                -Name $StackName `
                -Location $DeploymentLocation `
                -ActionOnUnmanage DeleteAll `
                -DenySettingsMode None `
                -TemplateFile $compiledTemplate `
                -TemplateParameterObject @{
                    lockName  = $LockName
                    lockNotes = $Notes
                } `
                -Force `
                -AsJob `
                -ErrorAction Stop

            Wait-QuarantineAzJob `
                -Job $deploymentJob `
                -Activity "Applying ReadOnly lock to subscription $SubscriptionId" | Out-Null
        }
        finally {
            Remove-Item -LiteralPath $compiledTemplate -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function @(
    'Assert-QuarantineAzModule'
    'Connect-QuarantineAzure'
    'Export-QuarantineArmTemplate'
    'Get-DirectControlPlaneWriteAssignment'
    'Get-QuarantineLock'
    'Get-SubscriptionParentManagementGroupId'
    'Get-SubscriptionScope'
    'New-QuarantineLockDeployment'
    'Start-QuarantineAzRemovalJob'
    'Wait-QuarantineAzJob'
)