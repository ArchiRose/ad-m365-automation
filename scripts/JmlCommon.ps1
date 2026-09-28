<#
.SYNOPSIS
    Shared helpers for the joiner, mover and leaver scripts.

.DESCRIPTION
    Dot-sourced by New-StarterAccount.ps1, Set-MoverAccess.ps1 and Disable-LeaverAccount.ps1.
    The role table (config/role-groups.csv) is the single source of truth for which groups
    a department gets. The scripts only add or remove groups that appear in that table,
    so anything granted by another process is left alone.
#>

function Get-RoleGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Department,
        [Parameter(Mandatory)] [string] $RoleTable
    )
    if (-not (Test-Path -LiteralPath $RoleTable)) {
        throw "Role table not found: $RoleTable"
    }
    $groups = @(Import-Csv -LiteralPath $RoleTable |
        Where-Object { $_.Department -eq $Department } |
        ForEach-Object { $_.Group })
    if ($groups.Count -eq 0) {
        throw "No groups are defined for department '$Department' in $RoleTable. Add them before running."
    }
    return $groups
}

function Get-ManagedGroups {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RoleTable)
    @(Import-Csv -LiteralPath $RoleTable | ForEach-Object { $_.Group } | Sort-Object -Unique)
}

function Write-JmlAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('JOINER', 'MOVER', 'LEAVER')] [string] $Action,
        [Parameter(Mandatory)] [string] $Account,
        [Parameter(Mandatory)] [string] $Ticket,
        [Parameter(Mandatory)] [string] $Detail,
        [string] $AuditLog = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'logs/jml-audit.csv')
    )
    $folder = Split-Path -Path $AuditLog -Parent
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }
    [pscustomobject]@{
        Timestamp = (Get-Date).ToString('s')
        Action    = $Action
        Account   = $Account
        Ticket    = $Ticket
        Detail    = $Detail
        RunBy     = [Environment]::UserName
    } | Export-Csv -LiteralPath $AuditLog -Append -NoTypeInformation
}
