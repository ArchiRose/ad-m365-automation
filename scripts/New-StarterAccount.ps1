#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Creates a starter's Active Directory account from an approved request.

.DESCRIPTION
    Checks the request first: the department must be in the role table, the manager and the
    department OU must exist, and the account name must be free. Only then does it create the
    user with a temporary password that must be changed at first sign-in, and add the groups
    listed for that department in config/role-groups.csv and nothing else.

    Every run is written to logs/jml-audit.csv with the ticket number.
    Run with -WhatIf first to see exactly what would change.

.PARAMETER Ticket
    The approved request number, recorded in the audit log.

.EXAMPLE
    .\New-StarterAccount.ps1 -FirstName Priya -LastName Shah -Department Finance -Manager j.bloggs -Ticket REQ0012345 -WhatIf

.EXAMPLE
    .\New-StarterAccount.ps1 -FirstName Priya -LastName Shah -Department Finance -Manager j.bloggs -Ticket REQ0012345
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [ValidatePattern("^[A-Za-z][A-Za-z' -]{0,49}$")] [string] $FirstName,
    [Parameter(Mandatory)] [ValidatePattern("^[A-Za-z][A-Za-z' -]{0,49}$")] [string] $LastName,
    [Parameter(Mandatory)] [string] $Department,
    [Parameter(Mandatory)] [string] $Manager,
    [Parameter(Mandatory)] [string] $Ticket,
    [string] $UpnSuffix = 'lab.local',
    [string] $StaffOU = 'OU=Staff,DC=lab,DC=local',
    [string] $RoleTable = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'config/role-groups.csv')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'JmlCommon.ps1')

# 1. Validate the whole request before changing anything.
$groups     = @(Get-RoleGroups -Department $Department -RoleTable $RoleTable)
$managerObj = Get-ADUser -Identity $Manager
$ou         = "OU=$Department,$StaffOU"
Get-ADOrganizationalUnit -Identity $ou | Out-Null

$sam = (('{0}.{1}' -f $FirstName, $LastName).ToLower() -replace "[^a-z.]", '')
if ($sam.Length -gt 20) { $sam = $sam.Substring(0, 20) }
if (Get-ADUser -Filter "SamAccountName -eq '$sam'") {
    throw "An account named '$sam' already exists. Agree a different name with the requester first."
}
$upn         = "$sam@$UpnSuffix"
$displayName = "$FirstName $LastName"

# 2. Create the account and apply role-based access.
if ($PSCmdlet.ShouldProcess($upn, "Create account in $ou and add $($groups.Count) role group(s)")) {
    $tempPassword = Read-Host -Prompt "Temporary password for $upn" -AsSecureString
    New-ADUser -Name $displayName -GivenName $FirstName -Surname $LastName -DisplayName $displayName `
        -SamAccountName $sam -UserPrincipalName $upn -Path $ou -Department $Department `
        -Manager $managerObj.DistinguishedName -AccountPassword $tempPassword `
        -ChangePasswordAtLogon $true -Enabled $true

    foreach ($group in $groups) {
        Add-ADGroupMember -Identity $group -Members $sam
    }

    Write-JmlAudit -Action JOINER -Account $sam -Ticket $Ticket `
        -Detail ('Created in {0}; groups: {1}' -f $ou, ($groups -join ', '))
    Write-Output "Created $upn with groups: $($groups -join ', '). Give the temporary password to the manager, not by email."
}
