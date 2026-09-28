#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users
<#
.SYNOPSIS
    Weekly report of Microsoft 365 accounts and licences that need attention. Changes nothing.

.DESCRIPTION
    Flags three things:
      - disabled accounts that still hold licences (money spent on nobody)
      - enabled accounts with no sign-in for -InactiveDays days
      - guest accounts with no sign-in for -InactiveDays days
    Each row gets a suggested action and an empty 'Approved' column for the IT lead to fill in.
    Accounts in config/hygiene-exceptions.txt (break-glass and service accounts) are never flagged.

    Read-only Graph scopes. Last sign-in data needs AuditLog.Read.All and Entra ID P1 or P2.

.EXAMPLE
    .\Get-M365HygieneReport.ps1 -InactiveDays 60
#>
[CmdletBinding()]
param(
    [ValidateRange(7, 365)] [int] $InactiveDays = 60,
    [string] $ExceptionsFile = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'config/hygiene-exceptions.txt'),
    [string] $OutFile = ('m365-hygiene-{0}.csv' -f (Get-Date -Format 'yyyy-MM-dd'))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Connect-MgGraph -Scopes 'User.Read.All', 'AuditLog.Read.All' -NoWelcome
$cutoff = (Get-Date).AddDays(-$InactiveDays)

$exceptions = @()
if (Test-Path -LiteralPath $ExceptionsFile) {
    $exceptions = @(Get-Content -LiteralPath $ExceptionsFile |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') } |
        ForEach-Object { $_.ToLower() })
}

$properties = @('DisplayName', 'UserPrincipalName', 'UserType', 'AccountEnabled', 'AssignedLicenses', 'SignInActivity')
$users = @(Get-MgUser -All -Property $properties)

$findings = @(foreach ($u in $users) {
    if ($exceptions -contains ([string]$u.UserPrincipalName).ToLower()) { continue }

    $lastSignIn = $null
    if ($u.SignInActivity) { $lastSignIn = $u.SignInActivity.LastSignInDateTime }
    $licences = @($u.AssignedLicenses).Count
    $finding  = $null
    $action   = $null

    if (-not $u.AccountEnabled -and $licences -gt 0) {
        $finding = 'Disabled but still licensed'
        $action  = 'Remove licences'
    }
    elseif ($u.UserType -eq 'Guest' -and (-not $lastSignIn -or $lastSignIn -lt $cutoff)) {
        $finding = "Guest with no sign-in for $InactiveDays+ days"
        $action  = 'Check with the sponsor, then remove'
    }
    elseif ($u.AccountEnabled -and $lastSignIn -and $lastSignIn -lt $cutoff) {
        $finding = "No sign-in for $InactiveDays+ days"
        $action  = 'Confirm with the manager, then disable'
    }

    if ($finding) {
        [pscustomobject]@{
            DisplayName       = $u.DisplayName
            UserPrincipalName = $u.UserPrincipalName
            UserType          = $u.UserType
            Enabled           = $u.AccountEnabled
            Licences          = $licences
            LastSignIn        = $lastSignIn
            Finding           = $finding
            SuggestedAction   = $action
            Approved          = ''
        }
    }
})

$findings | Sort-Object -Property Finding, DisplayName | Export-Csv -LiteralPath $OutFile -NoTypeInformation
Write-Output ('{0} account(s) need attention. Report saved to {1}. Nothing was changed.' -f $findings.Count, $OutFile)
