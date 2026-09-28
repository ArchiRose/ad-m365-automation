#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Disables a leaver's account safely: record, remove access, disable, keep for 30 days.

.DESCRIPTION
    1. Records every group the user belongs to in logs/leaver-groups/<user>-<date>.csv, so access
       can be put back if the leaving date changes.
    2. Disables the account and removes its group memberships (Domain Users, the primary group,
       stays).
    3. Stamps the description with the date and ticket, and moves the account to the Disabled OU.
       The account is not deleted: deletion happens after 30 days as a separate, reviewed step.
    4. Optional cloud clean-up: -RevokeCloudSessions signs the user out of Microsoft 365
       (run Connect-MgGraph first) and -ConvertMailbox turns the mailbox into a shared mailbox
       (run Connect-ExchangeOnline first).

    Every run is written to logs/jml-audit.csv. Run with -WhatIf first.

.EXAMPLE
    .\Disable-LeaverAccount.ps1 -Identity priya.shah -Ticket REQ0012456 -RevokeCloudSessions -ConvertMailbox -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $Identity,
    [Parameter(Mandatory)] [string] $Ticket,
    [string] $DisabledOU = 'OU=Disabled,OU=Staff,DC=lab,DC=local',
    [switch] $RevokeCloudSessions,
    [switch] $ConvertMailbox,
    [string] $GroupRecordFolder = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'logs/leaver-groups')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'JmlCommon.ps1')

$user   = Get-ADUser -Identity $Identity -Properties MemberOf, UserPrincipalName
$groups = @($user.MemberOf | ForEach-Object { Get-ADGroup -Identity $_ })
$stamp  = Get-Date -Format 'yyyy-MM-dd'
Get-ADOrganizationalUnit -Identity $DisabledOU | Out-Null

if ($PSCmdlet.ShouldProcess($user.SamAccountName, "Record and remove $($groups.Count) group(s), disable, move to $DisabledOU")) {
    # 1. Record memberships before removing anything.
    if (-not (Test-Path -LiteralPath $GroupRecordFolder)) {
        New-Item -Path $GroupRecordFolder -ItemType Directory -Force | Out-Null
    }
    $record = Join-Path $GroupRecordFolder ('{0}-{1}.csv' -f $user.SamAccountName, $stamp)
    $groups | Select-Object Name, DistinguishedName | Export-Csv -LiteralPath $record -NoTypeInformation

    # 2. Disable and remove access.
    Disable-ADAccount -Identity $user
    foreach ($group in $groups) {
        Remove-ADGroupMember -Identity $group -Members $user -Confirm:$false
    }

    # 3. Label and park the account. It is kept, not deleted.
    Set-ADUser -Identity $user -Description ('Leaver {0} ({1}). Disabled, delete after 30 days.' -f $stamp, $Ticket)
    Move-ADObject -Identity $user.DistinguishedName -TargetPath $DisabledOU

    # 4. Optional cloud clean-up.
    if ($RevokeCloudSessions) {
        Revoke-MgUserSignInSession -UserId $user.UserPrincipalName | Out-Null
    }
    if ($ConvertMailbox) {
        Set-Mailbox -Identity $user.UserPrincipalName -Type Shared
    }

    $detail = 'Disabled; {0} group(s) recorded in {1} and removed; cloud sessions revoked: {2}; mailbox shared: {3}' -f `
        $groups.Count, $record, [bool]$RevokeCloudSessions, [bool]$ConvertMailbox
    Write-JmlAudit -Action LEAVER -Account $user.SamAccountName -Ticket $Ticket -Detail $detail
    Write-Output $detail
}
