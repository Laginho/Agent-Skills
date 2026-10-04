# One read-only branch contract for driver, bare-ID dispatch and standup.
[CmdletBinding()]
param([string]$Repo = '.', [string]$Id, [switch]$IncludeRemote)
function Find-TicketBranch($repository, $ticketId, [switch]$Remote) {
  if ($ticketId -notmatch '^\p{Lu}[\p{Lu}0-9]*-\d+$') { throw "Invalid ticket ID: $ticketId" }
  $roots = @('refs/heads/')
  if ($Remote) { $roots += 'refs/remotes/origin/' }
  $ErrorActionPreference = 'Continue'
  $refs = @(& git -C $repository for-each-ref '--format=%(refname)' @roots 2>&1)
  if ($LASTEXITCODE) { throw "Cannot discover ticket branches: $refs" }
  $pattern = '^(?:.*/)?' + [regex]::Escape($ticketId) + '(?:-.+)?$'
  $candidates = @($refs | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] } | ForEach-Object {
    $ref = "$_"; $name = $ref -replace '^refs/heads/', '' -replace '^refs/remotes/origin/', ''
    # Old attempts are intentionally kept. Neither namespace nor suffix is active.
    if ($name -cmatch '^recovery/' -or $name -match '-(?:asked|recovery)-\d') { return }
    if ($name -cmatch $pattern -or $name -ceq $ticketId.ToLowerInvariant()) {
      [pscustomobject]@{ Name = $name; Ref = $ref }
    }
  })
  # Local/origin copies of one name are one branch only when their commits agree.
  $names = @($candidates | Select-Object -ExpandProperty Name -Unique)
  if ($names.Count -gt 1) { throw "Ambiguous active branches for ${ticketId}: $($names -join ', '). Preserve work and choose explicitly." }
  if (-not $names.Count) { return }
  $matches = @($candidates | Where-Object Name -eq $names[0])
  if ($matches.Count -gt 1) {
    $local = $matches | Where-Object { $_.Ref -like 'refs/heads/*' }
    $origin = $matches | Where-Object { $_.Ref -like 'refs/remotes/*' }
    if (Test-GitAncestor $repository $origin.Ref $local.Ref) { $matches = @($local) }
    elseif (Test-GitAncestor $repository $local.Ref $origin.Ref) { $matches = @($origin) }
    else { throw "Ambiguous divergent local/origin history for $ticketId ($($names[0])). Reconcile explicitly." }
  }
  $matches[0].Ref -replace '^refs/heads/', '' -replace '^refs/remotes/', ''
}
function Test-GitAncestor($repository, $older, $newer) {
  $ErrorActionPreference = 'Continue'
  & git -C $repository merge-base --is-ancestor $older $newer
  if ($LASTEXITCODE -notin 0, 1) { throw "Cannot check Git ancestry: $older -> $newer" }
  $LASTEXITCODE -eq 0
}
if ($Id) { Find-TicketBranch $Repo $Id -Remote:$IncludeRemote }
