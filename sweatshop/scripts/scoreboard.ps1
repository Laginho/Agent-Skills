<#
.SYNOPSIS
  How often each implementer's work comes back from review, read from sweatshop run
  logs across repos. The reopen rate is reported per implementer -> reviewer pair:
  a stricter reviewer reopens more, so the pair is the unit, not the implementer.

.EXAMPLE
  .\scoreboard.ps1 D:\Desktop\Projects\SynchroNice D:\Desktop\Projects\SIGAA-ME
  .\scoreboard.ps1 -SelfCheck
#>
[CmdletBinding(PositionalBinding = $false)]
param([Parameter(ValueFromRemainingArguments)][string[]]$Repos, [string]$Tracker = '.scratch', [switch]$SelfCheck)
$ErrorActionPreference = 'Stop'

function Inv($f) { [string]::Format([Globalization.CultureInfo]::InvariantCulture, $f, [object[]]$args) }
function Median($v) { $s = @($v | Sort-Object); if ($s.Count) { $s[[int][math]::Floor($s.Count / 2)] } }

# Both run-log shapes: 10 cells before Tokens/Cost existed, 12 after. An `api error` row
# spent no attempt and says nothing about the model: dropped. Ids are keyed by repo,
# since two repos can each have a CLEAN-010.
function Rows($file, $repo) {
  foreach ($l in (Get-Content $file -Encoding UTF8)) {
    $c = @($l -split '\|' | ForEach-Object { $_.Trim() })
    if ($c.Count -notin 10, 12 -or $c[1] -notmatch '^\d{4}-\d\d-\d\d' -or $c[6] -like 'api error*') { continue }
    [pscustomobject]@{ Key = "$repo/$($c[2])"; Stage = $c[3]; Model = $c[4]; Outcome = $c[6]
                       Min = [int]($c[8] -replace '\D', '')
                       Cost = $(if ($c.Count -eq 12 -and $c[10] -match '^\$') { [double]($c[10] -replace '\$', '') } else { $null }) }
  }
}

# A review is charged to whoever sent that ticket to review last. A review that ended
# without a verdict (`review ended at ...`) charges nobody; the next one does.
function Score($rows) {
  $impl = [ordered]@{}; $pair = [ordered]@{}; $waiting = @{}
  foreach ($r in $rows) {
    if ($r.Stage -eq 'implement') {
      if (-not $impl.Contains($r.Model)) { $impl[$r.Model] = [pscustomobject]@{ Runs = 0; ToReview = 0; Failed = 0; Asked = 0; Min = @(); Cost = 0.0; Priced = 0 } }
      $i = $impl[$r.Model]; $i.Runs++
      if ($r.Outcome -eq 'to-review') { $i.ToReview++; $i.Min += $r.Min; $waiting[$r.Key] = $r.Model }
      elseif ($r.Outcome -like 'failed*') { $i.Failed++ }
      elseif ($r.Outcome -like 'asked*') { $i.Asked++ }
      if ($null -ne $r.Cost) { $i.Cost += $r.Cost; $i.Priced++ }
    } elseif ($r.Stage -eq 'review' -and $r.Outcome -in 'merged', 'reopened', 'waiting for you') {
      $by = if ($waiting[$r.Key]) { $waiting[$r.Key] } else { '?' }   # ?: sent to review before this log began
      $k = "$by|$($r.Model)"
      if (-not $pair.Contains($k)) { $pair[$k] = [pscustomobject]@{ Impl = $by; Rev = $r.Model; Reviews = 0; Reopened = 0 } }
      $pair[$k].Reviews++
      if ($r.Outcome -eq 'reopened') { $pair[$k].Reopened++ }
      $waiting.Remove($r.Key)
    }
  }
  $impl, $pair
}

