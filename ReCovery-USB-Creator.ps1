# Load required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Author: LG
# Created: 6-25-2025
# Version: 4.2

# --- Script Preamble and Administrative Check ---

# Define a base working directory and log file path early.
$ScriptWorkDir = "C:\USB"
$ScriptLogFile = Join-Path $ScriptWorkDir "winpe_creation.log"
$script:cancelRequested = $false
$script:opStartTime = $null

# Ensure the base working directory exists before any logging attempts
if (-Not (Test-Path $ScriptWorkDir)) {
    New-Item -ItemType Directory -Path $ScriptWorkDir -Force | Out-Null
}

# Check for Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    [System.Windows.Forms.MessageBox]::Show("This script must be run with Administrator privileges.", "Permission Denied", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}

# --- Logging Functions ---

function Log-ToFile {
    param ([string]$message, [string]$logFile)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formattedMessage = "[$timestamp] $message"
    Add-Content -Path $logFile -Value $formattedMessage
}

function Log-ToAll {
    param ([string]$message, [System.Windows.Forms.TextBox]$textBox, [string]$logFile)
    if ($textBox -and $logFile) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $formattedMessage = "[$timestamp] $message"
        $textBox.AppendText($formattedMessage + [Environment]::NewLine)
        $textBox.SelectionStart = $textBox.Text.Length
        $textBox.ScrollToCaret()
        Add-Content -Path $logFile -Value $formattedMessage
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# --- UI Functions ---

function Show-EditionSelector {
    param (
        [System.Windows.Forms.Form]$parentForm,
        [array]$imageEditions
    )

    $selectorForm = New-Object System.Windows.Forms.Form
    $selectorForm.Text = "Select Windows Edition"
    $selectorForm.Size = New-Object System.Drawing.Size(400, 300)
    $selectorForm.StartPosition = "CenterParent"
    $selectorForm.FormBorderStyle = "FixedDialog"
    $selectorForm.MaximizeBox = $false
    $selectorForm.MinimizeBox = $false
    $selectorForm.TopMost = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Select the Windows edition to install:"
    $label.Location = New-Object System.Drawing.Point(10, 10)
    $label.AutoSize = $true
    $selectorForm.Controls.Add($label)

    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Location = New-Object System.Drawing.Point(10, 30)
    $listBox.Size = New-Object System.Drawing.Size(360, 180)
    
    $listBox.DataSource = $imageEditions
    $listBox.DisplayMember = "Display"
    $listBox.ValueMember = "Index"
    
    $selectorForm.Controls.Add($listBox)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Location = New-Object System.Drawing.Point(150, 220)
    $okButton.Size = New-Object System.Drawing.Size(80, 30)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $selectorForm.Controls.Add($okButton)
    $selectorForm.AcceptButton = $okButton

    $result = $selectorForm.ShowDialog($parentForm)
    $selectorForm.Dispose()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $listBox.SelectedItem
    } else {
        return $null
    }
}

# --- Core Functions ---

