#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Moves a user to a new department: old role groups out, new role groups in.

.DESCRIPTION
    Works out the difference between the groups the user holds from the role table and the groups
    the new department should have. It removes only role-table groups the new role does not need,
    and adds only the missing ones. Groups granted outside the role table are left alone and listed
    so someone can review them. Then it updates the department and moves the account to the new OU.

    Every run is written to logs/jml-audit.csv. Run with -WhatIf first.

.EXAMPLE
    .\Set-MoverAccess.ps1 -Identity priya.shah -NewDepartment Sales -Ticket REQ0012399 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $Identity,
    [Parameter(Mandatory)] [string] $NewDepartment,
    [Parameter(Mandatory)] [string] $Ticket,
    [string] $StaffOU = 'OU=Staff,DC=lab,DC=local',
    [string] $RoleTable = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'config/role-groups.csv')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'JmlCommon.ps1')

$user     = Get-ADUser -Identity $Identity -Properties Department, MemberOf
$targetOU = "OU=$NewDepartment,$StaffOU"
Get-ADOrganizationalUnit -Identity $targetOU | Out-Null

$target  = @(Get-RoleGroups -Department $NewDepartment -RoleTable $RoleTable)
$managed = @(Get-ManagedGroups -RoleTable $RoleTable)
$held    = @($user.MemberOf | ForEach-Object { (Get-ADGroup -Identity $_).Name })

$current = @($held | Where-Object { $managed -contains $_ })
$other   = @($held | Where-Object { $managed -notcontains $_ })
$remove  = @($current | Where-Object { $target -notcontains $_ })
$add     = @($target | Where-Object { $current -notcontains $_ })

$summary = "Move from '{0}' to '{1}': remove [{2}], add [{3}]" -f $user.Department, $NewDepartment, ($remove -join ', '), ($add -join ', ')
if ($PSCmdlet.ShouldProcess($user.SamAccountName, $summary)) {
    foreach ($group in $remove) {
        Remove-ADGroupMember -Identity $group -Members $user -Confirm:$false
    }
    foreach ($group in $add) {
        Add-ADGroupMember -Identity $group -Members $user
    }
    Set-ADUser -Identity $user -Department $NewDepartment
    Move-ADObject -Identity $user.DistinguishedName -TargetPath $targetOU

    Write-JmlAudit -Action MOVER -Account $user.SamAccountName -Ticket $Ticket -Detail $summary
    Write-Output $summary
}

if ($other.Count -gt 0) {
    Write-Warning ("{0} also holds groups outside the role table. Ask the new manager whether these are still needed: {1}" -f $user.SamAccountName, ($other -join ', '))
}
