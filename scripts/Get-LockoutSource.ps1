#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Finds which device keeps locking an account.

.DESCRIPTION
    Reads account lockout events (Event ID 4740) from the PDC emulator, which records every
    lockout in the domain. Each event names the locked account and the caller computer, the
    device that sent the bad passwords. That is usually a phone with an old mail password,
    a mapped drive or a scheduled task.

    Read-only. Needs rights to read the Security log on the PDC emulator.
    Check the caller's identity before you unlock or reset anything.

.EXAMPLE
    .\Get-LockoutSource.ps1 -UserName priya.shah -Hours 48

.EXAMPLE
    .\Get-LockoutSource.ps1 -Summary
    Groups the last 24 hours of lockouts by account and device, busiest first.
#>
[CmdletBinding()]
param(
    [string] $UserName,
    [ValidateRange(1, 720)] [int] $Hours = 24,
    [switch] $Summary
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pdc    = (Get-ADDomain).PDCEmulator
$filter = @{ LogName = 'Security'; Id = 4740; StartTime = (Get-Date).AddHours(-$Hours) }

try {
    $events = @(Get-WinEvent -ComputerName $pdc -FilterHashtable $filter)
}
catch {
    if ($_.Exception.Message -match 'No events were found') {
        Write-Output "No lockouts in the last $Hours hour(s) on $pdc."
        return
    }
    throw
}

# 4740: Properties[0] = locked account, Properties[1] = caller computer (the source device).
$lockouts = @($events | ForEach-Object {
    [pscustomobject]@{
        Time   = $_.TimeCreated
        User   = [string]$_.Properties[0].Value
        Device = [string]$_.Properties[1].Value
    }
})
if ($UserName) {
    $lockouts = @($lockouts | Where-Object { $_.User -eq $UserName })
}

if ($Summary) {
    $lockouts |
        Group-Object -Property User, Device |
        Sort-Object -Property Count -Descending |
        Select-Object Count,
            @{ Name = 'User';   Expression = { $_.Group[0].User } },
            @{ Name = 'Device'; Expression = { $_.Group[0].Device } },
            @{ Name = 'Latest'; Expression = { ($_.Group | Sort-Object Time -Descending)[0].Time } }
}
else {
    $lockouts | Sort-Object -Property Time -Descending
}
