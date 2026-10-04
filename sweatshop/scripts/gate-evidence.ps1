# Runs the bound gate once, or checks the evidence already created by that run.
[CmdletBinding()]
param([string]$Repo = '.', [string]$Command, [string]$Log, [string]$Receipt)
function Save-GateEvidence($repository, $command, $exitCode, $logPath, $receiptPath) {
  if ($exitCode -ne 0) { throw "Gate failed (exit $exitCode); log: $logPath" }
  $ErrorActionPreference = 'Continue'
  $dirty = & git -C $repository status --porcelain
  if ($LASTEXITCODE -or $dirty) { throw 'Gate evidence requires committed, clean code.' }
  $code = & git -C $repository rev-parse HEAD
  $logHash = (Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash
  [pscustomobject]@{ Command = $command; ExitCode = $exitCode; Log = [IO.Path]::GetFullPath($logPath); LogHash = $logHash; Code = "$code" } |
    ConvertTo-Json | Set-Content -LiteralPath $receiptPath -Encoding UTF8
}
function Assert-GateEvidence($ticket, $ref) {
  if (-not $ticket.GateEvidence) { throw "$($ticket.Id): missing Gate evidence receipt." }
  $proof = Get-Content -LiteralPath $ticket.GateEvidence -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($proof.Command -ne $Gate -or $proof.ExitCode -ne 0 -or $proof.Code -notmatch '^[0-9a-f]{40}$') { throw "$($ticket.Id): invalid or failed gate evidence." }
  if ((Get-FileHash -LiteralPath $proof.Log -Algorithm SHA256).Hash -ne $proof.LogHash -or
      (Get-Content -LiteralPath $proof.Log -Raw) -notmatch '(?m)^ExitCode: 0\s*$') { throw "$($ticket.Id): gate log changed or exit status missing." }
  $ErrorActionPreference = 'Continue'
  & git cat-file -e "$($proof.Code)^{commit}"
  if ($LASTEXITCODE) { throw "$($ticket.Id): tested gate commit is unavailable." }
  # Only this ticket and its ledger may close after the checked commit. Skills,
  # scripts and arbitrary documentation remain production and invalidate evidence.
  $ledger = ($ticket.File -replace '/issues/[^/]+$', '/ledger.md')
  $changed = @(& git diff --name-only $proof.Code $ref -- . ":(exclude)$($ticket.File)" ":(exclude)$ledger")
  if ($LASTEXITCODE -or $changed) { throw "$($ticket.Id): code changed after gate ($($changed -join ', ')); reuse evidence only for identical code." }
}
if ($Command) {
  if (-not ($Log -and $Receipt)) { throw 'Pass -Log and -Receipt outside the repository.' }
  $Repo = (Resolve-Path -LiteralPath $Repo).Path
  foreach ($path in $Log, $Receipt) {
    $full = [IO.Path]::GetFullPath($path)
    if ($full.StartsWith($Repo.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Gate log and receipt must live outside the repository.' }
  }
  Push-Location $Repo
  try {
    if (Test-Path -LiteralPath $Receipt) { Remove-Item -LiteralPath $Receipt }
    if (& git status --porcelain) { throw 'Commit the tested code before running the gate.' }
    $testedCode = & git rev-parse HEAD
    if ($LASTEXITCODE) { throw 'Cannot identify tested commit.' }
    $ErrorActionPreference = 'Continue'
    $shellCode = "`$ErrorActionPreference = 'Stop'; try { & { $Command }; if (`$null -ne `$LASTEXITCODE) { exit `$LASTEXITCODE } } catch { Write-Error `$_; exit 1 }"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($shellCode))
    & powershell -NoProfile -EncodedCommand $encoded *> $Log
    $gateExit = $LASTEXITCODE
    Add-Content -LiteralPath $Log "ExitCode: $gateExit"
    $ErrorActionPreference = 'Stop'
    $afterCode = & git rev-parse HEAD
    if ($LASTEXITCODE -or $afterCode -ne $testedCode) { throw 'Gate changed HEAD; evidence cannot be attributed to the starting commit.' }
    Save-GateEvidence $Repo $Command $gateExit $Log $Receipt
    Write-Host "Gate exit $gateExit; log $Log; receipt $Receipt"
  } finally { Pop-Location }
}
