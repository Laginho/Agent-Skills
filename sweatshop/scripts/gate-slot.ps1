# One of this machine's gate slots, shared by ticket gates (sweatshop/scripts/gate-evidence.ps1)
# and PR gates (pr-review-loop/scripts/gate-lock.ps1), so parallel lanes and reviews queue instead
# of exhausting RAM or timing out each other's tests (CLEAN-081). Release it with ReleaseMutex().
function Enter-GateSlot([int]$Slots = 0) {
  # No -Slots: this machine's limit from ~/.config/gate-lock/slots (one number), else 3.
  if ($Slots -le 0) {
    $f = Join-Path $HOME '.config/gate-lock/slots'
    $Slots = if (Test-Path $f) { [int](Get-Content $f -Raw).Trim() } else { 3 }
  }
  $waiting = $false
  while ($true) {
    foreach ($i in 0..($Slots - 1)) {
      $m = New-Object System.Threading.Mutex($false, "gate-lock-slot-$i")
      try { if ($m.WaitOne(0)) { return $m } }
      catch [System.Threading.AbandonedMutexException] { return $m }  # previous holder died: slot is ours
      $m.Dispose()
    }
    if (-not $waiting) { Write-Host "Waiting for one of $Slots gate slots (another gate is running)."; $waiting = $true }
    Start-Sleep -Seconds 5
  }
}