function Clear-USBDrive {
    param (
        [string]$DriveLetterWithColon,
        [System.Windows.Forms.Form]$parentForm,
        [System.Windows.Forms.TextBox]$outputBox,
        [string]$logFile
    )
    
    Log-ToAll -message "Attempting to perform a low-level clean and format of drive $DriveLetterWithColon..." -textBox $outputBox -logFile $logFile
    
    try {
        $partitionToFind = Get-Partition -DriveLetter ($DriveLetterWithColon.TrimEnd(':')) -ErrorAction Stop
        $diskToClear = Get-Disk -Partition $partitionToFind -ErrorAction Stop

        if (-not $diskToClear) {
            Log-ToAll -message "CRITICAL ERROR: Could not find a physical disk for drive letter $DriveLetterWithColon." -textBox $outputBox -logFile $logFile
            return $false
        }
        
        $diskNumber = $diskToClear.Number

        if ($diskToClear.BusType -eq 'USB' -and $diskToClear.MediaType -eq 'Fixed') {
            Log-ToAll -message "INFO: The selected USB drive is reported as a 'Fixed' disk, not 'Removable'." -textBox $outputBox -logFile $logFile
            $fixedConfirm = [System.Windows.Forms.MessageBox]::Show($parentForm, "This USB drive reports itself as a FIXED disk.`n`nPlease confirm that Disk $($diskToClear.Number) ($($diskToClear.FriendlyName)) is the correct USB drive you wish to wipe.`n`nChoosing 'No' will safely cancel the operation.", "Fixed Disk Warning", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($fixedConfirm -ne [System.Windows.Forms.DialogResult]::Yes) {
                Log-ToAll -message "User cancelled the operation due to Fixed disk warning." -textBox $outputBox -logFile $logFile
                return $false
            }
        }

        $confirmMessage = @"
FINAL WARNING: You are about to completely wipe and format:

Disk Number: $($diskToClear.Number)
Model: $($diskToClear.FriendlyName)
Size: $([math]::Round($diskToClear.Size / 1GB, 2)) GB

This action is IRREVERSIBLE.
Are you absolutely sure you want to proceed?
"@
        $finalConfirm = [System.Windows.Forms.MessageBox]::Show($parentForm, $confirmMessage, "Final Confirmation Required", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Exclamation)
        
        if ($finalConfirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            Log-ToAll -message "User confirmed. Wiping Disk $diskNumber..." -textBox $outputBox -logFile $logFile
            Clear-Disk -Number $diskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
            Log-ToAll -message "Disk wipe complete." -textBox $outputBox -logFile $logFile

            Log-ToAll -message "Pausing for 2 seconds to allow OS to rescan disk..." -textBox $outputBox -logFile $logFile
            Start-Sleep -Seconds 2 
            $refreshedDisk = Get-Disk -Number $diskNumber
            
            if ($refreshedDisk.PartitionStyle -eq 'Raw') {
                Log-ToAll -message "Disk is Raw. Initializing disk..." -textBox $outputBox -logFile $logFile
                Initialize-Disk -Number $diskNumber -PartitionStyle MBR -ErrorAction Stop
            } else {
                Log-ToAll -message "Disk was already initialized by the OS. Skipping initialization step." -textBox $outputBox -logFile $logFile
            }
            
            Log-ToAll -message "Creating new partition..." -textBox $outputBox -logFile $logFile
            $newPartition = New-Partition -DiskNumber $diskNumber -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
            
            Log-ToAll -message "Pausing for 2 seconds before formatting..." -textBox $outputBox -logFile $logFile
            Start-Sleep -Seconds 2

            Log-ToAll -message "Formatting volume $($newPartition.DriveLetter) as NTFS..." -textBox $outputBox -logFile $logFile
            Format-Volume -Partition $newPartition -FileSystem NTFS -NewFileSystemLabel "WinPE USB" -Confirm:$false -ErrorAction Stop

            Log-ToAll -message "Disk $diskNumber has been successfully prepared and formatted as NTFS." -textBox $outputBox -logFile $logFile
            return $true
        } else {
            Log-ToAll -message "User cancelled the low-level clean operation at the final prompt." -textBox $outputBox -logFile $logFile
            return $false
        }

    } catch {
        Log-ToAll -message "ERROR during USB-PREP: $_. The drive may be locked by another process. Please close all File Explorer windows, then physically eject and re-insert the USB drive before trying again." -textBox $outputBox -logFile $logFile
        [System.Windows.Forms.MessageBox]::Show("An error occurred while preparing the disk. Please see the log for details. Try physically re-inserting the drive and running the script again.", "Preparation Failed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return $false
    }
}


function Download-File {
    param ([string]$url, [string]$destination)
    try { Invoke-WebRequest -Uri $url -OutFile $destination } catch { Write-Host "Error downloading $url`n$_"; Log-ToFile -message "Error downloading $url`: $_" -logFile $ScriptLogFile; return $false }
    return $true
}

function Run-Cmd {
    param ([string]$command, [System.Windows.Forms.TextBox]$outputBox, [string]$logFile)
    Log-ToAll -message "Executing: $command" -textBox $outputBox -logFile $logFile
    $tempOut = [System.IO.Path]::GetTempFileName()
    $tempErr = [System.IO.Path]::GetTempFileName()
    $processOutput = @()
    $exitCode = -1
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd.exe"
        $psi.Arguments = "/c $command > `"$tempOut`" 2>`"$tempErr`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::Start($psi)
        while (-not $process.HasExited) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 150
        }
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    } catch {
        Log-ToFile -message "Failed to launch process: $_" -logFile $logFile
    } finally {
        if (Test-Path $tempOut) { $processOutput += Get-Content $tempOut -ErrorAction SilentlyContinue; Remove-Item $tempOut -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempErr) { $processOutput += Get-Content $tempErr -ErrorAction SilentlyContinue; Remove-Item $tempErr -Force -ErrorAction SilentlyContinue }
    }
    foreach ($line in $processOutput) {
        $stringLine = [string]$line
        if ($stringLine.Trim() -ne "") { Log-ToFile -message $stringLine -logFile $logFile }
    }
    Log-ToFile -message "Command exited with code: $exitCode" -logFile $logFile
    return [pscustomobject]@{
        Output = $processOutput
        ExitCode = $exitCode
    }
}

function Get-PhysicalDiskNumber {
    param ([string]$DriveLetterWithColon, [System.Windows.Forms.TextBox]$outputBox, [string]$logFile)
    try {
        $volume = Get-Volume -DriveLetter ($DriveLetterWithColon.TrimEnd(':')) -ErrorAction Stop
        $partition = Get-Partition -Volume $volume -ErrorAction Stop
        $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
        return $disk.Number
    } catch {
        Log-ToAll -message "Warning: Could not determine physical disk number for $DriveLetterWithColon. Error details: ${$_}" -textBox $outputBox -logFile $logFile
        return $null
    }
}

