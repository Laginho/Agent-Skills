# Runs the repo gate inside one of $Slots machine-wide slots, so parallel sessions queue
# instead of exhausting RAM (7 gates with Flutter at once left 0.5 GB free and failed on timeouts).
# Log: WAIT, START, the gate output, then EXIT=<code>.
param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Log,
      [Parameter(Mandatory)][string]$Command, [int]$Slots = 0)
# No -Slots: this machine's limit from ~/.config/gate-lock/slots (one number), else 3.
if ($Slots -le 0) {
  $f = Join-Path $HOME '.config/gate-lock/slots'
  $Slots = if (Test-Path $f) { [int](Get-Content $f -Raw).Trim() } else { 3 }
}
"WAIT $(Get-Date -Format s)" | Out-File $Log -Encoding utf8
$held = $null
while (-not $held) {
  foreach ($i in 0..($Slots - 1)) {
    $m = New-Object System.Threading.Mutex($false, "gate-lock-slot-$i")
    try { if ($m.WaitOne(0)) { $held = $m; break } }
    catch [System.Threading.AbandonedMutexException] { $held = $m; break }  # previous holder died: slot is ours
    $m.Dispose()
  }
  if (-not $held) { Start-Sleep -Seconds 5 }
}
"START $(Get-Date -Format s)" | Add-Content $Log -Encoding utf8
Push-Location $Repo
try {
  if ($env:OS -eq 'Windows_NT') { cmd /c "$Command 2>&1" | Add-Content $Log -Encoding utf8 }
  else { sh -c "$Command 2>&1" | Add-Content $Log -Encoding utf8 }
  $code = $LASTEXITCODE
}
finally { Pop-Location }
"EXIT=$code" | Add-Content $Log -Encoding utf8
$held.ReleaseMutex()
exit $code
