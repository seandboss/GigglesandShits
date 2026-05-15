param(
    [string]$CID = 'DC5C455C199D4ECE8356A30510DA3C61-4D',
    [string]$ProvisioningToken = 'G0ldmemb3r!',
    [string]$SensorShare = 'c:\temp\WindowsSensor.exe',
    [string]$TempDir = 'C:\Temp',
    [string]$ServiceName = 'CSFalconService',
    [string]$Uninstaller = ''
)


$repoApiUrl = "https://api.github.com/repos/seandboss/GigglesandShits/contents"
$outputFile = "C:\temp\crowdstrike.zip"
$sourceDir = "C:\temp"
$UnistallerLocal = 'c:\temp\CsUninstallTool.exe'

# 1. Ensure destination directory exists
if (-not (Test-Path $sourceDir)) {
    New-Item -ItemType Directory -Path $sourceDir | Out-Null
}

# 2. Discover part files from GitHub
Write-Host "Fetching file list from GitHub..." -ForegroundColor Cyan
try {
    $contents = Invoke-RestMethod -Uri $repoApiUrl -Headers @{
        "User-Agent"          = "PowerShell"
        "Accept"              = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
} catch {
    Write-Error "Failed to fetch repository contents: $_"
    return
}

$partFiles = $contents |
    Where-Object { $_.type -eq "file" -and $_.download_url -and $_.name -match "^part_(\d+)\.dat$" } |
    Sort-Object { [int]([regex]::Match($_.name, "^part_(\d+)\.dat$").Groups[1].Value) }

if ($partFiles.Count -eq 0) {
    Write-Error "No part_*.dat files found in the GitHub repository."
    return
}

# 3. Download each part if missing or different from GitHub version
function Get-GitBlobSha1 {
    param([string]$FilePath)
    $fileInfo = Get-Item $FilePath
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes("blob $($fileInfo.Length)`0")
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $sha1.TransformBlock($headerBytes, 0, $headerBytes.Length, $null, 0) | Out-Null
        $buffer = New-Object byte[] 81920
        $stream = [System.IO.File]::OpenRead($FilePath)
        try {
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $sha1.TransformBlock($buffer, 0, $read, $null, 0) | Out-Null
            }
            $sha1.TransformFinalBlock([byte[]]::new(0), 0, 0) | Out-Null
        } finally {
            $stream.Dispose()
        }
        return ($sha1.Hash | ForEach-Object { $_.ToString("x2") }) -join ""
    } finally {
        $sha1.Dispose()
    }
}

$downloadedParts = @()
foreach ($file in $partFiles) {
    $destPath = Join-Path $sourceDir $file.name
    $needsDownload = $true

    if (Test-Path $destPath) {
        $localSha = Get-GitBlobSha1 -FilePath $destPath
        if ($localSha -eq $file.sha) {
            Write-Host "Skipping $($file.name) (already up to date)." -ForegroundColor Yellow
            $needsDownload = $false
        } else {
            Write-Host "Re-downloading $($file.name) (local file differs from GitHub)..." -ForegroundColor Cyan
        }
    } else {
        Write-Host "Downloading $($file.name)..." -ForegroundColor Cyan
    }

    if ($needsDownload) {
        try {
            Invoke-WebRequest -Uri $file.download_url -OutFile $destPath -ErrorAction Stop
        } catch {
            Write-Error "Failed to download $($file.name): $_"
            return
        }
        $downloadedSha = Get-GitBlobSha1 -FilePath $destPath
        if ($downloadedSha -ne $file.sha) {
            Write-Error "SHA mismatch after downloading $($file.name). Expected $($file.sha), got $downloadedSha."
            return
        }
    }

    $downloadedParts += Get-Item $destPath
}

# 4. Combine only the downloaded parts into a single zip file
Write-Host "Combining parts into $outputFile..." -ForegroundColor Cyan
try {
    $fileStream = [System.IO.File]::Create($outputFile)

    foreach ($part in $downloadedParts) {
        Write-Host "Processing $($part.Name)..." -ForegroundColor Cyan
        $inputStream = [System.IO.File]::OpenRead($part.FullName)
        try {
            $inputStream.CopyTo($fileStream)
        } finally {
            $inputStream.Close()
        }
    }
} finally {
    if ($fileStream) {
        $fileStream.Close()
    }
}

# 5. Extract the zip, overwriting any existing files
Write-Host "Extracting to $sourceDir..." -ForegroundColor Cyan
Expand-Archive -Path $outputFile -DestinationPath $sourceDir -Force
Write-Host "Success! Files extracted to: $sourceDir" -ForegroundColor Green

$ErrorActionPreference = 'Stop'
$SensorLocal = Join-Path -Path $TempDir -ChildPath 'WindowsSensor.exe'

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

try {
    # Check current state but always proceed with install/update
    Write-Log "Checking for existing CrowdStrike installation..."
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Write-Log "CrowdStrike already installed. Proceeding with reinstall..." -Level 'Warning'
    } else {
        Write-Log "CrowdStrike not installed. Proceeding with install..."
    }

    # Create temp directory if it doesn't exist
    if (-not (Test-Path -Path $TempDir)) {
        Write-Log "Creating temp directory: $TempDir"
        New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    }

    if (-not (Test-Path -Path $SensorLocal)) {
        throw "Installer not found at expected path: $SensorLocal"
    }

    # Install/reinstall CrowdStrike Falcon
    Write-Log "Installing CrowdStrike Falcon Sensor..."
    $installArgs = "/install /quiet /norestart CID=$CID"
    if ($ProvisioningToken) {
        $installArgs += " PW=$ProvisioningToken"
    }

    $process = Start-Process -FilePath $SensorLocal -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -eq 0) {
        Write-Log "CrowdStrike Falcon installed successfully." -Level 'Success'
        Start-Sleep -Seconds 5
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            Write-Log "Service '$ServiceName' verified and running." -Level 'Success'
        } else {
            Write-Log "Service not detected or not running. May require reboot." -Level 'Warning'
        }
    } elseif ($process.ExitCode -eq 106) {
        Write-Log "Installation failed with exit code: $($process.ExitCode). Already Installed" -Level 'Warning'
    } else {
        Write-Log "Installation failed with exit code: $($process.ExitCode)" -Level 'Error'
    }


    # Wait before uninstalling
    Write-Log "Waiting 5 minutes before uninstall..."
    Start-Sleep -Seconds 300

    # Determine uninstaller path
    if ($Uninstaller -and (Test-Path $Uninstaller)) {
        $uninstallPath = $Uninstaller
    } elseif (Test-Path $UnistallerLocal) {
        $uninstallPath = $UnistallerLocal
    } else {
        Write-Log "CsUninstallTool.exe not found at '$Uninstaller' or '$UnistallerLocal'." -Level 'Error'
    }

    Write-Log "Executing silent uninstall from: $uninstallPath"
    $process = Start-Process -FilePath $uninstallPath -ArgumentList "MAINTENANCE_TOKEN=48f6fb18f0970d45ec0ce5c30768c38f44034a06e306ea8bcc5914c432093b75 /quiet" -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -eq 0) {
        Write-Log "CrowdStrike uninstalled successfully." -Level 'Success'
    } else {
        Write-Log "Uninstaller failed with exit code: $($process.ExitCode)" -Level 'Error'
    }

} catch {
    Write-Log "ERROR: $_" -Level 'Error'
    return
}

Write-Log "Script completed successfully." -Level 'Success'
