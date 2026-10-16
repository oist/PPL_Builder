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
exit 0
