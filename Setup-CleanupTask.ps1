if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Script requires administrator privileges!" -ForegroundColor Red
    Write-Host "Run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

Write-Host "Configuring cleanup task in Task Scheduler..." -ForegroundColor Green

Write-Host "`nSelect operation mode:" -ForegroundColor Cyan
Write-Host "1. With logs (creating log.txt in script folder)" -ForegroundColor White
Write-Host "2. Without logs (silent mode - no log files)" -ForegroundColor White

do {
    $ModeChoice = Read-Host "`nSelect mode (1 or 2)"
} while ($ModeChoice -notmatch "^[12]$")

$EnableLogging = ($ModeChoice -eq "1")

if ($EnableLogging) {
    Write-Host "Selected mode: With logs" -ForegroundColor Green
} else {
    Write-Host "Selected mode: Without logs (silent)" -ForegroundColor Green
}

$ConfigPath = Join-Path $PSScriptRoot "cleanup-config.txt"
$ConfigContent = "EnableLogging=$EnableLogging"
Set-Content -Path $ConfigPath -Value $ConfigContent -Force
Write-Host "Configuration saved to: $ConfigPath" -ForegroundColor Gray

$ScriptPath = Join-Path $PSScriptRoot "CleanupScript.ps1"

if (-not (Test-Path $ScriptPath)) {
    Write-Host "ERROR: CleanupScript.ps1 file not found in directory: $PSScriptRoot" -ForegroundColor Red
    Write-Host "Make sure both scripts are in the same folder." -ForegroundColor Yellow
    exit 1
}

