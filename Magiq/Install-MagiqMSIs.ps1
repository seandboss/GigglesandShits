#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Silently installs Magiq MSI packages from a UNC network share.

.DESCRIPTION
    Installs MAGIQ.Setup.Word.msi, MAGIQ.Setup.Outlook.msi, and MAGIQ.Setup.Excel.msi
    silently from a specified UNC path with full error handling and logging.

.PARAMETER SourcePath
    UNC path to the folder containing the MSI files.
    Example: \\server\share\Magiq

.PARAMETER LogPath
    Local path where install logs will be written. Defaults to C:\Windows\Logs\Magiq.

.EXAMPLE
    .\Install-MagiqMSIs.ps1 -SourcePath "\\kdcsvfap01\$softwareinstalls\Magiq"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SourcePath = "\\kdcsvfap01\$softwareinstalls\Magiq",

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Windows\Logs\Magiq"
)

$MSIs = @(
    "MAGIQ.Setup.Word.msi",
    "MAGIQ.Setup.Outlook.msi",
    "MAGIQ.Setup.Excel.msi"
)

$MsiExec = "$env:SystemRoot\System32\msiexec.exe"

# Ensure log directory exists
if (-not (Test-Path $LogPath)) {
    try {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    catch {
        Write-Error "Failed to create log directory '$LogPath': $_"
        exit 1
    }
}

# Verify UNC path is reachable
if (-not (Test-Path $SourcePath)) {
    Write-Error "Source path '$SourcePath' is not accessible. Verify the UNC path and your network connection."
    exit 1
}

$overallSuccess = $true

foreach ($msi in $MSIs) {
    $msiPath = Join-Path $SourcePath $msi
    $logFile = Join-Path $LogPath "$([System.IO.Path]::GetFileNameWithoutExtension($msi))_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    Write-Host "Installing: $msi" -ForegroundColor Cyan

    # Verify MSI exists on share
    if (-not (Test-Path $msiPath)) {
        Write-Warning "  MSI not found: $msiPath — skipping."
        $overallSuccess = $false
        continue
    }

    $arguments = @(
        "/i", "`"$msiPath`"",
        "/qn",
        "/norestart",
        "/l*v", "`"$logFile`""
    )

    try {
        $process = Start-Process -FilePath $MsiExec -ArgumentList $arguments -Wait -PassThru -ErrorAction Stop

        switch ($process.ExitCode) {
            0       { Write-Host "  SUCCESS: $msi installed." -ForegroundColor Green }
            1641    { Write-Host "  SUCCESS: $msi installed (reboot initiated)." -ForegroundColor Green }
            3010    { Write-Host "  SUCCESS: $msi installed (reboot required to complete)." -ForegroundColor Yellow }
            1603    { Write-Warning "  FAILED ($($process.ExitCode)): Fatal error during installation of $msi. See log: $logFile"; $overallSuccess = $false }
            1618    { Write-Warning "  FAILED ($($process.ExitCode)): Another installation is in progress. Retry after current install completes."; $overallSuccess = $false }
            1638    { Write-Host "  SKIPPED: A newer version of $msi is already installed." -ForegroundColor Yellow }
            1642    { Write-Warning "  FAILED ($($process.ExitCode)): Patch cannot be applied — target product not found for $msi."; $overallSuccess = $false }
            default { Write-Warning "  FAILED ($($process.ExitCode)): Unexpected exit code for $msi. See log: $logFile"; $overallSuccess = $false }
        }
    }
    catch {
        Write-Error "  ERROR launching installer for $msi`: $_"
        $overallSuccess = $false
    }

    Write-Host "  Log: $logFile"
}

Write-Host ""
if ($overallSuccess) {
    Write-Host "All installations completed successfully." -ForegroundColor Green
    exit 0
}
else {
    Write-Warning "One or more installations failed or were skipped. Review the logs at '$LogPath'."
    exit 1
}
