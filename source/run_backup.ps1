
# this scripts takes a single argument "fullRepoPath"
param (
    [Parameter(Mandatory=$true)] [string] $fullRepoPath
)

Add-Type -AssemblyName PresentationCore,PresentationFramework

# load variables
. "$PSScriptRoot\restic-env.ps1"

function Get-Timestamp {
	[int] (Get-Date -UFormat %s).Replace(",", ".")
}

Set-Location $fullRepoPath

# set source folder here!
# TODO: provide way to input source folder
$sourceFolder = ""



Write-Host "Opening repository `"$fullRepoPath`""
$passwordSecure = Read-Host "Password" -AsSecureString

# Create a "password pointer"
$PwdPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordSecure)
# Get the plain text version of the password
$passwordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($PwdPointer)
# Free the pointer
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($PwdPointer)

$Env:RESTIC_REPOSITORY = $fullRepoPath
$Env:RESTIC_PASSWORD = $passwordPlain


Write-Host "`n--- Starting Backup ---"
restic backup $sourceFolder
if (-not($?)) {
	# error occurred
	$ButtonType = [System.Windows.MessageBoxButton]::YesNo
	$MessageIcon = [System.Windows.MessageBoxImage]::Warning
	$MessageBody = "An error occurred while performing the backup. Please check the console window.`n`nShould this backup be counted as successful?"	
	$MessageTitle = "Restic Backup - Error"
	$Result = [System.Windows.MessageBox]::Show($MessageBody,$MessageTitle,$ButtonType,$MessageIcon)
	$success = $Result -eq "Yes"
} else {
	$success = $true
}

if ($success) {
	$configFolder = "$Env:AppData\restic-backup"
	Set-Content -path "$configFolder\last_backup.txt" -value (Get-Timestamp)
}


Write-Host "`n--- Backup finished, starting cleanup of old backups ---"
restic forget --prune --keep-daily $KEEP_DAILY --keep-weekly $KEEP_WEEKLY --keep-monthly $KEEP_MONTHLY --keep-yearly $KEEP_YEARLY
if (!($?)) {
	# error occurred
	$ButtonType = [System.Windows.MessageBoxButton]::OK
	$MessageIcon = [System.Windows.MessageBoxImage]::Warning
	$MessageBody = "An error occurred during clean-up"
	$MessageTitle = "Restic Backup - Error"
	$Result = [System.Windows.MessageBox]::Show($MessageBody,$MessageTitle,$ButtonType,$MessageIcon)
}


Write-Host "`n--- Old backups deleted, starting repository check ---"
restic check
if (!($?)) {
	# error occurred
	$ButtonType = [System.Windows.MessageBoxButton]::OK
	$MessageIcon = [System.Windows.MessageBoxImage]::Warning
	$MessageBody = "An error occurred while checking the repo"
	$MessageTitle = "Restic Backup - Error"
	$Result = [System.Windows.MessageBox]::Show($MessageBody,$MessageTitle,$ButtonType,$MessageIcon)
}

