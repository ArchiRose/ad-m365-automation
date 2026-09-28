# AD and Microsoft 365 automation

PowerShell scripts for the service desk jobs that are repetitive and easy to get wrong by hand: starters, role changes, leavers, account lockouts and Microsoft 365 licence tidy-up.

Every script that changes something checks the request first, supports `-WhatIf` and writes an audit log. None of them delete an account.

Part of my portfolio: [archirose.github.io](https://archirose.github.io) (designs IT-01, IT-03 and IT-04).

| Script | What it does | Changes things? |
|---|---|---|
| [`New-StarterAccount.ps1`](scripts/New-StarterAccount.ps1) | Creates a starter in the right OU with the groups for their role, and a temporary password they must change at first sign-in | Yes, with `-WhatIf` support |
| [`Set-MoverAccess.ps1`](scripts/Set-MoverAccess.ps1) | Removes the old role's groups, adds the new role's, then updates the department and moves the account to the new OU. Groups granted outside the role table are flagged for review, not removed | Yes, with `-WhatIf` support |
| [`Disable-LeaverAccount.ps1`](scripts/Disable-LeaverAccount.ps1) | Records every group the leaver belongs to, removes those groups, disables the account and parks it in a Disabled OU for 30 days. Optionally it also signs the user out of Microsoft 365 and converts their mailbox to shared | Yes, with `-WhatIf` support |
| [`Get-LockoutSource.ps1`](scripts/Get-LockoutSource.ps1) | Reads Event 4740 on the PDC emulator to find which device keeps locking an account | No |
| [`Get-M365HygieneReport.ps1`](scripts/Get-M365HygieneReport.ps1) | Lists disabled users who still hold licences, inactive accounts and stale guests, each with a suggested action for a person to approve | No |

## How access is decided

[`config/role-groups.csv`](config/role-groups.csv) is the single source of truth for access. Each department maps to a list of groups:

```csv
Department,Group
Finance,GG-All-Staff
Finance,GG-Finance-Staff
Finance,GG-Finance-Share-Modify
```

Starters get exactly those groups. Movers lose role-table groups the new role does not include. Access granted any other way is never added or removed silently, so the role table decides access and nothing else does.

## Safety rules built in

- **Check first.** Before anything changes, the scripts confirm that the manager, the department's OU and the role-table entry all exist, and that the new account name is free.
- **Preview everything.** `-WhatIf` prints each change without making it. Run it first, every time.
- **Keep leavers for 30 days.** Leavers are disabled and moved, never deleted. Their group memberships are saved to `logs/leaver-groups/` so access can be restored if the leaving date moves.
- **Leave an audit trail.** Each run adds a row to `logs/jml-audit.csv` with the time, action, account, ticket number and who ran it.
- **Reports change nothing.** The two report scripts only read. The hygiene report has an empty `Approved` column for the IT lead to fill in, and it skips break-glass and service accounts listed in [`config/hygiene-exceptions.txt`](config/hygiene-exceptions.txt).

## Requirements

- Windows PowerShell 5.1 or PowerShell 7 on a machine with **RSAT: Active Directory** (the `ActiveDirectory` module), for the AD scripts.
- `Microsoft.Graph.Authentication` and `Microsoft.Graph.Users` for the hygiene report. For `Disable-LeaverAccount.ps1 -RevokeCloudSessions` you also need `Microsoft.Graph.Users.Actions`, and for `-ConvertMailbox` you need `ExchangeOnlineManagement`.
- The default OU layout is `OU=<Department>,OU=Staff,DC=lab,DC=local`, plus `OU=Disabled,OU=Staff,...` for leavers. Change the `-StaffOU`, `-DisabledOU` and `-UpnSuffix` parameters to match your domain.

## Examples

```powershell
# Starter: preview, then run
.\scripts\New-StarterAccount.ps1 -FirstName Priya -LastName Shah -Department Finance -Manager j.bloggs -Ticket REQ0012345 -WhatIf
.\scripts\New-StarterAccount.ps1 -FirstName Priya -LastName Shah -Department Finance -Manager j.bloggs -Ticket REQ0012345

# Mover
.\scripts\Set-MoverAccess.ps1 -Identity priya.shah -NewDepartment Sales -Ticket REQ0012399 -WhatIf

# Leaver, including Microsoft 365 sign-out and shared mailbox
Connect-MgGraph -Scopes 'User.RevokeSessions.All'
Connect-ExchangeOnline
.\scripts\Disable-LeaverAccount.ps1 -Identity priya.shah -Ticket REQ0012456 -RevokeCloudSessions -ConvertMailbox -WhatIf

# Which device keeps locking this account?
.\scripts\Get-LockoutSource.ps1 -UserName priya.shah -Hours 48

# Weekly licence and account tidy-up report
.\scripts\Get-M365HygieneReport.ps1 -InactiveDays 60
```

## Testing status

These scripts need a Windows domain and a Microsoft 365 tenant to run. This repository has no automated tests for them, and they have not been run from here. Run each one with `-WhatIf` against a lab domain before any real use.

## Licence

MIT