try {
    $TaskName = "SystemCleanup-LoginScreen"
    $ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($ExistingTask) {
        Write-Host "Removing existing task..." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -WindowStyle Hidden -NoLogo -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`""

    Write-Host "Creating triggers..." -ForegroundColor Cyan
    
    $TriggerStartup = New-ScheduledTaskTrigger -AtStartup
    
    $TriggerLogin = New-ScheduledTaskTrigger -AtLogOn
    
    
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false -DontStopOnIdleEnd -Hidden

    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    $MainTriggers = @($TriggerStartup, $TriggerLogin)
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $MainTriggers -Settings $Settings -Principal $Principal -Description "Automatic user data cleanup at system startup and user login"

    Write-Host "Task '$TaskName' created successfully!" -ForegroundColor Green

    Write-Host "Creating additional tasks..." -ForegroundColor Cyan

    $TaskNameLogoff = "SystemCleanup-Logoff"
    $ExistingTaskLogoff = Get-ScheduledTask -TaskName $TaskNameLogoff -ErrorAction SilentlyContinue
    if ($ExistingTaskLogoff) {
        Unregister-ScheduledTask -TaskName $TaskNameLogoff -Confirm:$false
    }

    $TriggerLogoffXML = @"
<QueryList>
  <Query Id="0" Path="System">
    <Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Winlogon'] and EventID=7002]]</Select>
  </Query>
</QueryList>
"@

    $CIMTriggerClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler:MSFT_TaskEventTrigger
    $TriggerLogoffEvent = New-CimInstance -CimClass $CIMTriggerClass -ClientOnly
    $TriggerLogoffEvent.Subscription = $TriggerLogoffXML
    $TriggerLogoffEvent.Enabled = $true

    Register-ScheduledTask -TaskName $TaskNameLogoff -Action $Action -Trigger $TriggerLogoffEvent -Settings $Settings -Principal $Principal -Description "Data cleanup at user logoff"

    $TaskNameLock = "SystemCleanup-Lock"
    $ExistingTaskLock = Get-ScheduledTask -TaskName $TaskNameLock -ErrorAction SilentlyContinue
    if ($ExistingTaskLock) {
        Unregister-ScheduledTask -TaskName $TaskNameLock -Confirm:$false
    }

    $TriggerLockXML = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">*[System[Provider[@Name='Microsoft-Windows-Security-Auditing'] and EventID=4800]]</Select>
  </Query>
</QueryList>
"@

    $TriggerLockEvent = New-CimInstance -CimClass $CIMTriggerClass -ClientOnly
    $TriggerLockEvent.Subscription = $TriggerLockXML
    $TriggerLockEvent.Enabled = $true

    Register-ScheduledTask -TaskName $TaskNameLock -Action $Action -Trigger $TriggerLockEvent -Settings $Settings -Principal $Principal -Description "Data cleanup at system lock"

    $TaskNameUnlock = "SystemCleanup-Unlock"
    $ExistingTaskUnlock = Get-ScheduledTask -TaskName $TaskNameUnlock -ErrorAction SilentlyContinue
    if ($ExistingTaskUnlock) {
        Unregister-ScheduledTask -TaskName $TaskNameUnlock -Confirm:$false
    }

    $TriggerUnlockXML = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">*[System[Provider[@Name='Microsoft-Windows-Security-Auditing'] and EventID=4801]]</Select>
  </Query>
</QueryList>
"@

    $TriggerUnlockEvent = New-CimInstance -CimClass $CIMTriggerClass -ClientOnly
    $TriggerUnlockEvent.Subscription = $TriggerUnlockXML
    $TriggerUnlockEvent.Enabled = $true

    Register-ScheduledTask -TaskName $TaskNameUnlock -Action $Action -Trigger $TriggerUnlockEvent -Settings $Settings -Principal $Principal -Description "Data cleanup at system unlock"

    Write-Host "`nSuccessfully created the following tasks:" -ForegroundColor Green
    Write-Host "1. $TaskName - runs at system startup and user login" -ForegroundColor White
    Write-Host "2. $TaskNameLogoff - runs at user logoff" -ForegroundColor White  
    Write-Host "3. $TaskNameLock - runs at system lock (Win+L)" -ForegroundColor White
    Write-Host "4. $TaskNameUnlock - runs at system unlock" -ForegroundColor White

    Write-Host "`nYou can check the tasks in Task Scheduler:" -ForegroundColor Yellow
    Write-Host "taskschd.msc -> Task Scheduler Library -> Find tasks starting with 'SystemCleanup'" -ForegroundColor White
    
    if (-not [System.Diagnostics.EventLog]::SourceExists("CleanupScript")) {
        Write-Host "`nCreating event source in Event Viewer..." -ForegroundColor Cyan
        New-EventLog -LogName Application -Source "CleanupScript"
        Write-Host "Event source 'CleanupScript' has been created." -ForegroundColor Green
    }

    Write-Host "`nEnabling workstation lock audit..." -ForegroundColor Cyan
    
    $SubcategoryNames = @(
        "{0cce9228-69ae-11d9-bed3-505054503030}"
    )
    
    $AuditEnabled = $false
    foreach ($SubcategoryName in $SubcategoryNames) {
        try {
            Write-Host "Trying with name: '$SubcategoryName'" -ForegroundColor Gray
            $AuditResult = & auditpol /set /subcategory:"$SubcategoryName" /success:enable /failure:enable 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Audit enabled successfully with name: '$SubcategoryName'" -ForegroundColor Green
                Write-Host "Result: $AuditResult" -ForegroundColor Gray
                
                $AuditCheck = & auditpol /get /subcategory:"$SubcategoryName" 2>&1
                Write-Host "Audit status: $AuditCheck" -ForegroundColor White
                $AuditEnabled = $true
                break
            } else {
                Write-Host "❌ Error with name '$SubcategoryName': $AuditResult" -ForegroundColor Red
            }
        } catch {
            Write-Host "❌ Exception with name '$SubcategoryName': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    if (-not $AuditEnabled) {
        Write-Host "`n⚠️  WARNING: Automatic audit enabling failed!" -ForegroundColor Yellow
        Write-Host "Enable manually through Group Policy or:" -ForegroundColor Yellow
        Write-Host "1. gpedit.msc" -ForegroundColor White
        Write-Host "2. Computer Configuration > Windows Settings > Security Settings > Advanced Audit Policy Configuration" -ForegroundColor White
        Write-Host "3. Audit Policies > Logon/Logoff > Audit Other Logon/Logoff Events" -ForegroundColor White
        Write-Host "4. Check 'Success' and 'Failure'" -ForegroundColor White
        
        Write-Host "`nOr try manually:" -ForegroundColor Yellow
        Write-Host "auditpol /list /subcategory:* | findstr Logon" -ForegroundColor Gray
        Write-Host "to find the correct subcategory name" -ForegroundColor Gray
    }

    Write-Host "`nConfiguration completed!" -ForegroundColor Green
    Write-Host "Tasks will run automatically according to settings." -ForegroundColor Green
    
    Write-Host "`nIMPORTANT: For Lock/Unlock tasks to work properly:" -ForegroundColor Yellow
    Write-Host "1. Audit 'Other Logon/Logoff Events' must be enabled (above)" -ForegroundColor White
    Write-Host "2. Test lock: Win+L, then unlock" -ForegroundColor White
    Write-Host "3. Check logs in: log.txt and Event Viewer (Security log, EventID 4800/4801)" -ForegroundColor White

} catch {
    Write-Host "ERROR during task creation: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.InnerException)" -ForegroundColor Red
}

Write-Host "`nPress any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") 