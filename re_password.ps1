# Account Management Script - Requires administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Please run this script as administrator!" -ForegroundColor Red
    Write-Host "Right-click on PowerShell and select 'Run as administrator'" -ForegroundColor Yellow
    pause
    exit
}

Write-Host "================================" -ForegroundColor Cyan
Write-Host "   Windows Account Management Tool" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Please select an operation:" -ForegroundColor Yellow
Write-Host "1. Create new account"
Write-Host "2. Change existing account password"
Write-Host "3. View all local accounts"
Write-Host "4. Delete account"
Write-Host "5. Manage account group membership"
Write-Host "6. Exit"
Write-Host ""

$choice = Read-Host "Enter option (1-6)"

switch ($choice) {
    "1" {
        Write-Host "`n=== Create New Account ===" -ForegroundColor Green
        $username = Read-Host "Enter new username"

        $userExists = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
        if ($userExists) {
            Write-Host "Error: Account '$username' already exists!" -ForegroundColor Red
            pause
            exit
        }

        $password = Read-Host "Enter password" -AsSecureString
        $passwordConfirm = Read-Host "Confirm password" -AsSecureString

        $pwd1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
        $pwd2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordConfirm))

        if ($pwd1 -ne $pwd2) {
            Write-Host "Error: Passwords do not match!" -ForegroundColor Red
            pause
            exit
        }

        try {
            New-LocalUser -Name $username -Password $password -FullName $username -Description "Account created via script" -PasswordNeverExpires -ErrorAction Stop
            Write-Host "Successfully created account: $username" -ForegroundColor Green

            Set-LocalUser -Name $username -PasswordNeverExpires $true
            Write-Host "Password set to never expire" -ForegroundColor Green

            $addToRDP = Read-Host "`nAllow this account to use Remote Desktop? (Y/N)"
            if ($addToRDP -eq "Y" -or $addToRDP -eq "y") {
                Add-LocalGroupMember -Group "Remote Desktop Users" -Member $username -ErrorAction SilentlyContinue
                Write-Host "Added to Remote Desktop Users group" -ForegroundColor Green
            }

            $addToUsers = Read-Host "`nAllow this account to login locally (add to Users group)? (Y/N)"
            if ($addToUsers -eq "Y" -or $addToUsers -eq "y") {
                Add-LocalGroupMember -Group "Users" -Member $username -ErrorAction Stop
                Write-Host "Added to Users group - account will be visible on login screen" -ForegroundColor Green
            } else {
                Write-Host "Not added to Users group - account will only be accessible via Remote Desktop" -ForegroundColor Yellow
            }

            $addToAdmin = Read-Host "`nGrant administrator privileges (add to Administrators group)? (Y/N)"
            if ($addToAdmin -eq "Y" -or $addToAdmin -eq "y") {
                Add-LocalGroupMember -Group "Administrators" -Member $username -ErrorAction Stop
                Write-Host "Added to Administrators group - account has full system privileges" -ForegroundColor Magenta
                Write-Host "WARNING: This account now has full administrative access!" -ForegroundColor Red
            } else {
                Write-Host "Not added to Administrators group - account has standard user privileges" -ForegroundColor Green
            }

            Write-Host "`n=== Account Information ===" -ForegroundColor Cyan
            Get-LocalUser -Name $username | Select-Object Name, Enabled, PasswordExpires, PasswordNeverExpires, LastLogon | Format-List

        } catch {
            Write-Host "Error: Failed to create account!" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }

    "2" {
        Write-Host "`n=== Change Account Password ===" -ForegroundColor Green
        Write-Host "`nCurrent local accounts:" -ForegroundColor Yellow
        Get-LocalUser | Select-Object Name, Enabled | Format-Table

        $username = Read-Host "Enter username to modify"

        $userExists = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
        if (-not $userExists) {
            Write-Host "Error: Account '$username' does not exist!" -ForegroundColor Red
            pause
            exit
        }

        $password = Read-Host "Enter new password" -AsSecureString
        $passwordConfirm = Read-Host "Confirm new password" -AsSecureString

        $pwd1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
        $pwd2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordConfirm))

        if ($pwd1 -ne $pwd2) {
            Write-Host "Error: Passwords do not match!" -ForegroundColor Red
            pause
            exit
        }

        try {
            Set-LocalUser -Name $username -Password $password -PasswordNeverExpires $true -ErrorAction Stop
            Write-Host "Successfully updated password for account: $username" -ForegroundColor Green
            Write-Host "Password set to never expire" -ForegroundColor Green

            Write-Host "`n=== Account Information ===" -ForegroundColor Cyan
            Get-LocalUser -Name $username | Select-Object Name, Enabled, PasswordExpires, PasswordNeverExpires, LastLogon | Format-List

            # Check and manage Remote Desktop Users group
            $inRDPGroup = Get-LocalGroupMember -Group "Remote Desktop Users" -ErrorAction SilentlyContinue | Where-Object {$_.Name -like "*$username"}
            if ($inRDPGroup) {
                Write-Host "This account is already in Remote Desktop Users group" -ForegroundColor Green
            } else {
                $addToRDP = Read-Host "`nAllow this account to use Remote Desktop? (Y/N)"
                if ($addToRDP -eq "Y" -or $addToRDP -eq "y") {
                    Add-LocalGroupMember -Group "Remote Desktop Users" -Member $username -ErrorAction SilentlyContinue
                    Write-Host "Added to Remote Desktop Users group" -ForegroundColor Green
                }
            }

            # Check and manage Users group
            $inUsersGroup = Get-LocalGroupMember -Group "Users" -ErrorAction SilentlyContinue | Where-Object {$_.Name -like "*$username"}
            if ($inUsersGroup) {
                Write-Host "This account is already in Users group" -ForegroundColor Green
            } else {
                $addToUsers = Read-Host "`nAllow this account to login locally (add to Users group)? (Y/N)"
                if ($addToUsers -eq "Y" -or $addToUsers -eq "y") {
                    Add-LocalGroupMember -Group "Users" -Member $username -ErrorAction Stop
                    Write-Host "Added to Users group - account will be visible on login screen" -ForegroundColor Green
                }
            }

            # Check and manage Administrators group
            $inAdminGroup = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Where-Object {$_.Name -like "*$username"}
            if ($inAdminGroup) {
                Write-Host "This account is already in Administrators group" -ForegroundColor Magenta
            } else {
                $addToAdmin = Read-Host "`nGrant administrator privileges (add to Administrators group)? (Y/N)"
                if ($addToAdmin -eq "Y" -or $addToAdmin -eq "y") {
                    Add-LocalGroupMember -Group "Administrators" -Member $username -ErrorAction Stop
                    Write-Host "Added to Administrators group - account has full system privileges" -ForegroundColor Magenta
                    Write-Host "WARNING: This account now has full administrative access!" -ForegroundColor Red
                }
            }

        } catch {
            Write-Host "Error: Failed to update password!" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }

    "3" {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "        All Local Accounts Details" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan

        # Get all local users and display detailed information
        $users = Get-LocalUser | Select-Object `
            Name,
            Enabled,
            @{Name="Password Never Expires";Expression={$_.PasswordNeverExpires}},
            @{Name="Password Expiry";Expression={if ($_.PasswordExpires) {$_.PasswordExpires.ToString("yyyy/MM/dd HH:mm")} else {"None"}}},
            @{Name="Password Last Set";Expression={if ($_.PasswordLastSet) {$_.PasswordLastSet.ToString("yyyy/MM/dd HH:mm")} else {"Unknown"}}},
            @{Name="Last Logon";Expression={if ($_.LastLogon) {$_.LastLogon.ToString("yyyy/MM/dd HH:mm")} else {"Never"}}},
            @{Name="Account Expiry";Expression={if ($_.AccountExpires) {$_.AccountExpires.ToString("yyyy/MM/dd HH:mm")} else {"Never"}}},
            Description,
            @{Name="Password Required";Expression={$_.PasswordRequired}},
            @{Name="User May Change Password";Expression={$_.UserMayChangePassword}}

        $users | Format-Table -AutoSize -Wrap

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "     Remote Desktop Users Group Members" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan

        $rdpUsers = Get-LocalGroupMember -Group "Remote Desktop Users" -ErrorAction SilentlyContinue
        if ($rdpUsers) {
            $rdpUsers | Select-Object Name, ObjectClass,
                @{Name="Type";Expression={
                    switch ($_.ObjectClass) {
                        "User" {"User"}
                        "Group" {"Group"}
                        default {$_.ObjectClass}
                    }
                }} | Format-Table -AutoSize
        } else {
            Write-Host "No other users in Remote Desktop Users group" -ForegroundColor Yellow
        }

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "          Account Statistics" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan

        $allUsers = Get-LocalUser
        $enabledCount = ($allUsers | Where-Object {$_.Enabled -eq $true}).Count
        $disabledCount = ($allUsers | Where-Object {$_.Enabled -eq $false}).Count
        $neverExpireCount = ($allUsers | Where-Object {$_.PasswordNeverExpires -eq $true}).Count
        $neverLoginCount = ($allUsers | Where-Object {$_.LastLogon -eq $null}).Count

        Write-Host "Total Accounts:        $($allUsers.Count)" -ForegroundColor White
        Write-Host "Enabled Accounts:      $enabledCount" -ForegroundColor Green
        Write-Host "Disabled Accounts:     $disabledCount" -ForegroundColor Red
        Write-Host "Password Never Expires: $neverExpireCount" -ForegroundColor Yellow
        Write-Host "Never Logged In:       $neverLoginCount" -ForegroundColor Gray

        Write-Host "`nView details of a specific account? (Y/N)" -ForegroundColor Yellow
        $viewDetail = Read-Host

        if ($viewDetail -eq "Y" -or $viewDetail -eq "y") {
            $targetUser = Read-Host "Enter username to view"
            $userDetail = Get-LocalUser -Name $targetUser -ErrorAction SilentlyContinue

            if ($userDetail) {
                Write-Host "`n========================================" -ForegroundColor Cyan
                Write-Host "    Account '$targetUser' Details" -ForegroundColor Cyan
                Write-Host "========================================" -ForegroundColor Cyan

                $userDetail | Format-List Name, FullName, Description, Enabled,
                    @{Name="Account Expiry";Expression={if ($_.AccountExpires) {$_.AccountExpires} else {"Never"}}},
                    PasswordLastSet, PasswordExpires, PasswordNeverExpires, PasswordRequired,
                    UserMayChangePassword, LastLogon,
                    @{Name="SID";Expression={$_.SID}},
                    @{Name="Home Directory";Expression={$_.HomeDirectory}}

                # Check group membership
                Write-Host "`nGroups this account belongs to:" -ForegroundColor Yellow
                $groups = Get-LocalGroup | Where-Object {
                    (Get-LocalGroupMember -Group $_.Name -ErrorAction SilentlyContinue).Name -contains "$env:COMPUTERNAME\$targetUser"
                }

                if ($groups) {
                    $groups | Select-Object Name, Description | Format-Table -AutoSize
                } else {
                    Write-Host "This account does not belong to any groups" -ForegroundColor Gray
                }

            } else {
                Write-Host "Account '$targetUser' not found" -ForegroundColor Red
            }
        }
    }

    "4" {
        Write-Host "`n=== Delete Account ===" -ForegroundColor Red
        Write-Host "Warning: Deleting an account is irreversible!" -ForegroundColor Yellow
        Write-Host ""

        Write-Host "Current local accounts:" -ForegroundColor Yellow
        Get-LocalUser | Select-Object Name, Enabled, Description | Format-Table -AutoSize

        $username = Read-Host "`nEnter username to delete"

        # Check if account exists
        $userExists = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
        if (-not $userExists) {
            Write-Host "Error: Account '$username' does not exist!" -ForegroundColor Red
            pause
            exit
        }

        # Check if it's the currently logged-in user
        $currentUser = $env:USERNAME
        if ($username -eq $currentUser) {
            Write-Host "Error: Cannot delete currently logged-in user '$username'!" -ForegroundColor Red
            pause
            exit
        }

        # Check if it's a system-critical account
        $protectedAccounts = @("Administrator", "Guest", "DefaultAccount", "WDAGUtilityAccount")
        if ($protectedAccounts -contains $username) {
            Write-Host "Warning: '$username' is a system account, deletion not recommended!" -ForegroundColor Yellow
            $forceDelete = Read-Host "Are you sure you want to continue? (Type YES to confirm)"
            if ($forceDelete -ne "YES") {
                Write-Host "Delete operation cancelled" -ForegroundColor Green
                pause
                exit
            }
        }

        # Display account information to be deleted
        Write-Host "`nAccount to be deleted:" -ForegroundColor Yellow
        Get-LocalUser -Name $username | Select-Object Name, FullName, Description, Enabled, LastLogon | Format-List

        # Second confirmation
        Write-Host "Warning: This operation cannot be undone!" -ForegroundColor Red
        $confirm = Read-Host "Are you sure you want to delete account '$username'? (Type YES to confirm)"

        if ($confirm -eq "YES") {
            try {
                # Execute deletion
                Remove-LocalUser -Name $username -ErrorAction Stop
                Write-Host "`nSuccessfully deleted account: $username" -ForegroundColor Green

                # Display remaining accounts
                Write-Host "`nRemaining accounts:" -ForegroundColor Cyan
                Get-LocalUser | Select-Object Name, Enabled | Format-Table -AutoSize

            } catch {
                Write-Host "Error: Failed to delete account!" -ForegroundColor Red
                Write-Host $_.Exception.Message -ForegroundColor Red
            }
        } else {
            Write-Host "Delete operation cancelled" -ForegroundColor Green
        }
    }

    "5" {
        Write-Host "`n=== Manage Account Group Membership ===" -ForegroundColor Green
        Write-Host "`nCurrent local accounts:" -ForegroundColor Yellow
        Get-LocalUser | Select-Object Name, Enabled | Format-Table

        $username = Read-Host "Enter username to manage"

        $userExists = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
        if (-not $userExists) {
            Write-Host "Error: Account '$username' does not exist!" -ForegroundColor Red
            pause
            exit
        }

        $managedGroups = @(
            @{ Name = "Administrators";              Color = "Magenta"; Desc = "Full system admin privileges" },
            @{ Name = "Users";                       Color = "Green";   Desc = "Local GUI login" },
            @{ Name = "Remote Desktop Users";        Color = "Cyan";    Desc = "RDP remote desktop login" },
            @{ Name = "docker-users";                Color = "Blue";    Desc = "Use Docker Desktop without admin" },
            @{ Name = "Hyper-V Administrators";      Color = "Blue";    Desc = "Manage Hyper-V / WSL2 VMs" },
            @{ Name = "Performance Monitor Users";   Color = "Gray";    Desc = "Read performance counters" },
            @{ Name = "Event Log Readers";           Color = "Gray";    Desc = "Read Windows event logs" },
            @{ Name = "Network Configuration Operators"; Color = "Gray"; Desc = "Change network settings" }
        )

        Write-Host "`n=== Current Group Membership for '$username' ===" -ForegroundColor Cyan
        foreach ($g in $managedGroups) {
            $groupExists = Get-LocalGroup -Name $g.Name -ErrorAction SilentlyContinue
            if (-not $groupExists) { continue }

            $isMember = (Get-LocalGroupMember -Group $g.Name -ErrorAction SilentlyContinue).Name -contains "$env:COMPUTERNAME\$username"
            $status = if ($isMember) { "[IN]  " } else { "[OUT] " }
            $statusColor = if ($isMember) { "Green" } else { "Gray" }
            Write-Host "$status $($g.Name) - $($g.Desc)" -ForegroundColor $statusColor
        }

        Write-Host ""
        foreach ($g in $managedGroups) {
            $groupExists = Get-LocalGroup -Name $g.Name -ErrorAction SilentlyContinue
            if (-not $groupExists) { continue }

            $isMember = (Get-LocalGroupMember -Group $g.Name -ErrorAction SilentlyContinue).Name -contains "$env:COMPUTERNAME\$username"
            $action = if ($isMember) { "Remove from" } else { "Add to" }
            $answer = Read-Host "$action '$($g.Name)'? (Y/N, Enter to skip)"

            if ($answer -eq "Y" -or $answer -eq "y") {
                try {
                    if ($isMember) {
                        Remove-LocalGroupMember -Group $g.Name -Member $username -ErrorAction Stop
                        Write-Host "Removed from $($g.Name)" -ForegroundColor Yellow
                    } else {
                        Add-LocalGroupMember -Group $g.Name -Member $username -ErrorAction Stop
                        Write-Host "Added to $($g.Name)" -ForegroundColor $g.Color
                    }
                } catch {
                    Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }

        Write-Host "`n=== Updated Group Membership for '$username' ===" -ForegroundColor Cyan
        $finalGroups = Get-LocalGroup | Where-Object {
            (Get-LocalGroupMember -Group $_.Name -ErrorAction SilentlyContinue).Name -contains "$env:COMPUTERNAME\$username"
        }
        if ($finalGroups) {
            $finalGroups | Select-Object Name, Description | Format-Table -AutoSize
        } else {
            Write-Host "This account does not belong to any groups" -ForegroundColor Gray
        }
    }

    "6" {
        Write-Host "Goodbye!" -ForegroundColor Yellow
        exit
    }

    default {
        Write-Host "Invalid option!" -ForegroundColor Red
    }
}

Write-Host "`nOperation completed!" -ForegroundColor Green
pause
