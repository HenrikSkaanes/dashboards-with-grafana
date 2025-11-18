# Valheim Dedicated Server - Simple Setup Script
# No fancy checks, just gets it done

Write-Host "Starting Valheim Server Setup..." -ForegroundColor Cyan

# Stop any running servers
Get-Process -Name "valheim_server" -ErrorAction SilentlyContinue | Stop-Process -Force

# Clean up old installations
if (Test-Path "C:\Valheim") { Remove-Item "C:\Valheim" -Recurse -Force }
if (Test-Path "C:\SteamCMD") { Remove-Item "C:\SteamCMD" -Recurse -Force }
if (Test-Path "C:\steamcmd") { Remove-Item "C:\steamcmd" -Recurse -Force }

# Remove old scheduled task
Unregister-ScheduledTask -TaskName "ValheimServerAutoStart" -Confirm:$false -ErrorAction SilentlyContinue

Write-Host "Creating directories..." -ForegroundColor Gray
New-Item -Path "C:\Valheim" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\Valheim\server" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\Valheim\steamcmd" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\Valheim\logs" -ItemType Directory -Force | Out-Null

Write-Host "Downloading SteamCMD..." -ForegroundColor Gray
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$wc = New-Object System.Net.WebClient
$wc.DownloadFile("https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip", "C:\Valheim\steamcmd.zip")

Write-Host "Extracting SteamCMD..." -ForegroundColor Gray
Expand-Archive -Path "C:\Valheim\steamcmd.zip" -DestinationPath "C:\Valheim\steamcmd" -Force
Remove-Item "C:\Valheim\steamcmd.zip" -Force

Write-Host "Installing Valheim Server (this takes 5-10 minutes)..." -ForegroundColor Yellow
Write-Host "First run: Updating SteamCMD..." -ForegroundColor Gray
Set-Location "C:\Valheim\steamcmd"
& ".\steamcmd.exe" +login anonymous +quit

Write-Host "Second run: Installing Valheim Dedicated Server..." -ForegroundColor Gray
& ".\steamcmd.exe" +force_install_dir "C:\Valheim\server" +login anonymous +app_update 896660 validate +quit

if (Test-Path "C:\Valheim\server\valheim_server.exe") {
    Write-Host "Valheim server installed successfully!" -ForegroundColor Green
} else {
    Write-Host "WARNING: valheim_server.exe not found! Installation may have failed." -ForegroundColor Red
    Write-Host "Try running manually: cd C:\Valheim\steamcmd; .\steamcmd.exe +force_install_dir C:\Valheim\server +login anonymous +app_update 896660 validate +quit" -ForegroundColor Yellow
}

Write-Host "Creating startup script..." -ForegroundColor Gray
$startScript = @'
$ErrorActionPreference = "SilentlyContinue"
Set-Location "C:\Valheim\server"
.\valheim_server.exe -nographics -batchmode -name "My Valheim Server" -port 2456 -world "MyWorld" -password "secret123" -public 1 -savedir "C:\Valheim\server\worlds" > C:\Valheim\logs\server.log 2>&1
'@
Set-Content -Path "C:\Valheim\start-server.ps1" -Value $startScript

Write-Host "Creating scheduled task..." -ForegroundColor Gray
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\Valheim\start-server.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "ValheimServerAutoStart" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

Write-Host "`n=== SETUP COMPLETE ===" -ForegroundColor Green
Write-Host "Server installed at: C:\Valheim\server" -ForegroundColor White
Write-Host "Startup script: C:\Valheim\start-server.ps1" -ForegroundColor White
Write-Host "`nTo start server now:" -ForegroundColor Yellow
Write-Host "  PowerShell -File C:\Valheim\start-server.ps1" -ForegroundColor White
Write-Host "`nOr reboot VM (auto-starts on boot)" -ForegroundColor Yellow
Write-Host "`nDon't forget:" -ForegroundColor Yellow
Write-Host "  1. Open UDP ports 2456-2458 in Azure NSG" -ForegroundColor White
Write-Host "  2. Connect from Steam: YOUR_VM_IP:2456" -ForegroundColor White
Write-Host "  3. Default password: secret123" -ForegroundColor White
