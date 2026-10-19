# Prints LabVIEW's own log files to the console.
# Run by build jobs only when an earlier task failed.
# If LabVIEW crashes, G-CLI only reports "IO Error When Reading Messages From LabVIEW",
# so the reason for the crash is only available from these files.
$ErrorActionPreference = 'Continue'
# Otherwise Windows PowerShell writes progress records to stderr as CLIXML.
$ProgressPreference = 'SilentlyContinue'
$maxLines = 400
# Ignore anything significantly older than the job (whose timeout is 15 minutes).
$since = (Get-Date).AddHours(-2)

function Show-LogFile($file) {
    Write-Output ''
    Write-Output ('===== {0} ({1} bytes, modified {2:yyyy-MM-dd HH:mm:ss}) =====' -f $file.FullName, $file.Length, $file.LastWriteTime)
    # Skip the initial lines - these don't help describe the failure.
    # Keep the last $maxLines lines.
    Get-Content -LiteralPath $file.FullName |
        Where-Object { $_ -notlike 'starting LabVIEW Execution System*' } |
        Select-Object -Last $maxLines
}

# Copies a file into $copyDir as $name. A failed copy only prints a warning.
function Copy-ToArtifactDir($file, $name) {
    $target = Join-Path $copyDir $name
    try {
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force -ErrorAction Stop
        Write-Output ('Copied {0} ({1} bytes) to {2}' -f $file.FullName, $file.Length, $target)
        $script:copied++
    } catch {
        Write-Output ('WARNING: Could not copy {0}: {1}' -f $file.FullName, $_)
    }
}

Write-Output '##### A task failed - printing LabVIEW log files #####'

$running = Get-Process -Name 'LabVIEW' -ErrorAction SilentlyContinue
if ($running) {
    Write-Output ('LabVIEW is still running (PID {0}) - it may have hung rather than crashed.' -f ($running.Id -join ', '))
} else {
    Write-Output 'LabVIEW is not running.'
}

# LabVIEW_<bitness>_<version>_<user>_cur.txt (current/last session), _log.txt (previous session),
# LabVIEW_BrokenVILog_*.txt, and lvlog*.txt from older LabVIEW versions.
$tempLogs = @(Get-ChildItem -LiteralPath $env:TEMP -File -Filter '*.txt' -ErrorAction SilentlyContinue |
    Where-Object { ($_.Name -like 'LabVIEW_*' -or $_.Name -like 'lvlog*') -and $_.LastWriteTime -ge $since } |
    Sort-Object LastWriteTime)
if ($tempLogs.Count -eq 0) {
    Write-Output "No LabVIEW log files written in the last 2 hours found in $env:TEMP"
}
foreach ($file in $tempLogs) {
    Show-LogFile $file
}

# Crash reports: LVInternalReports\LabVIEW\<version>\<GUID>\ holding a .dmp and text logs.
$documents = [Environment]::GetFolderPath('MyDocuments')
if (-not $documents) {
    $documents = Join-Path $env:USERPROFILE 'Documents'
}
$reportDir = Join-Path $documents 'LabVIEW Data\LVInternalReports'
if (Test-Path -LiteralPath $reportDir) {
    $reports = @(Get-ChildItem -LiteralPath $reportDir -Recurse -File | Where-Object { $_.LastWriteTime -ge $since } | Sort-Object LastWriteTime)
    Write-Output ''
    Write-Output ('===== {0} files written in the last 2 hours in {1} =====' -f $reports.Count, $reportDir)
    foreach ($file in $reports) {
        Write-Output ('{0:yyyy-MM-dd HH:mm:ss}  {1,10}  {2}' -f $file.LastWriteTime, $file.Length, $file.FullName)
    }
    foreach ($file in ($reports | Where-Object { $_.Extension -in '.txt', '.log' })) {
        Show-LogFile $file
    }
} else {
    Write-Output "No LabVIEW crash reports found ($reportDir does not exist)"
}

Write-Output '##### End of LabVIEW log files #####'

# Copy the crash dumps and the TEMP logs into the job's working directory so that a
# GoCD artifact rule can upload them. The folder and its README.txt are always created,
# so the artifact rule always matches something.
Write-Output ''
Write-Output '##### Copying LabVIEW crash dumps and log files #####'
$copyDir = Join-Path (Get-Location).ProviderPath 'LabVIEW-Crash-Dumps'
$copied = 0
try {
    New-Item -ItemType Directory -Path $copyDir -Force -ErrorAction Stop | Out-Null
} catch {
    Write-Output ('WARNING: Could not create {0}: {1}' -f $copyDir, $_)
}

$dumps = @()
if (Test-Path -LiteralPath $reportDir) {
    $dumps = @(Get-ChildItem -LiteralPath $reportDir -Recurse -File -Filter '*.dmp' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $since } |
        Sort-Object LastWriteTime)
}
foreach ($file in $dumps) {
    # Prefix the session GUID (the parent folder) so dumps from different sessions don't collide.
    Copy-ToArtifactDir $file ('{0}_{1}' -f $file.Directory.Name, $file.Name)
}
foreach ($file in $tempLogs) {
    Copy-ToArtifactDir $file $file.Name
}

$total = $dumps.Count + $tempLogs.Count
$readme = @(
    ('Copied {0} of {1} files: {2} LabVIEW crash dumps (*.dmp) from {3} and {4} log files from {5}.' -f $copied, $total, $dumps.Count, $reportDir, $tempLogs.Count, $env:TEMP),
    ('Only files written since {0:yyyy-MM-dd HH:mm:ss} on {1} were included.' -f $since, $env:COMPUTERNAME),
    'Crash dump names are prefixed with the session GUID folder they were found in.'
)
try {
    Set-Content -LiteralPath (Join-Path $copyDir 'README.txt') -Value $readme -ErrorAction Stop
} catch {
    Write-Output ('WARNING: Could not write README.txt in {0}: {1}' -f $copyDir, $_)
}
Write-Output ('Copied {0} of {1} files to {2}' -f $copied, $total, $copyDir)
exit 0
