[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [guid]$SubscriptionId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path $PWD "quarantine-readiness-$SubscriptionId-$(Get-Date -Format 'yyyyMMddHHmmss').json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Quarantine.Common.psm1') -Force
Assert-QuarantineAzModule
Connect-QuarantineAzure -Verbose:($VerbosePreference -eq 'Continue')
Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null

$scope = Get-SubscriptionScope -SubscriptionId $SubscriptionId
$subscription = Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop
$resources = @(Get-AzResource -ErrorAction Stop)
$roleAssignments = @(Get-AzRoleAssignment -Scope $scope -ErrorAction Stop)
$writeAssignments = @(Get-DirectControlPlaneWriteAssignment -SubscriptionId $SubscriptionId)
$locks = @(Get-AzResourceLock -Scope $scope -ErrorAction SilentlyContinue)
$policyAssignments = @(Get-AzPolicyAssignment -Scope $scope -IncludeDescendent -ErrorAction Stop)
$policyExemptions = @(Get-AzPolicyExemption -Scope $scope -ErrorAction SilentlyContinue)

$resourceTypeSummary = @($resources |
    Group-Object ResourceType |
    Sort-Object Name |
    ForEach-Object {
        [pscustomobject]@{
            ResourceType = [string]$_.Name
            Count        = $_.Count
        }
    })
$roleAssignmentSummary = @($roleAssignments | ForEach-Object {
        [pscustomobject]@{
            Role              = [string]$_.RoleDefinitionName
            PrincipalName     = [string]$_.DisplayName
            PrincipalObjectId = [string]$_.ObjectId
            PrincipalType     = [string]$_.ObjectType
            Scope             = [string]$_.Scope
        }
    })
$lockSummary = @($locks | ForEach-Object {
        [pscustomobject]@{
            Name  = [string]$_.Name
            Level = [string]$_.Properties.Level
            Scope = [string]$_.ResourceId
            Notes = [string]$_.Properties.Notes
        }
    })
$policyAssignmentSummary = @($policyAssignments | ForEach-Object {
        [pscustomobject]@{
            Name            = [string]$_.Name
            DisplayName     = [string]$_.DisplayName
            Scope           = [string]$_.Scope
            EnforcementMode = [string]$_.EnforcementMode
        }
    })
$policyExemptionSummary = @($policyExemptions | ForEach-Object {
        [pscustomobject]@{
            Name               = [string]$_.Name
            DisplayName        = [string]$_.DisplayName
            Scope              = [string]$_.Scope
            PolicyAssignmentId = [string]$_.PolicyAssignmentId
            Category           = [string]$_.ExemptionCategory
            ExpiresOn          = $_.ExpiresOn
        }
    })

$evidence = [ordered]@{
    GeneratedAtUtc                = (Get-Date).ToUniversalTime().ToString('o')
    Subscription                  = [ordered]@{
        Id       = [string]$subscription.Id
        Name     = [string]$subscription.Name
        State    = [string]$subscription.State
        TenantId = [string]$subscription.TenantId
    }
    ParentManagementGroupId       = Get-SubscriptionParentManagementGroupId -SubscriptionId $SubscriptionId
    ResourceCount                 = $resources.Count
    ResourceTypeSummary           = $resourceTypeSummary
    RoleAssignmentCount           = $roleAssignments.Count
    RoleAssignments               = $roleAssignmentSummary
    DirectWriteAssignmentCount    = $writeAssignments.Count
    DirectControlPlaneWriteRoles  = $writeAssignments
    LockCount                     = $locks.Count
    Locks                         = $lockSummary
    PolicyAssignmentCount         = $policyAssignments.Count
    PolicyAssignments             = $policyAssignmentSummary
    PolicyExemptionCount          = $policyExemptions.Count
    PolicyExemptions              = $policyExemptionSummary
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$evidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8

[pscustomobject]@{
    SubscriptionId               = [string]$SubscriptionId
    ResourceCount                = $resources.Count
    DirectWriteAssignmentCount   = $writeAssignments.Count
    LockCount                    = $locks.Count
    PolicyAssignmentCount        = $policyAssignments.Count
    EvidencePath                 = (Resolve-Path -LiteralPath $OutputPath).Path
}