function Check-ADKTools {
    param ([System.Windows.Forms.TextBox]$outputBox, [string]$logFile)
    $adkPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
    $winpePath = "$adkPath\Windows Preinstallation Environment"
    $copypePath = "$winpePath\copype.cmd"
    $bootsectPath = "$adkPath\Deployment Tools\amd64\BCDBoot\bootsect.exe"

    if (-Not (Test-Path $copypePath) -or -Not (Test-Path $bootsectPath)) {
        Log-ToAll -message "ADK or required tools (bootsect.exe) not found. Attempting to download and install..." -textBox $outputBox -logFile $logFile
        $adkInstaller = Join-Path $ScriptWorkDir "adksetup.exe"
        $winpeInstaller = Join-Path $ScriptWorkDir "adkwinpesetup.exe"
        
        if (-Not (Test-Path $adkInstaller)) {
            Log-ToAll -message "Downloading ADK installer..." -textBox $outputBox -logFile $logFile
            if (-Not (Download-File -url "https://go.microsoft.com/fwlink/?linkid=2289980" -destination $adkInstaller)) {
                [System.Windows.Forms.MessageBox]::Show("Failed to download ADK installer.", "Download Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error); exit
            }
        }
        if (-Not (Test-Path $winpeInstaller)) {
            Log-ToAll -message "Downloading WinPE add-on installer..." -textBox $outputBox -logFile $logFile
            if (-Not (Download-File -url "https://go.microsoft.com/fwlink/?linkid=2289981" -destination $winpeInstaller)) {
                [System.Windows.Forms.MessageBox]::Show("Failed to download WinPE installer.", "Download Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error); exit
            }
        }
        Log-ToAll -message "Starting ADK installation..." -textBox $outputBox -logFile $logFile
        Start-Process -FilePath $adkInstaller -Wait
        Log-ToAll -message "Starting WinPE add-on installation..." -textBox $outputBox -logFile $logFile
        Start-Process -FilePath $winpeInstaller -Wait
        if (-Not (Test-Path $copypePath) -or -Not (Test-Path $bootsectPath)) {
            Log-ToAll -message "Required ADK tools not found after installation. Please install manually." -textBox $outputBox -logFile $logFile
            [System.Windows.Forms.MessageBox]::Show("Required ADK tools not found after installation. Please install manually.", "Installation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error); exit
        }
    }
    Log-ToAll -message "ADK and WinPE tools found and ready." -textBox $outputBox -logFile $logFile
}


function Run-WinPECreation {
    param ([string]$usbDrive, [System.Windows.Forms.Form]$parentForm, [System.Windows.Forms.TextBox]$outputBox, [System.Windows.Forms.ProgressBar]$progressBar, [System.Windows.Forms.Button]$createButton, [System.Windows.Forms.Button]$prepButton, [System.Windows.Forms.Button]$cancelButton, [string]$logFile)

    $createButton.Enabled = $false; $prepButton.Enabled = $false; $cancelButton.Enabled = $true; $progressBar.Value = 0
    
    $workDir = $ScriptWorkDir
    $mediaPath = Join-Path $workDir "media"
    $mountPath = Join-Path $workDir "mount"
    $installMountPath = Join-Path $workDir "mount-install"
    $arch = "amd64"
    $adkRootPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
    $winpeSourcePath = Join-Path $adkRootPath "Windows Preinstallation Environment\$arch"
    $bootsectPath = Join-Path $adkRootPath "Deployment Tools\amd64\BCDBoot\bootsect.exe"

    if (Test-Path $logFile) { Remove-Item $logFile -Force }

    Log-ToAll -message "--- Starting New Session: Performing initial cleanup ---" -textBox $outputBox -logFile $logFile
    Log-ToAll -message "Cleaning up potential stale mount point: $mountPath" -textBox $outputBox -logFile $logFile
    Run-Cmd "dism /unmount-image /mountdir:`"$mountPath`" /discard" -outputBox $outputBox -logFile $logFile | Out-Null
    Log-ToAll -message "Cleaning up potential stale mount point: $installMountPath" -textBox $outputBox -logFile $logFile
    Run-Cmd "dism /unmount-image /mountdir:`"$installMountPath`" /discard" -outputBox $outputBox -logFile $logFile | Out-Null
    
    Check-ADKTools -outputBox $outputBox -logFile $logFile

    if ($script:cancelRequested) {
        Log-ToAll -message "--- Operation cancelled. ---" -textBox $outputBox -logFile $logFile
        $createButton.Enabled = $true; $prepButton.Enabled = $true; return
    }

    Log-ToAll -message "PHASE 1: Customizing WinPE Image..." -textBox $outputBox -logFile $logFile
    
    Log-ToAll -message "[1.1] Creating working directories..." -textBox $outputBox -logFile $logFile
    $progressBar.Maximum = 10 
    $progressBar.Value = 1
    if (Test-Path $mountPath) { Remove-Item -Recurse -Force $mountPath }
    if (Test-Path $installMountPath) { Remove-Item -Recurse -Force $installMountPath }
    if (Test-Path $mediaPath) { Remove-Item -Recurse -Force $mediaPath }
    New-Item -ItemType Directory -Path $mediaPath, $mountPath, $installMountPath -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $mediaPath "sources") -Force | Out-Null
    
    Log-ToAll -message "[1.2] Copying base WinPE files..." -textBox $outputBox -logFile $logFile
    Copy-Item -Path (Join-Path $winpeSourcePath "media\*") -Destination $mediaPath -Recurse -Force
    $bootWimDest = Join-Path $mediaPath "sources\boot.wim"
    Copy-Item -Path (Join-Path $winpeSourcePath "en-us\winpe.wim") -Destination $bootWimDest -Force

    Log-ToAll -message "[1.3] Mounting WinPE image for customization..." -textBox $outputBox -logFile $logFile
    $progressBar.Value = 2
    if ((Run-Cmd "dism /Mount-Image /ImageFile:`"$bootWimDest`" /index:1 /MountDir:`"$mountPath`"" -outputBox $outputBox -logFile $logFile).ExitCode -ne 0) {
        Log-ToAll -message "Error: Failed to mount the image." -textBox $outputBox -logFile $logFile; $createButton.Enabled = $true; $prepButton.Enabled = $true; return
    }

    Log-ToAll -message "[1.4] Exporting third-party drivers from this PC..." -textBox $outputBox -logFile $logFile
    $progressBar.Value = 3
    $driverDest = Join-Path $workDir "drivers"
    if(Test-Path $driverDest) { Remove-Item -Recurse -Force $driverDest }
    New-Item -ItemType Directory -Path $driverDest -Force | Out-Null
    if ((Run-Cmd "dism /online /export-driver /destination:`"$driverDest`"" -outputBox $outputBox -logFile $logFile).ExitCode -ne 0) {
        Log-ToAll -message "Warning: Failed to export drivers. Continuing without them..." -textBox $outputBox -logFile $logFile
    } else {
        Log-ToAll -message "Injecting exported drivers into WinPE image..." -textBox $outputBox -logFile $logFile
        if ((Run-Cmd "dism /image:`"$mountPath`" /add-driver /driver:`"$driverDest`" /recurse" -outputBox $outputBox -logFile $logFile).ExitCode -ne 0) {
            Log-ToAll -message "Warning: Some drivers could not be injected. This might be okay." -textBox $outputBox -logFile $logFile
        }
    }


    Log-ToAll -message "[1.5] Creating custom menu and restore scripts..." -textBox $outputBox -logFile $logFile
    $progressBar.Value = 4

    Copy-Item -Path "$env:SystemRoot\System32\choice.exe" -Destination (Join-Path $mountPath "Windows\System32\") -Force

    $menuScriptContent = @"
@echo off
title ReCovery-USB-Creator :: Main Menu
:start
cls
echo ========================================
echo    ReCovery-USB-Creator :: Main Menu
echo ========================================
echo.
echo Please choose an option:
echo.
echo   [1] Automated Windows 11 Restore (Wipes the primary hard drive!)
echo.
echo   [2] Open Recovery Command Prompt (For manual repairs)
echo.
echo   [3] Reboot Computer
echo.

choice /c 123 /m "Enter your choice: "

if errorlevel 3 goto reboot
if errorlevel 2 goto command
if errorlevel 1 goto restore

:restore
cls
call %~d0\Restore-Windows.bat
goto start

:command
cls
echo Starting Recovery Command Prompt...
cmd.exe
goto start

:reboot
echo Rebooting...
wpeutil reboot
goto end

:end
"@
    Set-Content -Path (Join-Path $mediaPath "Menu.bat") -Value $menuScriptContent

    $restoreScriptContent = @"
@echo off
title Automated Windows 11 Restore
echo ==========================================================
echo           !! WARNING !! WARNING !! WARNING !!
echo ==========================================================
echo.
echo This process will completely ERASE everything on the
echo computer's primary internal hard drive (Disk 0).
echo.
echo ASSUMPTION: This script targets Disk 0. On systems with
echo multiple internal drives, run 'diskpart' then 'list disk'
echo to confirm Disk 0 is your Windows drive before proceeding.
echo.
echo All personal files, applications, and settings will be
echo permanently destroyed.
echo.
echo This action CANNOT be undone.
echo.
set /p "areyousure=Are you absolutely sure you want to continue? (Y/N): "
if /i not "%areyousure%"=="y" goto cancel

echo Creating disk partitions...
echo select disk 0 > %~d0\diskpart.txt
echo clean >> %~d0\diskpart.txt
echo convert gpt >> %~d0\diskpart.txt
echo create partition efi size=100 >> %~d0\diskpart.txt
echo format quick fs=fat32 label="System" >> %~d0\diskpart.txt
echo assign letter=S >> %~d0\diskpart.txt
echo create partition msr size=16 >> %~d0\diskpart.txt
echo create partition primary >> %~d0\diskpart.txt
echo format quick fs=ntfs label="Windows" >> %~d0\diskpart.txt
echo assign letter=W >> %~d0\diskpart.txt
diskpart /s %~d0\diskpart.txt

echo.
echo Applying Windows 11 image... This will take a while.
dism /apply-image /imagefile:%~d0\sources\install.wim /index:##INDEX_PLACEHOLDER## /applydir:W:\

echo.
echo Creating boot files...
bcdboot W:\Windows /s S: /f UEFI

echo.
echo =================================================
echo  RESTORE COMPLETE. You can now close this window.
echo  Reboot the computer and remove the USB drive.
echo =================================================
echo.
goto end

:cancel
echo Operation cancelled by user.

:end
pause
"@
    Set-Content -Path (Join-Path $mediaPath "Restore-Windows.bat") -Value $restoreScriptContent

    # --- ARCHITECTURE FIX: The startup script now searches for Menu.bat on all drives ---
    Log-ToAll -message "[1.6] Setting custom menu to launch on boot..." -textBox $outputBox -logFile $logFile
    $startnetContent = @"
@echo off
wpeinit
echo Searching for ReCovery-USB-Creator menu...
for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%D:\Menu.bat" (
        echo Found menu on drive %%D:
        call %%D:\Menu.bat
        goto :eof
    )
)
echo ERROR: Could not find Menu.bat on any connected drives.
pause
"@
    Set-Content -Path (Join-Path $mountPath "Windows\System32\startnet.cmd") -Value $startnetContent

    Log-ToAll -message "[1.7] Unmounting and committing all changes to WinPE image..." -textBox $outputBox -logFile $logFile
    $progressBar.Value = 5
    if ((Run-Cmd "dism /Unmount-Image /MountDir:`"$mountPath`" /Commit" -outputBox $outputBox -logFile $logFile).ExitCode -ne 0) {
        Log-ToAll -message "Error: Failed to unmount and commit changes." -textBox $outputBox -logFile $logFile; $createButton.Enabled = $true; $prepButton.Enabled = $true; return
    }

    if ($script:cancelRequested) {
        Log-ToAll -message "--- Operation cancelled after Phase 1. ---" -textBox $outputBox -logFile $logFile
        $createButton.Enabled = $true; $prepButton.Enabled = $true; return
    }

    Log-ToAll -message "PHASE 2: Preparing USB Drive and Copying Files..." -textBox $outputBox -logFile $logFile
    
    $progressBar.Value = 6
    
    Log-ToAll -message "[2.1] Preparing USB drive ($usbDrive) using PowerShell..." -textBox $outputBox -logFile $logFile
    $usbDiskNumber = Get-PhysicalDiskNumber -DriveLetterWithColon $usbDrive -outputBox $outputBox -logFile $logFile
    if (-not $usbDiskNumber) {
        Log-ToAll -message "Error: Could not determine physical disk number. Preparation aborted." -textBox $outputBox -logFile $logFile
        $createButton.Enabled = $true; $prepButton.Enabled = $true; return
    }

    $usbDiskObj = Get-Disk -Number $usbDiskNumber
    $usbSizeGB = [math]::Round($usbDiskObj.Size / 1GB, 1)
    if ($usbDiskObj.Size -lt 8GB) {
        Log-ToAll -message "ERROR: USB drive is $usbSizeGB GB. Minimum 8 GB required (16 GB recommended for Windows installation files)." -textBox $outputBox -logFile $logFile
        [System.Windows.Forms.MessageBox]::Show($parentForm, "The selected USB drive is too small ($usbSizeGB GB).`n`nMinimum required: 8 GB`nRecommended for full installation: 16 GB", "Drive Too Small", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        $createButton.Enabled = $true; $prepButton.Enabled = $true; return
    }
    Log-ToAll -message "Drive size check passed: $usbSizeGB GB." -textBox $outputBox -logFile $logFile

    if ($usbDiskObj.BusType -eq 'USB' -and $usbDiskObj.MediaType -eq 'Fixed') {
        Log-ToAll -message "INFO: USB drive is reported as a 'Fixed' disk type." -textBox $outputBox -logFile $logFile
        $fixedCheck = [System.Windows.Forms.MessageBox]::Show($parentForm, "This USB drive reports itself as a FIXED disk.`n`nPlease confirm that Disk $($usbDiskObj.Number) ($($usbDiskObj.FriendlyName)) is the correct drive to wipe.`n`nChoosing 'No' will safely cancel the operation.", "Fixed Disk Warning", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($fixedCheck -ne [System.Windows.Forms.DialogResult]::Yes) {
            Log-ToAll -message "User cancelled due to Fixed disk warning." -textBox $outputBox -logFile $logFile
            $createButton.Enabled = $true; $prepButton.Enabled = $true; return
        }
    }

    try {
        Log-ToAll -message "[2.1] Wiping disk $usbDiskNumber..." -textBox $outputBox -logFile $logFile
        Clear-Disk -Number $usbDiskNumber -RemoveData -Confirm:$false -ErrorAction Stop

        Log-ToAll -message "[2.1] Pausing for 2 seconds to allow OS to rescan disk..." -textBox $outputBox -logFile $logFile
        Start-Sleep -Seconds 2

        $refreshedDisk = Get-Disk -Number $usbDiskNumber
        if ($refreshedDisk.PartitionStyle -eq 'Raw') {
            Log-ToAll -message "[2.1] Initializing disk as MBR..." -textBox $outputBox -logFile $logFile
            Initialize-Disk -Number $usbDiskNumber -PartitionStyle MBR -ErrorAction Stop
        } elseif ($refreshedDisk.PartitionStyle -ne 'MBR') {
            Log-ToAll -message "[2.1] Converting disk to MBR (required for bootable USB)..." -textBox $outputBox -logFile $logFile
            Set-Disk -Number $usbDiskNumber -PartitionStyle MBR -ErrorAction Stop
        } else {
            Log-ToAll -message "[2.1] Disk is already MBR." -textBox $outputBox -logFile $logFile
        }

        Log-ToAll -message "[2.1] Creating new partition..." -textBox $outputBox -logFile $logFile
        $newPartition = New-Partition -DiskNumber $usbDiskNumber -UseMaximumSize -AssignDriveLetter -ErrorAction Stop

        Log-ToAll -message "[2.1] Marking partition as active (required for bootsect)..." -textBox $outputBox -logFile $logFile
        Set-Partition -DiskNumber $usbDiskNumber -PartitionNumber $newPartition.PartitionNumber -IsActive $true -ErrorAction SilentlyContinue

        Log-ToAll -message "[2.1] Pausing for 2 seconds before formatting..." -textBox $outputBox -logFile $logFile
        Start-Sleep -Seconds 2

        Log-ToAll -message "[2.1] Formatting volume $($newPartition.DriveLetter) as NTFS..." -textBox $outputBox -logFile $logFile
        Format-Volume -Partition $newPartition -FileSystem NTFS -NewFileSystemLabel "WinPE USB" -Confirm:$false -ErrorAction Stop
    } catch {
        Log-ToAll -message "ERROR during disk preparation: $_. The drive may be locked. Please close all File Explorer windows, eject the drive, re-insert it, and try again." -textBox $outputBox -logFile $logFile
        [System.Windows.Forms.MessageBox]::Show($parentForm, "An error occurred while preparing the disk. Please see the log for details. Try physically re-inserting the drive and running the script again.", "Preparation Failed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        $createButton.Enabled = $true; $prepButton.Enabled = $true; return
    }

    Log-ToAll -message "[2.2] Making USB drive bootable..." -textBox $outputBox -logFile $logFile
    $progressBar.Value = 7
    Start-Sleep -Seconds 3

    $driveLetterOnly = $usbDrive.TrimEnd('\').TrimEnd(':')
    $partForUnmount = Get-Partition -DriveLetter $driveLetterOnly -ErrorAction SilentlyContinue
    if ($partForUnmount) {
        Log-ToAll -message "[2.2] Dismounting volume to release Explorer locks before bootsect..." -textBox $outputBox -logFile $logFile
        Remove-PartitionAccessPath -DiskNumber $partForUnmount.DiskNumber -PartitionNumber $partForUnmount.PartitionNumber -AccessPath "$driveLetterOnly`:\" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Add-PartitionAccessPath -DiskNumber $partForUnmount.DiskNumber -PartitionNumber $partForUnmount.PartitionNumber -AccessPath "$driveLetterOnly`:\" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    Log-ToAll -message "[2.2] Running bootsect to write boot sector..." -textBox $outputBox -logFile $logFile
    $bootsectOutput = & "$bootsectPath" /nt60 $usbDrive /force 2>&1
    $bootsectExit = $LASTEXITCODE
    foreach ($line in $bootsectOutput) { Log-ToFile -message ([string]$line) -logFile $logFile }
    Log-ToFile -message "bootsect exited with code: $bootsectExit" -logFile $logFile
    if ($bootsectExit -ne 0) {
        Log-ToAll -message "Error: Failed to write bootsector (exit $bootsectExit). Check log for details." -textBox $outputBox -logFile $logFile
        $createButton.Enabled = $true; $prepButton.Enabled = $true; return
    }
    
    Log-ToAll -message "[2.3] Copying all temporary files to USB drive..." -textBox $outputBox -logFile $logFile
    if ((Run-Cmd "robocopy `"$mediaPath`" `"$($usbDrive.TrimEnd('\'))`" /E" -outputBox $outputBox -logFile $logFile).ExitCode -gt 3) {
        Log-ToAll -message "Error: Failed to copy WinPE files." -textBox $outputBox -logFile $logFile; $createButton.Enabled = $true; $prepButton.Enabled = $true; return
    }

    if ($script:cancelRequested) {
        Log-ToAll -message "--- Operation cancelled after Phase 2. WinPE-only USB is ready but ISO was not added. ---" -textBox $outputBox -logFile $logFile
        Remove-Item -Recurse -Force $mountPath, $mediaPath, $driverDest -ErrorAction SilentlyContinue
        $createButton.Enabled = $true; $prepButton.Enabled = $true; return
    }

    Log-ToAll -message "PHASE 3: Adding Windows 11 Installation Files and Drivers..." -textBox $outputBox -logFile $logFile
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Title = "Please select the Windows 11 ISO file"
    $openFileDialog.Filter = "ISO Files (*.iso)|*.iso"
    if ($openFileDialog.ShowDialog($parentForm) -eq [System.Windows.Forms.DialogResult]::OK) {
        $isoFile = $openFileDialog.FileName
        Log-ToAll -message "[3.1] Mounting Windows 11 ISO: $isoFile" -textBox $outputBox -logFile $logFile
        
        try {
            $isoDriveLetter = (Mount-DiskImage -ImagePath $isoFile -PassThru | Get-Volume).DriveLetter + ":"
            $localInstallWim = Join-Path $mediaPath "sources\install.wim"
            
            Log-ToAll -message "[3.2] Searching for installation image in $isoDriveLetter\sources..." -textBox $outputBox -logFile $logFile
            $wimSourcePath = Join-Path $isoDriveLetter "sources\install.wim"
            $esdSourcePath = Join-Path $isoDriveLetter "sources\install.esd"

            if (Test-Path $wimSourcePath) {
                Log-ToAll -message "[3.2] Found install.wim. Copying to local cache..." -textBox $outputBox -logFile $logFile
                Copy-Item -Path $wimSourcePath -Destination $localInstallWim -Force
            } elseif (Test-Path $esdSourcePath) {
                Log-ToAll -message "[3.2] Found install.esd. Copying to local cache..." -textBox $outputBox -logFile $logFile
                Copy-Item -Path $esdSourcePath -Destination $localInstallWim -Force
            } else {
                [System.Windows.Forms.MessageBox]::Show($parentForm, "Could not find install.wim or install.esd in the selected ISO.", "Image Not Found", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                throw "Installation image not found in ISO."
            }
            $progressBar.Value = 8

            Log-ToAll -message "[3.3] Setting file attributes on local install.wim..." -textBox $outputBox -logFile $logFile
            Set-ItemProperty -Path $localInstallWim -Name IsReadOnly -Value $false

            Log-ToAll -message "[3.4] Getting information about Windows editions..." -textBox $outputBox -logFile $logFile
            $dismInfo = Run-Cmd "dism /get-imageinfo /imagefile:`"$localInstallWim`"" -outputBox $outputBox -logFile $logFile
            if ($dismInfo.ExitCode -ne 0) { throw "Failed to get image info from install.wim" }

            $editionList = [System.Collections.Generic.List[object]]::new()
            $dismInfo.Output | ForEach-Object {
                if ($_ -match "Index : (.*)") { $currentIndex = $matches[1].Trim() }
                if ($_ -match "Name : (.*)") { 
                    $currentName = $matches[1].Trim()
                    if ($currentIndex -and $currentName) { 
                        $editionList.Add([pscustomobject]@{
                            Index = $currentIndex
                            Display = "$currentIndex - $currentName"
                        })
                        $currentIndex = $null 
                    }
                }
            }

            $selectedEditionObject = Show-EditionSelector -parentForm $parentForm -imageEditions $editionList
            if (-not $selectedEditionObject) { throw "User cancelled edition selection." }
            
            $chosenIndex = $selectedEditionObject.Index
            
            Log-ToAll -message "[3.5] User selected: `"$($selectedEditionObject.Display)`" (Index: $chosenIndex)" -textBox $outputBox -logFile $logFile
            
            Log-ToAll -message "[3.5] Mounting Windows installation image index $chosenIndex. This may take some time..." -textBox $outputBox -logFile $logFile
            if ((Run-Cmd "dism /mount-image /imagefile:`"$localInstallWim`" /index:$chosenIndex /mountdir:`"$installMountPath`"" -outputBox $outputBox -logFile $logFile).ExitCode -ne 0) {
                throw "Failed to mount the install.wim"
            }
            $progressBar.Value = 9

            Log-ToAll -message "[3.6] Injecting third-party drivers into Windows installation image..." -textBox $outputBox -logFile $logFile
            if ((Run-Cmd "dism /image:`"$installMountPath`" /add-driver /driver:`"$driverDest`" /recurse" -outputBox $outputBox -logFile $logFile).ExitCode -ne 0) {
                Log-ToAll -message "Warning: Some drivers could not be injected into the main Windows image. This might be okay." -textBox $outputBox -logFile $logFile
            }

            Log-ToAll -message "[3.7] Committing changes to install.wim. THIS IS THE LONGEST STEP. PLEASE BE PATIENT..." -textBox $outputBox -logFile $logFile
            if ((Run-Cmd "dism /unmount-image /mountdir:`"$installMountPath`" /commit" -outputBox $outputBox -logFile $logFile).ExitCode -ne 0) {
                throw "Failed to unmount and commit install.wim"
            }
            
            Log-ToAll -message "[3.8] Copying modified install.wim to USB drive..." -textBox $outputBox -logFile $logFile
            if ((Run-Cmd "robocopy `"$($mediaPath)\sources`" `"$($usbDrive.TrimEnd('\'))\sources`" `"$($localInstallWim | Split-Path -Leaf)`" /COPY:DAT /R:3 /W:5" -outputBox $outputBox -logFile $logFile).ExitCode -gt 1) {
                throw "Failed to copy modified install.wim to USB drive."
            }
            
            # ARCHITECTURE FIX: Modify the placeholder in the batch file on the USB drive
            Log-ToAll -message "[3.9] Dynamically updating restore script on USB with selected index..." -textBox $outputBox -logFile $logFile
            $restoreScriptPathOnUsb = Join-Path ($usbDrive.TrimEnd('\')) "Restore-Windows.bat"
            $scriptContent = Get-Content -Path $restoreScriptPathOnUsb -Raw
            $newContent = $scriptContent -replace '##INDEX_PLACEHOLDER##', $chosenIndex
            Set-Content -Path $restoreScriptPathOnUsb -Value $newContent -Force
            $progressBar.Value = 10

        }
        catch {
            Log-ToAll -message "ERROR during advanced ISO processing: $_" -textBox $outputBox -logFile $logFile
            [System.Windows.Forms.MessageBox]::Show($parentForm, "An error occurred during the advanced driver injection process. Please check the log for details.", "Processing Failed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            $createButton.Enabled = $true; $prepButton.Enabled = $true; return
        }
        finally {
            Log-ToAll -message "[3.10] Cleaning up temporary files..." -textBox $outputBox -logFile $logFile
            Dismount-DiskImage -ImagePath $isoFile | Out-Null
            if (Test-Path $installMountPath) { Remove-Item -Recurse -Force $installMountPath }
        }
    } else {
        Log-ToAll -message "User cancelled ISO selection. Drive will be a standard WinPE tool without Windows 11 installation files." -textBox $outputBox -logFile $logFile
        $restoreScriptPathOnUsb = Join-Path ($usbDrive.TrimEnd('\')) "Restore-Windows.bat"
        if (Test-Path $restoreScriptPathOnUsb) {
            $scriptContent = Get-Content -Path $restoreScriptPathOnUsb -Raw
            if ($scriptContent -match '##INDEX_PLACEHOLDER##') {
                $newContent = $scriptContent -replace '##INDEX_PLACEHOLDER##', '1'
                Set-Content -Path $restoreScriptPathOnUsb -Value $newContent -Force
                Log-ToAll -message "Note: Restore-Windows.bat index defaulted to 1 (no ISO selected)." -textBox $outputBox -logFile $logFile
            }
        }
    }
    
    Remove-Item -Recurse -Force $mountPath, $mediaPath, $driverDest -ErrorAction SilentlyContinue
    
    Log-ToAll -message "ReCovery USB Drive created successfully!" -textBox $outputBox -logFile $logFile
    [System.Windows.Forms.MessageBox]::Show($parentForm, "ReCovery USB Drive created successfully!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    $createButton.Enabled = $true
    $prepButton.Enabled = $true
}


# --- GUI Setup ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "ReCovery-USB-Creator v4.2"
$form.Size = New-Object System.Drawing.Size(500, 490); $form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"; $form.MaximizeBox = $false

$label = New-Object System.Windows.Forms.Label
$label.Text = "Select USB Drive:"; $label.Location = New-Object System.Drawing.Point(20, 22)
$label.Size = New-Object System.Drawing.Size(120, 20); $form.Controls.Add($label)

$comboBox = New-Object System.Windows.Forms.ComboBox
$comboBox.Location = New-Object System.Drawing.Point(150, 22); $comboBox.Size = New-Object System.Drawing.Size(200, 20)
$comboBox.DropDownStyle = "DropDownList"; $form.Controls.Add($comboBox)

$comboBox.Add_DropDown({
    $currentItem = $comboBox.SelectedItem
    $comboBox.Items.Clear()
    Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 } | ForEach-Object { $comboBox.Items.Add($_.DeviceID) }
    $comboBox.SelectedItem = $currentItem
})
Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 } | ForEach-Object { $comboBox.Items.Add($_.DeviceID) }

$outputBox = New-Object System.Windows.Forms.TextBox
$outputBox.Multiline = $true; $outputBox.ScrollBars = "Vertical"
$outputBox.Location = New-Object System.Drawing.Point(20, 52); $outputBox.Size = New-Object System.Drawing.Size(440, 265)
$outputBox.ReadOnly = $true; $form.Controls.Add($outputBox)

$elapsedLabel = New-Object System.Windows.Forms.Label
$elapsedLabel.Text = ""; $elapsedLabel.Location = New-Object System.Drawing.Point(20, 324)
$elapsedLabel.Size = New-Object System.Drawing.Size(440, 18); $form.Controls.Add($elapsedLabel)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 348); $progressBar.Size = New-Object System.Drawing.Size(440, 20)
$progressBar.Minimum = 0; $progressBar.Maximum = 10; $form.Controls.Add($progressBar)

$elapsedTimer = New-Object System.Windows.Forms.Timer
$elapsedTimer.Interval = 1000
$elapsedTimer.Add_Tick({
    if ($script:opStartTime) {
        $elapsed = (Get-Date) - $script:opStartTime
        $mm = [math]::Floor($elapsed.TotalMinutes)
        $ss = $elapsed.Seconds
        $elapsedLabel.Text = "Elapsed: {0}:{1:D2}" -f $mm, $ss
    }
})

# --- Button Definitions and Logic ---

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "Cancel"
$cancelButton.Location = New-Object System.Drawing.Point(20, 390)
$cancelButton.Size = New-Object System.Drawing.Size(90, 30)
$cancelButton.Enabled = $false
$form.Controls.Add($cancelButton)

$prepButton = New-Object System.Windows.Forms.Button
$prepButton.Text = "USB-PREP"
$prepButton.Location = New-Object System.Drawing.Point(130, 390)
$prepButton.Size = New-Object System.Drawing.Size(100, 30)
$form.Controls.Add($prepButton)

$createButton = New-Object System.Windows.Forms.Button
$createButton.Text = "Create ReCoveryUSB"
$createButton.Location = New-Object System.Drawing.Point(250, 390)
$createButton.Size = New-Object System.Drawing.Size(130, 30)
$form.Controls.Add($createButton)

$cancelButton.Add_Click({
    $script:cancelRequested = $true
    $cancelButton.Enabled = $false
    Log-ToAll -message "--- Cancellation requested. Waiting for current step to finish... ---" -textBox $outputBox -logFile $ScriptLogFile
})

$prepButton.Add_Click({
    $usbDrive = $comboBox.SelectedItem
    if (-Not $usbDrive) {
        [System.Windows.Forms.MessageBox]::Show($form, "Please select a USB drive to prepare.", "Selection Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $outputBox.Clear()
    Log-ToAll -message "Initiating USB drive preparation..." -textBox $outputBox -logFile $ScriptLogFile

    $cleanupSuccess = Clear-USBDrive -DriveLetterWithColon $usbDrive -parentForm $form -outputBox $outputBox -logFile $ScriptLogFile

    if ($cleanupSuccess) {
        Log-ToAll -message "USB-PREP task completed successfully." -textBox $outputBox -logFile $ScriptLogFile
        [System.Windows.Forms.MessageBox]::Show($form, "USB Prep Complete. The application will now close.`n`nPlease re-open it to use the 'Create ReCoveryUSB' button.", "Prep Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        $form.Close()
    } else {
        Log-ToAll -message "USB-PREP task failed or was cancelled by the user." -textBox $outputBox -logFile $ScriptLogFile
        [System.Windows.Forms.MessageBox]::Show($form, "USB Drive preparation failed or was cancelled.", "Prep Incomplete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
})


$createButton.Add_Click({
    $usbDrive = $comboBox.SelectedItem
    if (-Not $usbDrive) {
        [System.Windows.Forms.MessageBox]::Show($form, "Please select a USB drive.", "Selection Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $confirmResult = [System.Windows.Forms.MessageBox]::Show($form, "This process will ERASE all data on '$usbDrive'.`n`nFor stubborn drives that fail, use the 'USB-PREP' button first.`n`nDo you want to continue?", "Confirm WinPE Creation", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirmResult -eq [System.Windows.Forms.DialogResult]::No) {
        Log-ToAll -message "Operation cancelled by user." -textBox $outputBox -logFile $ScriptLogFile
        return
    }

    $outputBox.Clear()
    $script:cancelRequested = $false
    $script:opStartTime = Get-Date
    $elapsedTimer.Start()
    Log-ToAll -message "Initiating WinPE creation script..." -textBox $outputBox -logFile $ScriptLogFile

    Run-WinPECreation -usbDrive $usbDrive -parentForm $form -outputBox $outputBox -progressBar $progressBar -createButton $createButton -prepButton $prepButton -cancelButton $cancelButton -logFile $ScriptLogFile

    $elapsedTimer.Stop()
    $cancelButton.Enabled = $false
    $elapsedLabel.Text = ""
    Log-ToAll -message "Script execution attempt completed." -textBox $outputBox -logFile $ScriptLogFile
})

# Show the form
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()