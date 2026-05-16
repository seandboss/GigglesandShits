$repoApiUrl = "https://api.github.com/repos/seandboss/GigglesandShits/contents"
$zipDest    = "C:\temp\Huntress.zip"
$tempDir    = "C:\temp"

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

# 1. Ensure temp directory exists
if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
}

# 2. Fetch repo contents from GitHub
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

$huntressFile = $contents | Where-Object { $_.type -eq "file" -and $_.name -eq "huntress.zip" }
if (-not $huntressFile) {
    Write-Log "huntress.zip not found in the GitHub repository." -Level 'Error'
    exit 1
}

# 3. Download huntress.zip (skip if already up to date)
$needsDownload = $true
if (Test-Path $zipDest) {
    $localSha = Get-GitBlobSha1 -FilePath $zipDest
    if ($localSha -eq $huntressFile.sha) {
        Write-Log "huntress.zip already up to date, skipping download." -Level 'Warning'
        $needsDownload = $false
    } else {
        Write-Log "Re-downloading huntress.zip (local file differs from GitHub)..."
    }
} else {
    Write-Log "Downloading huntress.zip..."
}

if ($needsDownload) {
    try {
        Invoke-WebRequest -Uri $huntressFile.download_url -OutFile $zipDest -ErrorAction Stop
    } catch {
        Write-Log "Failed to download huntress.zip: $_" -Level 'Error'
        exit 1
    }
    $downloadedSha = Get-GitBlobSha1 -FilePath $zipDest
    if ($downloadedSha -ne $huntressFile.sha) {
        Write-Log "SHA mismatch after downloading huntress.zip. Expected $($huntressFile.sha), got $downloadedSha." -Level 'Error'
        exit 1
    }
    Write-Log "huntress.zip downloaded and verified." -Level 'Success'
}

Write-Log "Download complete. Run Install-Huntress-System.ps1 as SYSTEM to continue." -Level 'Success'
