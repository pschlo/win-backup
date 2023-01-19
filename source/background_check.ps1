Add-Type -AssemblyName PresentationCore,PresentationFramework
[reflection.assembly]::loadwithpartialname('System.Windows.Forms')
[reflection.assembly]::loadwithpartialname('System.Drawing')

# load variables
. "$PSScriptRoot\restic-env.ps1"

# store the last oldBackupWarning object in a global variable so that there is only one at all times
$Global:oldBackupWarning = New-Object system.windows.forms.notifyicon
# store when the last oldBackupWarning was done
$Global:lastWarnOldBackup = 0


$configFolder = "$Env:AppData\restic-backup"
# create if does not exist
if (!(Test-Path $configFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $configFolder
}

if (!(Test-Path "$configFolder\last_backup.txt")) {
   New-Item -path "$configFolder" -name last_backup.txt -type "file" -value "0"
}



function Get-Timestamp {
	[int] (Get-Date -UFormat %s).Replace(",", ".")
}

function hasAccess {
	param ($fullRepoPath)
	Test-Path $fullRepoPath
}

function getMatchingPartitions {
	Get-Partition | Where-Object {$_.UniqueId -eq $PARTITION_ID}
}

# check if the timedelta to the last backup is greater than max backup age
function isTimeBackup {
	$lastBackup = Get-Content "$Env:AppData\restic-backup\last_backup.txt"
	((Get-Timestamp) - $lastBackup) -ge $MAX_BACKUP_AGE
}

function isTimeWarnOldBackup {
	((Get-Timestamp) - $Global:lastWarnOldBackup) -ge $WARN_INTERVAL
}

function warnOldBackup {
	$Global:oldBackupWarning.Dispose()
	
	$notify = New-Object system.windows.forms.notifyicon
	$path = Get-Process -id $pid | Select-Object -ExpandProperty Path
	$notify.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
	$notify.Visible = $true
	$notify.BalloonTipIcon = [system.windows.forms.tooltipicon]::Info
	$notify.BalloonTipTitle = "Old Restic Backups"
	$notify.BalloonTipText = "Please create a new backup"
	$notify.ShowBalloonTip(0)
	
	$Global:oldBackupWarning = $notify
	$Global:lastWarnOldBackup = Get-Timestamp
}

function warnNoAccess {
	# open popup message
	Write-Host "warn no access"
	$ButtonType = [System.Windows.MessageBoxButton]::OK
	$MessageIcon = [System.Windows.MessageBoxImage]::Warning
	$MessageBody = "The backup drive was detected but the restic repo could not be accessed. Is the drive encrypted or the repo missing?"	
	$MessageTitle = "Restic Backup - Timeout"
	$Result = [System.Windows.MessageBox]::Show($MessageBody,$MessageTitle,$ButtonType,$MessageIcon)
}

function askBackup {
	# popup message
	$ButtonType = [System.Windows.MessageBoxButton]::YesNo
	$MessageIcon = [System.Windows.MessageBoxImage]::Information
	$MessageBody = "Backup drive detected. Perform backup now?"	
	$MessageTitle = "Restic Backup"
	$Result = [System.Windows.MessageBox]::Show($MessageBody,$MessageTitle,$ButtonType,$MessageIcon)

	if ($Result -ne "Yes") {
		# do not run backup
		return $false
	}

	# run restic backup
	Write-Host "running restic backup"
	Start-Process powershell -ArgumentList "-NoExit -NoLogo -File `"$PSScriptRoot\run_backup.ps1`" -fullRepoPath `"$fullRepoPath`""
	return $true
}



$tryBackingUp = $true
$warnNoAccess = $true
$isConnected = $false  # set to false so that device is recognized as newly connected in the first iteration
$delay = 0  # execute first iteration without any delay

while ($true) {
	Start-Sleep $delay
	$delay = 5
	
	$isConnectedOld = $isConnected
	
	if (-not(isTimeBackup)) {
		continue
	}
	
	# time for backup!
	
	# The "@" guarantees that the result is always an array, even if Where-Object only matches one or zero objects
	# see https://stackoverflow.com/q/11107428
	$parts = @(getMatchingPartitions)
	$isConnected = $parts.Length -eq 1
	
	# detect insertion
	if (-not($isConnectedOld) -and $isConnected) {
		$insertionTime = Get-Timestamp
		$tryBackingUp = $true
		$warnNoAccess = $true
	}

	if (-not($tryBackingUp) -or -not($isConnected)) {
		if (isTimeWarnOldBackup) {
			Write-Host warnOldBackup
			warnOldBackup
		}
		continue
	}
	
	$mountLetter = $parts[0].DriveLetter
	$fullRepoPath = $mountLetter + ":/" + $REL_REPO_PATH
	
	Write-Host "Trying to access repo"
	if (-not(hasAccess($fullRepoPath))) {
		# warning should appear max. once for each time the device gets connected
		if ($warnNoAccess -and (((Get-Timestamp) - $insertionTime) -ge $WARN_NO_ACCESS_AFTER)) {
			warnNoAccess
			$warnNoAccess = $false
		}
		continue
	}
	
	# time for backup, trying to back up, connected and having access
	Write-Host "Ready to run backup"
	askBackup
	$tryBackingUp = $false

}

