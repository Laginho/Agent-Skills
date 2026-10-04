<# The bootstrap updates before loading any runtime/helper code. #>
param(
  [Parameter(Mandatory)][string]$Repo,
  [string]$Tracker = '.scratch',
  [int]$ImplementMinutes = 45,
  [int]$ReviewMinutes = 0,
  [switch]$DryRun,
  [switch]$SelfCheck,
  [string]$Lineup,
  [string]$Models
)
$ErrorActionPreference = 'Stop'
$before = $null; $after = $null
# Both diagnostic modes must be safe in dirty/offline checkouts and need no CLIs.
if ($SelfCheck) { & (Join-Path $PSScriptRoot 'driver-selfcheck.ps1'); return }
if (-not ($DryRun -or $SelfCheck)) {
  $mutex = [Threading.Mutex]::new($false, 'sweatshop-self-update')
  try {
    try { $null = $mutex.WaitOne() } catch [Threading.AbandonedMutexException] { }
    $ErrorActionPreference = 'Continue'
    $inside = & git -C $PSScriptRoot rev-parse --is-inside-work-tree 2>$null
    $prefix = if ($LASTEXITCODE -eq 0 -and $inside) { & git -C $PSScriptRoot rev-parse --show-prefix 2>$null }
    $tracked = if ($prefix -eq 'sweatshop/scripts/') { & git -C $PSScriptRoot ls-files --error-unmatch -- sweatshop.ps1 2>$null }
    if ($prefix -ne 'sweatshop/scripts/' -or -not $tracked) { Write-Host 'driver: standalone/copied install; not updated' }
    elseif (& git -C $PSScriptRoot status --porcelain) { Write-Host 'driver: local edits; not updated' }
    else {
      $before = & git -C $PSScriptRoot rev-parse HEAD
      if ($env:SWEATSHOP_UPDATED_REVISION -ne $before) {
        & git -C $PSScriptRoot pull -q --ff-only
        if ($LASTEXITCODE) { throw 'Driver update failed; no runtime loaded.' }
      }
      $after = & git -C $PSScriptRoot rev-parse HEAD
    }
  } finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
  if ($after -and $after -ne $before) {
    # Reparse the new entry point once, with precisely the original arguments.
    $oldRevision = $env:SWEATSHOP_UPDATED_REVISION
    try {
      $env:SWEATSHOP_UPDATED_REVISION = $after
      & $PSCommandPath @PSBoundParameters
      return
    } finally { $env:SWEATSHOP_UPDATED_REVISION = $oldRevision }
  }
}
$ErrorActionPreference = 'Stop'
$runtime = Join-Path $PSScriptRoot 'driver.ps1'
Write-Host "driver: executing SHA256 $((Get-FileHash -LiteralPath $runtime -Algorithm SHA256).Hash)"
& $runtime @PSBoundParameters
