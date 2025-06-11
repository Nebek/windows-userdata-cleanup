# Windows Automatic User Data Cleanup Script

PowerShell script for automatically cleaning user data (Downloads, Recycle Bin, browser history) on Windows login screen. Fully compatible with Windows 10/11 and BitLocker.

## Features

The script automatically cleans:
- **Downloads folders** for all users
- **Recycle Bin** for all users (3 cleaning methods)
- **Browser history** (Chrome and Edge)
- **System temporary files**

The script runs:
- At system startup (before user login)
- On user logoff
- On screen lock (Win+L)
- On screen unlock

## Files

- `CleanupScript.ps1` - Main cleanup script
- `Setup-CleanupTask.ps1` - Automated Task Scheduler configuration
- `README.md` - This instruction file

## Installation

1. Download all 3 files to the same folder (e.g., `C:\Scripts\`)

2. **Run PowerShell as Administrator**

3. Execute the setup command:
   ```powershell
   cd "C:\Scripts"
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   .\Setup-CleanupTask.ps1
   ```

4. Choose mode:
   - **Mode 1** (with logging) - saves details to `log.txt`
   - **Mode 2** (without logging) - faster, no log files

5. The script automatically:
   - Creates 4 scheduled tasks in Task Scheduler
   - Configures audit policies for lock/unlock events
   - Sets SYSTEM privileges for all tasks

## Created Scheduled Tasks

1. **SystemCleanup-LoginScreen** - runs at system startup
2. **SystemCleanup-Logoff** - runs on user logoff
3. **SystemCleanup-Lock** - runs on screen lock (Win+L)
4. **SystemCleanup-Unlock** - runs on screen unlock

## Verification

### Checking Task Scheduler
```
Win+R → taskschd.msc → Task Scheduler Library
Look for tasks starting with "SystemCleanup"
```

### Checking Event Logs
```
Win+R → eventvwr.msc → Windows Logs → Application
Source: "CleanupScript"
```

### Checking Security Audit
```
Win+R → eventvwr.msc → Windows Logs → Security
Look for EventID 4800 (lock) and 4801 (unlock)
```

## Troubleshooting

### Lock/Unlock Events Not Working

If lock/unlock tasks don't trigger:

1. **Check audit policy:**
   ```powershell
   auditpol /get /subcategory:"{0cce9228-69ae-11d9-bed3-505054503030}"
   ```

2. **Enable manually if needed:**
   ```
   gpedit.msc → Computer Configuration → Windows Settings 
   → Security Settings → Advanced Audit Policy Configuration 
   → Audit Policies → Logon/Logoff 
   → Audit Other Logon/Logoff Events → Enable Success and Failure
   ```

3. **Test the lock:**
   - Press Win+L to lock
   - Enter password to unlock
   - Check Security log for EventID 4800/4801

### Manual Task Removal

To remove all tasks:
```powershell
Get-ScheduledTask | Where-Object {$_.TaskName -like "SystemCleanup*"} | Unregister-ScheduledTask -Confirm:$false
```

### Manual Audit Disable

To disable audit:
```powershell
auditpol /set /subcategory:"{0cce9228-69ae-11d9-bed3-505054503030}" /success:disable /failure:disable
```

## Technical Details

### Security
- All tasks run with **SYSTEM** privileges
- No user interaction required
- Completely invisible operation (hidden windows)

### Compatibility
- ✅ Windows 10
- ✅ Windows 11  
- ✅ BitLocker encrypted drives
- ✅ Domain and local accounts
- ✅ Multiple user profiles

### Performance
- Uses `-Force` and `-ErrorAction SilentlyContinue`
- Background execution without UI
- Optimized for speed and reliability

## Advanced Configuration

### Customizing Cleaned Locations

Edit `CleanupScript.ps1` to add/remove cleaning targets:

```powershell
# Add custom paths
$CustomPaths = @(
    "C:\CustomFolder",
    "$env:USERPROFILE\CustomData"
)
```

### Changing Trigger Events

Modify `Setup-CleanupTask.ps1` to add different triggers:

```powershell
# Example: Add shutdown trigger
$TriggerShutdown = New-ScheduledTaskTrigger -AtStartup
# Change to your preferred event
```

## Logs and Monitoring

### With Logging Mode
- Detailed logs saved to `log.txt`
- Timestamped entries
- File count statistics
- Error details

### Event Viewer Integration
- Application log entries
- EventID 1001 (success)
- EventID 1002 (errors)

## Uninstallation

Run the removal script:
```powershell
# Remove all tasks
Get-ScheduledTask | Where-Object {$_.TaskName -like "SystemCleanup*"} | Unregister-ScheduledTask -Confirm:$false

# Disable audit (optional)
auditpol /set /subcategory:"{0cce9228-69ae-11d9-bed3-505054503030}" /success:disable /failure:disable

# Remove Event Log source (as Administrator)
Remove-EventLog -Source "CleanupScript" -ErrorAction SilentlyContinue
```

## License

Free to use and modify. No warranty provided.

## Support

For issues or questions, check:
1. Task Scheduler for task status
2. Event Viewer for execution logs
3. Security audit logs for lock/unlock events

---

**⚠️ Important:** This script deletes files permanently. Test in a safe environment before production use. 