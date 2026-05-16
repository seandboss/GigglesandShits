$acctkey   = 'be8f267418123fcab86a875ea890aa88'
$orgkey    = $env:huntressorganizationkey
$zipDest   = "C:\temp\Huntress.zip"
$extractDir = "C:\temp\huntress"

function Write-Log {
    param([string]$Message, [string]$Level = 'Info')
    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'White' }
    }
    Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] $Message" -ForegroundColor $color
}

# 1. Verify zip exists
if (-not (Test-Path $zipDest)) {
    Write-Log "huntress.zip not found at $zipDest. Run Download-Huntress.ps1 first." -Level 'Error'
    exit 1
}

# 2. Clear the extract directory before extraction
if (Test-Path $extractDir) {
    Write-Log "Clearing existing contents of $extractDir..."
    Remove-Item -Path $extractDir -Recurse -Force
}
New-Item -ItemType Directory -Path $extractDir | Out-Null

# 3. Extract the zip
Write-Log "Extracting huntress.zip to $extractDir..."
Expand-Archive -Path $zipDest -DestinationPath $extractDir -Force
Write-Log "Extraction complete." -Level 'Success'

# 4. Find the installer exe (name may change with version)
$installer = Get-ChildItem -Path $extractDir -Filter "*.exe" -File | Select-Object -First 1
if (-not $installer) {
    Write-Log "No .exe found in $extractDir after extraction." -Level 'Error'
    exit 1
}
Write-Log "Found installer: $($installer.Name)"

# 5. Run the installer
$installArgs = "/ACCT_KEY=`"$acctkey`" /ORG_KEY=`"$orgkey`" /S"
Write-Log "Running installer: $($installer.FullName) $installArgs"

$process = Start-Process -FilePath $installer.FullName -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

if ($process.ExitCode -eq 0) {
    Write-Log "Huntress installed successfully." -Level 'Success'
} else {
    Write-Log "Installer exited with code: $($process.ExitCode)" -Level 'Error'
    exit $process.ExitCode
}