function Render($impl, $pair) {
  '| Implementer | Stage runs | To review | Failed | Asked | Median min to review | Cost |'
  '|---|---|---|---|---|---|---|'
  foreach ($m in $impl.Keys) {
    $i = $impl[$m]
    $cost = if ($i.Priced) { Inv '${0:0.00} ({1}/{2} priced)' $i.Cost $i.Priced $i.Runs } else { '?' }
    $med = if ($i.Min.Count) { "$(Median $i.Min)m" } else { '-' }
    '| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f $m, $i.Runs, $i.ToReview, $i.Failed, $i.Asked, $med, $cost
  }
  ''
  '| Implementer | Reviewer | Reviews | Reopened | Reopen rate |'
  '|---|---|---|---|---|'
  foreach ($p in $pair.Values) {
    '| {0} | {1} | {2} | {3} | {4}% |' -f $p.Impl, $p.Rev, $p.Reviews, $p.Reopened, [int](100 * $p.Reopened / $p.Reviews)
  }
}

if ($SelfCheck) {
  # Attribution is the whole point: a reopen charged to the wrong implementer ranks the wrong model.
  $tmp = Join-Path $env:TEMP "scoreboard-$PID.md"
  $s = 'sweatshop/x'
  Set-Content -Encoding UTF8 $tmp @(
    '| When | ID | Stage | Model | Attempt | Outcome | Session | Took | Tokens | Cost |', '|---|---|---|---|---|---|---|---|---|---|',
    "| 2026-09-27 10:00 | T-1 | implement | a high | 1 | to-review | $s | 10m | 1k in (0% cached), 1k out | `$1.000 |",
    "| 2026-09-27 10:10 | T-1 | review | r high | 1 | reopened | $s | 5m | ? | ? |",
    "| 2026-09-27 10:20 | T-1 | implement | a high | 1 | to-review | $s | 20m | ? | ? |",
    "| 2026-09-27 10:30 | T-1 | review | r high | 1 | merged | $s | 5m | ? | ? |",
    "| 2026-09-27 10:40 | T-2 | implement | b max | 1 | failed (exit 0), will retry | $s | 3m | ? | ? |",
    "| 2026-09-27 10:41 | T-2 | implement | b max | 2 | api error, not counted | $s | 0m | ? | ? |",
    "| 2026-09-27 10:50 | T-2 | implement | b max | 2 | to-review | $s | 9m | ? | ? |",
    "| 2026-09-27 11:00 | T-2 | review | r high | 2 | review ended at blocked (exit 0) | $s | 5m | ? | ? |",
    "| 2026-09-27 11:10 | T-2 | review | r high | 2 | merged | $s | 5m | ? | ? |",
    '| 2026-09-27 11:20 | T-3 | review | r high | 1 | reopened | x | 5m |')   # old shape, no Tokens/Cost; sent to review before the log
  $impl, $pair = Score @(Rows $tmp 'repo')
  Remove-Item $tmp
  $got = ($pair.Values | ForEach-Object { '{0}>{1} {2}/{3}' -f $_.Impl, $_.Rev, $_.Reopened, $_.Reviews }) -join ', '
  if ($got -ne 'a high>r high 1/2, b max>r high 0/1, ?>r high 1/1') { throw "Score pairs: $got" }
  $b = $impl['b max']
  if ("$($b.Runs) $($b.Failed) $($b.ToReview)" -ne '2 1 1') { throw "Score b: runs/failed/to-review $($b.Runs) $($b.Failed) $($b.ToReview)" }
  if ((Median $impl['a high'].Min) -ne 20 -or $impl['a high'].Priced -ne 1) { throw 'Score a: median or priced' }
  Write-Host 'Self-check OK'; exit 0
}

if (-not $Repos) { throw 'Pass one or more repo paths.' }
$rows = foreach ($r in $Repos) {
  $f = Join-Path $r "$Tracker/run-log.md"
  if (Test-Path $f) { Rows $f (Split-Path $r -Leaf) } else { Write-Warning "no run log: $f" }
}
$impl, $pair = Score @($rows)
Render $impl $pair
