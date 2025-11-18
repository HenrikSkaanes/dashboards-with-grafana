# ============================================================================
# VALHEIM DEDICATED SERVER - COMPLETE SETUP SCRIPT
# For Windows Server on Azure VM (D4as_v6)
# PowerShell Admin CLI Only - No GUI
# ============================================================================
# This script will:
# 1. Remove all existing Valheim and SteamCMD installations
# 2. Download and install SteamCMD fresh
# 3. Install Valheim Dedicated Server (AppID 896660)
# 4. Create startup script
# 5. Set up scheduled task for auto-start on boot
# ============================================================================

# CRITICAL: Prevent window from closing on errors
$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "Valheim Server Setup"

# Function to pause and wait for user input before exiting
function Pause-OnError {
    param([string]$message)
    Write-Host "`n$message" -ForegroundColor Red
    Write-Host "`nPress any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Function to verify we're in the right place
function Test-WorkingEnvironment {
    Write-Host "Verifying environment..." -ForegroundColor Gray
    
    # Ensure we're on C: drive
    $currentDrive = (Get-Location).Drive.Name
    if ($currentDrive -ne "C") {
        Set-Location C:\
        Write-Host "Changed to C:\ drive" -ForegroundColor Gray
    }
    
    # Check disk space (need at least 5GB free)
    $drive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
    if ($drive) {
        $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
        Write-Host "Available disk space on C:\: $freeSpaceGB GB" -ForegroundColor Gray
        
        if ($freeSpaceGB -lt 5) {
            Pause-OnError "ERROR: Insufficient disk space! Need at least 5GB free, only $freeSpaceGB GB available."
        }
    } else {
        Write-Host "Could not check disk space, but continuing..." -ForegroundColor Yellow
    }
    
    Write-Host "Environment check passed!" -ForegroundColor Green
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "VALHEIM SERVER SETUP - STARTING" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Verify environment first
Test-WorkingEnvironment

# ============================================================================
# STEP 1: CLEAN UP EXISTING INSTALLATIONS
# ============================================================================
Write-Host "`n[STEP 1/6] Cleaning up existing installations..." -ForegroundColor Yellow

# Stop any running Valheim processes
Write-Host "Stopping any running Valheim server processes..." -ForegroundColor Gray
Get-Process -Name "valheim_server" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# Remove existing directories
$pathsToRemove = @(
    "C:\Valheim",
    "C:\SteamCMD",
    "C:\steamcmd"
)

foreach ($path in $pathsToRemove) {
    if (Test-Path $path) {
        Write-Host "Removing: $path" -ForegroundColor Gray
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Remove scheduled task if it exists
$taskName = "ValheimServerAutoStart"
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Write-Host "Removing existing scheduled task: $taskName" -ForegroundColor Gray
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

Write-Host "Cleanup complete!" -ForegroundColor Green

# ============================================================================
# STEP 2: CREATE DIRECTORY STRUCTURE
# ============================================================================
Write-Host "`n[STEP 2/6] Creating fresh directory structure..." -ForegroundColor Yellow

$directories = @(
    "C:\Valheim",
    "C:\Valheim\server",
    "C:\Valheim\steamcmd",
    "C:\Valheim\server\worlds",
    "C:\Valheim\logs"
)

foreach ($dir in $directories) {
    New-Item -Path $dir -ItemType Directory -Force | Out-Null
    Write-Host "Created: $dir" -ForegroundColor Gray
}

Write-Host "Directory structure created!" -ForegroundColor Green

# ============================================================================
# STEP 3: DOWNLOAD AND INSTALL STEAMCMD
# ============================================================================
Write-Host "`n[STEP 3/6] Downloading and installing SteamCMD..." -ForegroundColor Yellow

$steamCmdUrl = "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip"
$steamCmdZip = "C:\Valheim\steamcmd.zip"
$steamCmdPath = "C:\Valheim\steamcmd"

# Download SteamCMD
Write-Host "Downloading SteamCMD from $steamCmdUrl..." -ForegroundColor Gray
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
    Invoke-WebRequest -Uri $steamCmdUrl -OutFile $steamCmdZip -UseBasicParsing -TimeoutSec 300
} catch {
    Pause-OnError "ERROR: Failed to download SteamCMD! Check internet connection. Error: $($_.Exception.Message)"
}

if (!(Test-Path $steamCmdZip)) {
    Pause-OnError "ERROR: SteamCMD zip file not found after download!"
}

$downloadSize = [math]::Round((Get-Item $steamCmdZip).Length / 1MB, 2)
Write-Host "Download complete! Size: $downloadSize MB" -ForegroundColor Gray

if ($downloadSize -lt 1) {
    Pause-OnError "ERROR: Downloaded file seems too small ($downloadSize MB). Download may have failed."
}

# Extract SteamCMD
Write-Host "Extracting SteamCMD..." -ForegroundColor Gray
try {
    Expand-Archive -Path $steamCmdZip -DestinationPath $steamCmdPath -Force
    Remove-Item $steamCmdZip -Force
} catch {
    Pause-OnError "ERROR: Failed to extract SteamCMD! Error: $($_.Exception.Message)"
}

if (!(Test-Path "$steamCmdPath\steamcmd.exe")) {
    Pause-OnError "ERROR: steamcmd.exe not found at $steamCmdPath\steamcmd.exe after extraction!"
}

Write-Host "SteamCMD installed successfully!" -ForegroundColor Green

# ============================================================================
# STEP 4: INSTALL VALHEIM DEDICATED SERVER
# ============================================================================
Write-Host "`n[STEP 4/6] Installing Valheim Dedicated Server..." -ForegroundColor Yellow
Write-Host "This may take several minutes (downloading ~1-2 GB)..." -ForegroundColor Gray
Write-Host "The window may appear frozen - this is normal. Please wait..." -ForegroundColor Gray

$serverPath = "C:\Valheim\server"

# Ensure we're in the correct directory
Set-Location "C:\Valheim\steamcmd"
Write-Host "Working directory: $(Get-Location)" -ForegroundColor Gray

# Run SteamCMD to install Valheim server
# Using +login anonymous, +force_install_dir, +app_update 896660 validate, +quit
Write-Host "Running SteamCMD installation command..." -ForegroundColor Gray

# Try up to 3 times (SteamCMD can be flaky)
$maxAttempts = 3
$attempt = 1
$success = $false

while ($attempt -le $maxAttempts -and -not $success) {
    Write-Host "`nAttempt $attempt of $maxAttempts..." -ForegroundColor Cyan
    
    # Run SteamCMD with proper escaping and arguments
    $steamCmdExe = Join-Path $steamCmdPath "steamcmd.exe"
    
    # Create a batch file to run steamcmd (more reliable than Start-Process with complex args)
    $batchFile = "C:\Valheim\install-server.bat"
    $batchContent = "@echo off`r`n"
    $batchContent += "cd /d `"$steamCmdPath`"`r`n"
    $batchContent += "`"$steamCmdExe`" +force_install_dir `"$serverPath`" +login anonymous +app_update 896660 validate +quit`r`n"
    $batchContent += "exit /b %ERRORLEVEL%"
    Set-Content -Path $batchFile -Value $batchContent -Force
    
    # Run the batch file
    $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$batchFile`"" -Wait -NoNewWindow -PassThru
    
    Write-Host "SteamCMD process exited with code: $($process.ExitCode)" -ForegroundColor Gray
    
    # Check if server executable exists
    $serverExe = "$serverPath\valheim_server.exe"
    if (Test-Path $serverExe) {
        $success = $true
        Write-Host "Server executable found!" -ForegroundColor Green
    } else {
        Write-Host "Server executable not found. Checking for partial installation..." -ForegroundColor Yellow
        
        # Check if any files were downloaded
        $serverFiles = Get-ChildItem -Path $serverPath -Recurse -ErrorAction SilentlyContinue
        if ($serverFiles.Count -gt 5) {
            Write-Host "Partial installation detected. Retrying..." -ForegroundColor Yellow
        } else {
            Write-Host "No files downloaded. This might be a network or Steam server issue." -ForegroundColor Yellow
        }
        
        if ($attempt -lt $maxAttempts) {
            Write-Host "Waiting 10 seconds before retry..." -ForegroundColor Yellow
            Start-Sleep -Seconds 10
        }
    }
    
    $attempt++
}

# Verify installation
if (-not $success) {
    Write-Host "`nInstallation failed after $maxAttempts attempts." -ForegroundColor Red
    Write-Host "`nPossible causes:" -ForegroundColor Yellow
    Write-Host "1. Steam servers are down or rate-limiting" -ForegroundColor White
    Write-Host "2. Internet connection interrupted" -ForegroundColor White
    Write-Host "3. Disk space ran out during download" -ForegroundColor White
    Write-Host "4. Windows Firewall blocking steamcmd.exe" -ForegroundColor White
    Write-Host "`nTroubleshooting steps:" -ForegroundColor Yellow
    Write-Host "1. Check internet: Test-NetConnection google.com" -ForegroundColor White
    Write-Host "2. Check disk space: Get-PSDrive C" -ForegroundColor White
    Write-Host "3. Try manual install: cd C:\Valheim\steamcmd; .\steamcmd.exe +login anonymous +app_update 896660 validate +quit" -ForegroundColor White
    Write-Host "4. Wait 30 minutes and run this script again (Steam may be rate-limiting)" -ForegroundColor White
    Pause-OnError "Installation failed. See troubleshooting steps above."
}

Write-Host "Valheim Dedicated Server installed successfully!" -ForegroundColor Green
Write-Host "Server executable found at: $serverExe" -ForegroundColor Gray

# Verify critical files exist
$criticalFiles = @(
    "$serverPath\valheim_server.exe",
    "$serverPath\UnityPlayer.dll",
    "$serverPath\valheim_server_Data"
)

$missingFiles = @()
foreach ($file in $criticalFiles) {
    if (!(Test-Path $file)) {
        $missingFiles += $file
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Host "`nWARNING: Some critical files are missing:" -ForegroundColor Yellow
    $missingFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host "Server may not start correctly. Consider re-running the script." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
} else {
    Write-Host "All critical server files verified!" -ForegroundColor Green
}

# ============================================================================
# STEP 5: CREATE SERVER STARTUP SCRIPT
# ============================================================================
Write-Host "`n[STEP 5/6] Creating server startup script..." -ForegroundColor Yellow

$startScriptPath = "C:\Valheim\start-valheim-server.ps1"

# Create the startup script content
$startScriptContent = @'
# Valheim Dedicated Server Startup Script
# Auto-generated

$serverPath = "C:\Valheim\server"
$serverExe = "$serverPath\valheim_server.exe"
$worldName = "MyWorld"
$serverName = "My Valheim Server"
$port = 2456
$password = "secret123"
$public = 1  # Set to 0 for private server (not listed in server browser)
$saveDir = "C:\Valheim\server\worlds"
$logFile = "C:\Valheim\logs\valheim-server.log"

# Ensure log directory exists
if (!(Test-Path "C:\Valheim\logs")) {
    New-Item -Path "C:\Valheim\logs" -ItemType Directory -Force | Out-Null
}

Write-Host "Starting Valheim Dedicated Server..." -ForegroundColor Cyan
Write-Host "Server Name: $serverName" -ForegroundColor Gray
Write-Host "World Name: $worldName" -ForegroundColor Gray
Write-Host "Port: $port" -ForegroundColor Gray
Write-Host "Public: $public" -ForegroundColor Gray
Write-Host "Log File: $logFile" -ForegroundColor Gray

# Change to server directory
Set-Location $serverPath

# Build arguments
$arguments = @(
    "-nographics",
    "-batchmode",
    "-name `"$serverName`"",
    "-port $port",
    "-world `"$worldName`"",
    "-password `"$password`"",
    "-public $public",
    "-savedir `"$saveDir`""
)

# Start the server
$argumentString = $arguments -join " "
Write-Host "`nExecuting: $serverExe $argumentString" -ForegroundColor Gray
Write-Host "`nServer is starting... Press Ctrl+C to stop." -ForegroundColor Yellow
Write-Host "Check the log file for server status: $logFile`n" -ForegroundColor Yellow

# Start server and redirect output to log file
Start-Process -FilePath $serverExe -ArgumentList $argumentString -NoNewWindow -RedirectStandardOutput $logFile -Wait

Write-Host "`nServer has stopped." -ForegroundColor Red
'@

# Write the startup script
try {
    Set-Content -Path $startScriptPath -Value $startScriptContent -Force
} catch {
    Pause-OnError "ERROR: Failed to create startup script at $startScriptPath. Error: $($_.Exception.Message)"
}

if (!(Test-Path $startScriptPath)) {
    Pause-OnError "ERROR: Startup script was not created at $startScriptPath"
}

Write-Host "Startup script created at: $startScriptPath" -ForegroundColor Green

# Test script syntax
try {
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $startScriptPath -Raw), [ref]$null)
    Write-Host "Startup script syntax validated!" -ForegroundColor Green
} catch {
    Write-Host "WARNING: Startup script may have syntax issues: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ============================================================================
# STEP 6: CREATE SCHEDULED TASK FOR AUTO-START ON BOOT
# ============================================================================
Write-Host "`n[STEP 6/6] Creating scheduled task for auto-start..." -ForegroundColor Yellow

$taskName = "ValheimServerAutoStart"
$taskDescription = "Automatically starts Valheim Dedicated Server on VM boot"

# Create scheduled task action
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$startScriptPath`""

# Create scheduled task trigger (at startup)
$trigger = New-ScheduledTaskTrigger -AtStartup

# Create scheduled task settings
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

# Create scheduled task principal (run as SYSTEM with highest privileges)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Register the scheduled task
try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $taskDescription -Force | Out-Null
    Write-Host "Scheduled task '$taskName' created successfully!" -ForegroundColor Green
    Write-Host "The server will now start automatically when the VM boots." -ForegroundColor Gray
} catch {
    Write-Host "WARNING: Failed to create scheduled task. Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "You can create it manually later or start the server manually." -ForegroundColor Yellow
}

# ============================================================================
# INSTALLATION COMPLETE
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "INSTALLATION COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nImportant Information:" -ForegroundColor Yellow
Write-Host "----------------------" -ForegroundColor Yellow
Write-Host "Server Executable: C:\Valheim\server\valheim_server.exe" -ForegroundColor White
Write-Host "Startup Script: C:\Valheim\start-valheim-server.ps1" -ForegroundColor White
Write-Host "Worlds Directory: C:\Valheim\server\worlds" -ForegroundColor White
Write-Host "Log Directory: C:\Valheim\logs" -ForegroundColor White

Write-Host "`nDefault Server Settings:" -ForegroundColor Yellow
Write-Host "------------------------" -ForegroundColor Yellow
Write-Host "Server Name: My Valheim Server" -ForegroundColor White
Write-Host "World Name: MyWorld" -ForegroundColor White
Write-Host "Password: secret123" -ForegroundColor White
Write-Host "Port: 2456-2458 (UDP)" -ForegroundColor White
Write-Host "Public: Yes (listed in server browser)" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "-----------" -ForegroundColor Yellow
Write-Host "1. CONFIGURE AZURE FIREWALL:" -ForegroundColor Cyan
Write-Host "   Open UDP ports 2456, 2457, 2458 in your VM's Network Security Group" -ForegroundColor White

Write-Host "`n2. CUSTOMIZE SERVER SETTINGS (optional):" -ForegroundColor Cyan
Write-Host "   Edit: C:\Valheim\start-valheim-server.ps1" -ForegroundColor White
Write-Host "   Change server name, world name, password, etc." -ForegroundColor White

Write-Host "`n3. START SERVER MANUALLY (for testing):" -ForegroundColor Cyan
Write-Host "   PowerShell -ExecutionPolicy Bypass -File C:\Valheim\start-valheim-server.ps1" -ForegroundColor White

Write-Host "`n4. OR REBOOT VM TO START AUTOMATICALLY:" -ForegroundColor Cyan
Write-Host "   Restart-Computer -Force" -ForegroundColor White

Write-Host "`n5. VERIFY SERVER IS RUNNING:" -ForegroundColor Cyan
Write-Host "   Get-Process -Name valheim_server" -ForegroundColor White
Write-Host "   Get-Content C:\Valheim\logs\valheim-server.log -Tail 50" -ForegroundColor White

Write-Host "`n6. CONNECT FROM STEAM:" -ForegroundColor Cyan
Write-Host "   Open Valheim > Join Game > Add your VM's public IP" -ForegroundColor White
Write-Host "   Format: YOUR_VM_PUBLIC_IP:2456" -ForegroundColor White

Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
Write-Host "----------------" -ForegroundColor Yellow
Write-Host "- Check server is running: Get-Process valheim_server" -ForegroundColor White
Write-Host "- View logs: Get-Content C:\Valheim\logs\valheim-server.log -Tail 100" -ForegroundColor White
Write-Host "- Stop server: Stop-Process -Name valheim_server -Force" -ForegroundColor White
Write-Host "- Restart server: Start-ScheduledTask -TaskName ValheimServerAutoStart" -ForegroundColor White
Write-Host "- Update server: cd C:\Valheim\steamcmd; .\steamcmd.exe +force_install_dir C:\Valheim\server +login anonymous +app_update 896660 validate +quit" -ForegroundColor White

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Ready to play Valheim with friends!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nScript completed successfully!" -ForegroundColor Green
Write-Host "Window will remain open. You can close it manually or start the server now." -ForegroundColor Gray
Write-Host "`nTo start server immediately, run:" -ForegroundColor Yellow
Write-Host "PowerShell -ExecutionPolicy Bypass -File C:\Valheim\start-valheim-server.ps1" -ForegroundColor White

# Keep window open
Write-Host "`nPress any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
