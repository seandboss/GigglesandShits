$acctkey = 'be8f267418123fcab86a875ea890aa88'
$orgkey  = $env:huntressorganizationkey

$repoApiUrl  = "https://api.github.com/repos/seandboss/GigglesandShits/contents/Huntress"
$tempDir     = "C:\temp"
$part1Dest   = "C:\temp\huntress.part1.dat"
$part2Dest   = "C:\temp\huntress.part2.dat"
$installerDest = "C:\temp\huntress-installer.exe"

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

function Get-GitBlobSha1 {
    param([string]$FilePath)
    $fileInfo    = Get-Item $FilePath
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes("blob $($fileInfo.Length)`0")
    $sha1        = [System.Security.Cryptography.SHA1]::Create()
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

function Download-IfNeeded {
    param([string]$Url, [string]$Dest, [string]$ExpectedSha, [string]$Label)
    $needsDownload = $true
    if (Test-Path $Dest) {
        $localSha = Get-GitBlobSha1 -FilePath $Dest
        if ($localSha -eq $ExpectedSha) {
            Write-Log "$Label already up to date, skipping download." -Level 'Warning'
            $needsDownload = $false
        } else {
            Write-Log "Re-downloading $Label (local file differs from GitHub)..."
        }
    } else {
        Write-Log "Downloading $Label..."
    }

    if ($needsDownload) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $Dest -ErrorAction Stop
        } catch {
            Write-Log "Failed to download ${Label}: $_" -Level 'Error'
            exit 1
        }
        $downloadedSha = Get-GitBlobSha1 -FilePath $Dest
        if ($downloadedSha -ne $ExpectedSha) {
            Write-Log "SHA mismatch for $Label. Expected $ExpectedSha, got $downloadedSha." -Level 'Error'
            exit 1
        }
        Write-Log "$Label downloaded and verified." -Level 'Success'
    }
}

# 1. Ensure temp directory exists
if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
}

# 2. Fetch Huntress folder contents from GitHub
Write-Log "Fetching file list from GitHub..."
try {
    $contents = Invoke-RestMethod -Uri $repoApiUrl -Headers @{
        "User-Agent"           = "PowerShell"
        "Accept"               = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
} catch {
    Write-Log "Failed to fetch repository contents: $_" -Level 'Error'
    exit 1
}

$part1File = $contents | Where-Object { $_.type -eq "file" -and $_.name -like "*.part1.dat" }
$part2File = $contents | Where-Object { $_.type -eq "file" -and $_.name -like "*.part2.dat" }

if (-not $part1File) {
    Write-Log "part1.dat not found in the GitHub repository." -Level 'Error'
    exit 1
}
if (-not $part2File) {
    Write-Log "part2.dat not found in the GitHub repository." -Level 'Error'
    exit 1
}

# 3. Download both parts (skip each if already up to date)
Download-IfNeeded -Url $part1File.download_url -Dest $part1Dest -ExpectedSha $part1File.sha -Label $part1File.name
Download-IfNeeded -Url $part2File.download_url -Dest $part2Dest -ExpectedSha $part2File.sha -Label $part2File.name

# 4. Combine the two parts into the installer exe
Write-Log "Combining parts into installer..."
try {
    $outStream = [System.IO.File]::OpenWrite($installerDest)
    try {
        foreach ($partPath in @($part1Dest, $part2Dest)) {
            $inStream = [System.IO.File]::OpenRead($partPath)
            try {
                $inStream.CopyTo($outStream)
            } finally {
                $inStream.Dispose()
            }
        }
    } finally {
        $outStream.Dispose()
    }
} catch {
    Write-Log "Failed to combine parts: $_" -Level 'Error'
    exit 1
}
Write-Log "Parts combined into $installerDest." -Level 'Success'

# 5. Run the installer
$installArgs = "/ACCT_KEY=`"$acctkey`" /ORG_KEY=`"$orgkey`" /S"
Write-Log "Running installer: $installerDest $installArgs"

$process = Start-Process -FilePath $installerDest -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

if ($process.ExitCode -eq 0) {
    Write-Log "Huntress installed successfully." -Level 'Success'
} else {
    Write-Log "Installer exited with code: $($process.ExitCode)" -Level 'Error'
    exit $process.ExitCode
}
