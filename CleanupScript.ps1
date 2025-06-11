
$ConfigPath = Join-Path $PSScriptRoot "cleanup-config.txt"
$EnableLogging = $true 

if (Test-Path $ConfigPath) {
    try {
        $ConfigContent = Get-Content -Path $ConfigPath -ErrorAction Stop
        if ($ConfigContent -match "EnableLogging=(.+)") {
            $EnableLogging = [System.Convert]::ToBoolean($matches[1])
        }
    } catch {

    }
}


$LogPath = Join-Path $PSScriptRoot "log.txt"

function Write-Log {
    param([string]$Message)
    if ($EnableLogging) {
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $LogEntry = "[$Timestamp] $Message"
        Add-Content -Path $LogPath -Value $LogEntry -ErrorAction SilentlyContinue
    }
}


if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "ERROR: Script requires administrator privileges!"
    exit 1
}

Write-Log "Starting user data cleanup..."


function Stop-BrowserProcesses {
    Write-Log "Closing browsers..."
    

    $ChromeProcesses = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
    if ($ChromeProcesses) {
        Write-Log "  Found $($ChromeProcesses.Count) Chrome processes - closing..."
        $ChromeProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    

    $EdgeProcesses = Get-Process -Name "msedge" -ErrorAction SilentlyContinue
    if ($EdgeProcesses) {
        Write-Log "  Found $($EdgeProcesses.Count) Edge processes - closing..."
        $EdgeProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    

    Start-Sleep -Seconds 2
    Write-Log "Browsers closed"
}


function Clear-UserData {
    param([string]$UserPath, [string]$UserName)
    
    Write-Log "Clearing data for user: $UserName"
    

    $DownloadsPath = Join-Path $UserPath "Downloads"
    if (Test-Path $DownloadsPath) {
        Write-Log "  Clearing Downloads folder..."
        $DownloadFiles = Get-ChildItem -Path $DownloadsPath -Recurse -Force -ErrorAction SilentlyContinue
        if ($DownloadFiles) {
            Write-Log "    Found $($DownloadFiles.Count) files to delete"
            $DownloadFiles | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            Write-Log "    Downloads folder cleared"
        } else {
            Write-Log "    Downloads folder is empty"
        }
    } else {
        Write-Log "  Downloads folder does not exist"
    }
    

    $RecycleBinPath = Join-Path $UserPath "AppData\Local\Microsoft\Windows\Explorer"
    if (Test-Path $RecycleBinPath) {
        Write-Log "  Clearing recycle bin cache..."
        try {
            $RecycleBinFiles = Get-ChildItem -Path $RecycleBinPath -Recurse -Force -ErrorAction Stop | 
                Where-Object { $_.Name -like "*RecycleBin*" }
            if ($RecycleBinFiles) {
                Write-Log "    Found $($RecycleBinFiles.Count) recycle bin cache files"
                $RecycleBinFiles | Remove-Item -Force -Recurse -ErrorAction Stop
                Write-Log "    Recycle bin cache cleared"
            } else {
                Write-Log "    No recycle bin cache files found"
            }
        } catch {
            Write-Log "    ERROR clearing recycle bin cache: $($_.Exception.Message)"
        }
    } else {
        Write-Log "  Recycle bin cache folder does not exist"
    }
    

    Write-Log "  Clearing system recycle bin..."
    $RecycleBin = '$Recycle.Bin'
    $Drives = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    $TotalRecycleFiles = 0
    
    foreach ($Drive in $Drives) {
        $RecyclePath = Join-Path $Drive.DeviceID $RecycleBin
        Write-Log "    Checking drive $($Drive.DeviceID) - path: $RecyclePath"
        
        if (Test-Path $RecyclePath) {
            try {

                $UserSID = (New-Object System.Security.Principal.NTAccount($UserName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
                Write-Log "      User SID $UserName : $UserSID"
                

                $UserRecyclePath = Get-ChildItem -Path $RecyclePath -Force -ErrorAction Stop | 
                    Where-Object { $_.Name -eq $UserSID -and $_.PSIsContainer }
                
                if ($UserRecyclePath) {
                    Write-Log "      Found user recycle bin folder: $($UserRecyclePath.FullName)"
                    $RecycleFiles = Get-ChildItem -Path $UserRecyclePath.FullName -Recurse -Force -ErrorAction Stop
                    if ($RecycleFiles) {
                        Write-Log "      Found $($RecycleFiles.Count) files in recycle bin"
                        $RecycleFiles | Remove-Item -Force -Recurse -ErrorAction Stop
                        $TotalRecycleFiles += $RecycleFiles.Count
                        Write-Log "      Recycle bin on drive $($Drive.DeviceID) cleared"
                    } else {
                        Write-Log "      Recycle bin on drive $($Drive.DeviceID) is empty"
                    }
                } else {
                    Write-Log "      No user recycle bin folder found on drive $($Drive.DeviceID)"
                }
            } catch {
                Write-Log "      ERROR clearing recycle bin on drive $($Drive.DeviceID): $($_.Exception.Message)"
            }
        } else {
            Write-Log "    $RecycleBin folder does not exist on drive $($Drive.DeviceID)"
        }
    }
    

    Write-Log "  Trying to clear recycle bin via COM..."
    try {

        if (Get-Command Clear-RecycleBin -ErrorAction SilentlyContinue) {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-Log "    Recycle bin cleared via Clear-RecycleBin"
        } else {
            Write-Log "    Clear-RecycleBin not available"
        }
    } catch {
        Write-Log "    ERROR Clear-RecycleBin: $($_.Exception.Message)"
    }
    
    Write-Log "  Recycle bin summary: removed $TotalRecycleFiles files"
    

    $ChromeHistoryPath = Join-Path $UserPath "AppData\Local\Google\Chrome\User Data\Default"
    if (Test-Path $ChromeHistoryPath) {
        Write-Log "  Clearing Chrome history..."
        $ChromeHistoryFiles = Get-ChildItem -Path $ChromeHistoryPath -Filter "History*" -Force -ErrorAction SilentlyContinue
        if ($ChromeHistoryFiles) {
            Write-Log "    Found $($ChromeHistoryFiles.Count) Chrome history files"
            $ChromeHistoryFiles | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        

        $ChromeFiles = @("Cookies", "Web Data", "Login Data", "Top Sites", "Visited Links", "Preferences")
        $RemovedCount = 0
        foreach ($File in $ChromeFiles) {
            $FilePath = Join-Path $ChromeHistoryPath $File
            if (Test-Path $FilePath) {
                Remove-Item -Path $FilePath -Force -ErrorAction SilentlyContinue
                $RemovedCount++
            }
        }
        Write-Log "    Removed $RemovedCount additional Chrome files"
    } else {
        Write-Log "  Chrome not installed or no profile found"
    }
    

    $EdgeHistoryPath = Join-Path $UserPath "AppData\Local\Microsoft\Edge\User Data\Default"
    if (Test-Path $EdgeHistoryPath) {
        Write-Log "  Clearing Edge history..."
        $EdgeHistoryFiles = Get-ChildItem -Path $EdgeHistoryPath -Filter "History*" -Force -ErrorAction SilentlyContinue
        if ($EdgeHistoryFiles) {
            Write-Log "    Found $($EdgeHistoryFiles.Count) Edge history files"
            $EdgeHistoryFiles | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        

        $EdgeFiles = @("Cookies", "Web Data", "Login Data", "Top Sites", "Visited Links", "Preferences")
        $RemovedCount = 0
        foreach ($File in $EdgeFiles) {
            $FilePath = Join-Path $EdgeHistoryPath $File
            if (Test-Path $FilePath) {
                Remove-Item -Path $FilePath -Force -ErrorAction SilentlyContinue
                $RemovedCount++
            }
        }
        Write-Log "    Removed $RemovedCount additional Edge files"
    } else {
        Write-Log "  Edge not installed or no profile found"
    }
    
    Write-Log "User data cleanup for $UserName completed"
}


try {

    Stop-BrowserProcesses
    

    $LocalUsers = Get-WmiObject -Class Win32_UserProfile | 
        Where-Object { 
            $_.Special -eq $false -and 
            $_.LocalPath -ne $null -and
            $_.LocalPath -notlike "*service*" -and
            $_.LocalPath -notlike "*systemprofile*" -and
            $_.LocalPath -notlike "*NetworkService*" -and
            $_.LocalPath -notlike "*LocalService*"
        }
    
    Write-Log "Found $($LocalUsers.Count) users to clean"
    

    foreach ($User in $LocalUsers) {
        $UserPath = $User.LocalPath
        $UserName = Split-Path $UserPath -Leaf
        
        if (Test-Path $UserPath) {
            Clear-UserData -UserPath $UserPath -UserName $UserName
        } else {
            Write-Log "User path does not exist: $UserPath"
        }
    }
    
    Write-Log "User data cleanup completed successfully!"
    

    Write-Log "Clearing system temporary files..."
    

    $TempPaths = @(
        $env:TEMP,
        "C:\Windows\Temp",
        "C:\Temp"
    )
    
    foreach ($TempPath in $TempPaths) {
        if (Test-Path $TempPath) {
            Write-Log "  Clearing: $TempPath"
            $TempFiles = Get-ChildItem -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
            if ($TempFiles) {
                Write-Log "    Found $($TempFiles.Count) temporary files"
                $TempFiles | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                Write-Log "    Temporary files removed"
            } else {
                Write-Log "    Folder is empty"
            }
        } else {
            Write-Log "  Folder does not exist: $TempPath"
        }
    }
    

    if ($EnableLogging) {
        Write-Log "Logging to Event Viewer..."
        Write-EventLog -LogName Application -Source "CleanupScript" -EventId 1001 -EntryType Information -Message "User data cleanup completed successfully" -ErrorAction SilentlyContinue
    }

} catch {
    Write-Log "ERROR during cleanup: $($_.Exception.Message)"
    Write-Log "Error details: $($_.Exception.InnerException)"
    if ($EnableLogging) {
        Write-EventLog -LogName Application -Source "CleanupScript" -EventId 1002 -EntryType Error -Message "Error during cleanup: $($_.Exception.Message)" -ErrorAction SilentlyContinue
    }
}

Write-Log "Script completed - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "----------------------------------------" 