$ErrorActionPreference = 'Continue'

# ============================================================
#  NapCat guard  (created by Cyrene)
#
#  Job: keep the QQ bot online. When NapCat / QQ is really gone,
#  relaunch it through run-napcat.cmd (which passes the account
#  number, so it goes through QUICK LOGIN instead of a QR code).
#
#  Health rule (rewritten 2026-09-16):
#    healthy = NapCatWinBootMain.exe is alive
#              AND there is an ESTABLISHED link on 6199
#
#  Do NOT look for "-q <uin>" inside the QQ command line: the QQ that
#  NapCat launches carries only "--enable-logging", so that check never
#  matched and the guard kept "restarting" a perfectly healthy NapCat.
#
#  If NapCat is alive but not linked yet, it is most likely waiting for
#  a QR scan. That state is left alone for $StuckMin minutes so the
#  user has time to scan, instead of the QR being regenerated forever.
#
#  Silent when everything is fine (nothing is written in that case).
# ============================================================

$Root        = 'D:\Astrbot'
$LogFile     = Join-Path $Root 'napcat-guard.log'
$StampFile   = Join-Path $Root '_tool\.napcat-restart-stamp'
$StuckFile   = Join-Path $Root '_tool\.napcat-stuck-stamp'
$LauncherCmd = 'cmd /c call "D:\Astrbot\run-napcat.cmd"'
$QQNumber    = '3964589920'
$CooldownMin = 5      # minimum minutes between two relaunches
$StuckMin    = 20     # grace period while waiting for a login
$MaxLogBytes = 2MB

function Write-Log([string]$Message) {
    $line = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Rotate-Log {
    if (Test-Path $LogFile) {
        $fi = Get-Item $LogFile
        if ($fi.Length -gt $MaxLogBytes) {
            Move-Item -Path $LogFile -Destination ($LogFile + '.old') -Force
        }
    }
}

function Get-NapCatState {
    $state = [pscustomobject]@{
        Boot   = $false
        Linked = $false
    }

    if (@(Get-Process -Name 'NapCatWinBootMain' -ErrorAction SilentlyContinue).Count -gt 0) {
        $state.Boot = $true
    }

    foreach ($line in @(netstat -ano | Select-String ':6199')) {
        if ($line.ToString() -match 'ESTABLISHED') { $state.Linked = $true; break }
    }

    return $state
}

function Stop-NapCat {
    $killed = 0

    # 1) the launcher and everything it spawned (QQ included)
    foreach ($b in @(Get-Process -Name 'NapCatWinBootMain' -ErrorAction SilentlyContinue)) {
        & taskkill /PID $b.Id /T /F 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $killed++ }
    }
    Start-Sleep -Seconds 2

    # 2) orphaned QQ left behind by a dead launcher.
    #    NapCat's QQ always carries "--enable-logging"; a QQ the user
    #    opened by hand does not, so their own client is left alone.
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='QQ.exe'" -ErrorAction SilentlyContinue)) {
        if ($p.CommandLine -and $p.CommandLine -like '*--enable-logging*') {
            & taskkill /PID $p.ProcessId /T /F 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { $killed++ }
        }
    }

    return $killed
}

function Restart-NapCat([string]$ReasonText) {
    Write-Log ('UNHEALTHY: ' + $ReasonText + ' -> restarting NapCat (quick login as ' + $QQNumber + ')')
    $killed = Stop-NapCat
    Write-Log ('stopped ' + $killed + ' NapCat process(es)')
    Start-Sleep -Seconds 3

    $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $LauncherCmd }
    Write-Log ('relaunch ReturnValue=' + $r.ReturnValue + ' ProcessId=' + $r.ProcessId)

    Set-Content -Path $StampFile -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Encoding ASCII
    if (Test-Path $StuckFile) { Remove-Item $StuckFile -Force }
}

# ---------------------------- main ----------------------------

Rotate-Log

$state = Get-NapCatState

if ($state.Boot -and $state.Linked) {
    # everything is fine - stay quiet
    if (Test-Path $StuckFile) { Remove-Item $StuckFile -Force }
    Write-Output ('healthy: boot=' + $state.Boot + ' link=' + $state.Linked)
    exit 0
}

if ($state.Boot -and -not $state.Linked) {
    # process is up but the bot is not connected yet: waiting for a scan.
    if (-not (Test-Path $StuckFile)) {
        Set-Content -Path $StuckFile -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Encoding ASCII
        Write-Output 'waiting for login (grace period started)'
        exit 0
    }
    $stuckFor = ((Get-Date) - (Get-Item $StuckFile).LastWriteTime).TotalMinutes
    if ($stuckFor -lt $StuckMin) {
        Write-Output ('waiting for login (' + [math]::Round($stuckFor, 1) + ' min)')
        exit 0
    }
    Restart-NapCat ('not connected for ' + [math]::Round($stuckFor, 1) + ' min')
    exit 0
}

# NapCat itself is gone
$reason = @()
if (-not $state.Boot)   { $reason += 'NapCatWinBootMain not running' }
if (-not $state.Linked) { $reason += 'no active link on 6199' }
$reasonText = $reason -join '; '

if (Test-Path $StampFile) {
    $ago = ((Get-Date) - (Get-Item $StampFile).LastWriteTime).TotalMinutes
    if ($ago -lt $CooldownMin) {
        Write-Log ('UNHEALTHY (' + $reasonText + ') but still in cooldown (' + [math]::Round($ago, 1) + ' min ago), skip this round')
        exit 0
    }
}

Restart-NapCat $reasonText
exit 0
