# Runs the repo gate inside one of the machine's gate slots (sweatshop/scripts/gate-slot.ps1).
# Log: WAIT, START, the gate output, then EXIT=<code>.
param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Log,
      [Parameter(Mandatory)][string]$Command, [int]$Slots = 0)
. (Join-Path $PSScriptRoot '../../sweatshop/scripts/gate-slot.ps1')
"WAIT $(Get-Date -Format s)" | Out-File $Log -Encoding utf8
$held = Enter-GateSlot $Slots
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
