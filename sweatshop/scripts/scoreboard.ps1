<#
.SYNOPSIS
  How often each implementer's work comes back from review, read from sweatshop run
  logs across repos. The reopen rate is reported per implementer -> reviewer pair:
  a stricter reviewer reopens more, so the pair is the unit, not the implementer.
  Where <tracker>/reopen-attribution.md exists (the foreman writes it), each reopen is
  also split by fault: only a reopen with a stage-2 finding counts against the implementer.

.EXAMPLE
  .\scoreboard.ps1 D:\Desktop\Projects\SynchroNice D:\Desktop\Projects\SIGAA-ME
  .\scoreboard.ps1 -SelfCheck
#>
[CmdletBinding(PositionalBinding = $false)]
param([Parameter(ValueFromRemainingArguments)][string[]]$Repos, [string]$Tracker = '.scratch', [switch]$SelfCheck)
$ErrorActionPreference = 'Stop'

function Inv($f) { [string]::Format([Globalization.CultureInfo]::InvariantCulture, $f, [object[]]$args) }
function Median($v) { $s = @($v | Sort-Object); if ($s.Count) { $s[[int][math]::Floor($s.Count / 2)] } }
# Logs before 2026-10-02 spelled a binding's `claude-opus-5-5`; the driver now logs `opus-5.5`.
function ModelName($m) { $m -replace '^claude-([a-z]+)-(\d+)-(\d+)\b', '$1-$2.$3' -replace '^claude-', '' }

# Both run-log shapes: 10 cells before Tokens/Cost existed, 12 after. An `api error` row
# spent no attempt and says nothing about the model: dropped. Ids are keyed by repo,
# since two repos can each have a CLEAN-010.
function Rows($file, $repo) {
  foreach ($l in (Get-Content $file -Encoding UTF8)) {
    $c = @($l -split '\|' | ForEach-Object { $_.Trim() })
    if ($c.Count -notin 10, 12, 13 -or $c[1] -notmatch '^\d{4}-\d\d-\d\d' -or $c[6] -like 'api error*') { continue }
    [pscustomobject]@{ Key = "$repo/$($c[2])"; Stage = $c[3]; Model = ModelName $c[4]; Outcome = $c[6]
                       Shutdown = $(if ($c.Count -eq 13 -and $c[11] -match '^\d+(\.\d+)?$') { [double]::Parse($c[11], [Globalization.CultureInfo]::InvariantCulture) } else { $null })
                       Min = [int]($c[8] -replace '\D', '')
                       Cost = $(if ($c.Count -ge 12 -and $c[10] -match '^\$') { [double]($c[10] -replace '\$', '') } else { $null }) }
  }
}

# One row per finding of a reopen: | When | ID | Round | Implementer | Reviewer | Label | Finding | Why |.
# Round N is the ticket's Nth `reopened` review row in run-log.md, which is how the two join.
# Round 0 is a finding the merging review fixed itself instead of reopening.
function Findings($file, $repo) {
  foreach ($l in (Get-Content $file -Encoding UTF8)) {
    $c = @($l -split '\|' | ForEach-Object { $_.Trim() })
    if ($c.Count -notin 10, 14 -or $c[1] -notmatch '^\d{4}-\d\d-\d\d' -or $c[3] -notmatch '^(\d+|-)$') { continue }
    [pscustomobject]@{ Key = "$repo/$($c[2])#$($c[3])"; Pair = "$(ModelName $c[4]) -> $(ModelName $c[5])"; Label = $c[6]
      Discovery = $(if ($c.Count -eq 14) { $c[9] } else { 'ticket-review' })
      Origin = $(if ($c.Count -eq 14) { $c[10] } else { 'unknown' })
      Miss = $(if ($c.Count -eq 14) { $c[11] } else { 'unknown' })
      Churn = $(if ($c.Count -eq 14) { $c[12] } else { 'unknown' }) }
  }
}

# A review is charged to whoever sent that ticket to review last. A review that ended
# without a verdict (`review ended at ...`) charges nobody; the next one does. A reopen
# counts against the implementer (S2) when any of its findings is S2; one with findings
# but no S2 was the spec's or the reviewer's; one with no findings is unclassified. A merge
# whose review fixed an S2 finding itself (round 0) counts as fixed for S2: a miss the
# implementer made that a stricter reviewer would have reopened.
function Score($rows, $findings) {
  $findings = @($findings | Where-Object Discovery -eq 'ticket-review')
  $impl = [ordered]@{}; $pair = [ordered]@{}; $waiting = @{}; $round = @{}; $seen = @{}; $s2 = @{}
  foreach ($f in $findings) { $seen[$f.Key] = 1; if ($f.Label -like 'S2*') { $s2[$f.Key] = 1 } }
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
      if (-not $pair.Contains($k)) { $pair[$k] = [pscustomobject]@{ Impl = $by; Rev = $r.Model; Reviews = 0; Reopened = 0; S2 = 0; Unclassified = 0; Fixed = 0 } }
      $pair[$k].Reviews++
      if ($r.Outcome -eq 'merged' -and $s2["$($r.Key)#0"]) { $pair[$k].Fixed++ }
      if ($r.Outcome -eq 'reopened') {
        $pair[$k].Reopened++
        $round[$r.Key] = 1 + $round[$r.Key]
        $n = "$($r.Key)#$($round[$r.Key])"
        if ($s2[$n]) { $pair[$k].S2++ } elseif (-not $seen[$n]) { $pair[$k].Unclassified++ }
      }
      $waiting.Remove($r.Key)
    }
  }
  $impl, $pair
}

function Count($labels, $re) { @($labels | Where-Object { $_ -match $re }).Count }

function Render($impl, $pair, $findings) {
  $findings = @($findings | Where-Object Discovery -eq 'ticket-review')
  '| Implementer | Stage runs | To review | Failed | Asked | Median min to review | Cost |'
  '|---|---|---|---|---|---|---|'
  foreach ($m in $impl.Keys) {
    $i = $impl[$m]
    $cost = if ($i.Priced) { Inv '${0:0.00} ({1}/{2} priced)' $i.Cost $i.Priced $i.Runs } else { '?' }
    $med = if ($i.Min.Count) { "$(Median $i.Min)m" } else { '-' }
    '| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f $m, $i.Runs, $i.ToReview, $i.Failed, $i.Asked, $med, $cost
  }
  ''
  # Unclassified reopens may be S2 too, so the S2 rate is a floor while any remain.
  '| Implementer | Reviewer | Reviews | Reopened | Reopen rate | Reopened for S2 | S2 rate | Unclassified | Fixed in review for S2 |'
  '|---|---|---|---|---|---|---|---|---|'
  foreach ($p in $pair.Values) {
    $floor = if ($p.Unclassified) { '>=' } else { '' }
    '| {0} | {1} | {2} | {3} | {4}% | {5} | {6}{7}% | {8} | {9} |' -f $p.Impl, $p.Rev, $p.Reviews, $p.Reopened,
      [int](100 * $p.Reopened / $p.Reviews), $p.S2, $floor, [int](100 * $p.S2 / $p.Reviews), $p.Unclassified, $p.Fixed
  }
  if (-not $findings) { return }
  # Every attributed finding, including reopens from before run-log.md began: labels, not rates.
  ''
  '| Implementer -> Reviewer | Rounds | S2 explicit code | S2 explicit test | S2 implicit | S1 | S3 noise |'
  '|---|---|---|---|---|---|---|'
  foreach ($g in ($findings | Group-Object Pair)) {
    $l = @($g.Group.Label)
    '| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f $g.Name, @($g.Group.Key | Sort-Object -Unique).Count,
      (Count $l '^S2-expl\S*[/ ]c'), (Count $l '^S2-expl\S*[/ ]t'), (Count $l '^S2-impl'), (Count $l '^S1'), (Count $l '^S3')
  }
}

# Counts describe recorded findings, not a defect rate: audit coverage is not uniform.
function RenderEvidence($rows, $findings, $interventions) {
  ''
  'Evidence coverage: legacy flags and absent records are unknown, not zero defects or zero interventions.'
  '| Discovery | Recorded findings | Earlier review miss (yes / known) | Review-induced churn (yes / known) |'
  '|---|---|---|---|'
  foreach ($g in ($findings | Where-Object { $_.Label -notlike 'S3*' } | Group-Object Discovery)) {
    $miss = @($g.Group | Where-Object Miss -eq 'yes').Count; $knownMiss = @($g.Group | Where-Object { $_.Miss -in 'yes','no' }).Count
    $churn = @($g.Group | Where-Object Churn -eq 'yes').Count; $knownChurn = @($g.Group | Where-Object { $_.Churn -in 'yes','no' }).Count
    '| {0} | {1} | {2} / {3} | {4} / {5} |' -f $g.Name, $g.Count, $miss, $knownMiss, $churn, $knownChurn
  }
  $timed = @($rows | Where-Object { $null -ne $_.Shutdown })
  if ($timed.Count) { Inv 'Runtime completion to process exit: {0:0.000}s total over {1} measured stages; {2} unmeasured.' (SumShutdown $timed) $timed.Count (@($rows).Count - $timed.Count) }
  else { 'Runtime completion to process exit: unmeasured.' }
  '| Intervention | Recorded events |'
  '|---|---|'
  foreach ($g in ($interventions | Group-Object Kind)) { '| {0} | {1} |' -f $g.Name, $g.Count }
  if (-not $interventions) { 'Interventions: no structured records; inspect foreman notes for older runs.' }
}
function SumShutdown($rows) { ($rows | Measure-Object Shutdown -Sum).Sum }
function Interventions($file) {
  foreach ($line in Get-Content $file -Encoding UTF8) {
    $c = @($line -split '\|' | ForEach-Object { $_.Trim() })
    if ($c.Count -eq 6 -and $c[1] -match '^\d{4}-\d\d-\d\d' -and $c[3] -in 'human-rescue','routine-approval','proxy-decision','automatic-recovery') {
      [pscustomobject]@{ Kind = $c[3] }
    }
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
    "| 2026-09-27 11:15 | T-4 | implement | a high | 1 | to-review | $s | 20m | ? | ? |",
    "| 2026-09-27 11:16 | T-4 | review | r high | 1 | reopened | $s | 5m | ? | ? |",
    "| 2026-09-27 11:17 | T-4 | implement | a high | 1 | to-review | $s | 20m | ? | ? |",
    "| 2026-09-27 11:18 | T-4 | review | r high | 1 | reopened | $s | 5m | ? | ? |",
    "| 2026-09-27 11:19 | T-4 | implement | a high | 1 | to-review | $s | 20m | ? | ? |",
    "| 2026-09-27 11:19 | T-4 | review | r high | 1 | merged | $s | 5m | ? | ? |",
    '| 2026-09-27 11:20 | T-3 | review | r high | 1 | reopened | x | 5m |')   # old shape, no Tokens/Cost; sent to review before the log
  # Round 1 of T-4 is noise and round 2 is S2: a join that ignored the round would count one S2, not two.
  $att = Join-Path $env:TEMP "attribution-$PID.md"
  Set-Content -Encoding UTF8 $att @(
    '| When | ID | Round | Implementer | Reviewer | Label | Finding | Why |', '|---|---|---|---|---|---|---|---|',
    '| 2026-09-27 | T-1 | 1 | a high | r high | S2-implicito | x | x |',
    '| 2026-09-27 | T-1 | 1 | a high | r high | S1 | x | x |',
    '| 2026-09-27 | T-4 | 1 | a high | r high | S3-ruido | x | x |',
    '| 2026-09-27 | T-4 | 2 | a high | r high | S2-explicito/teste ? | x | x |',
    '| 2026-09-27 | T-2 | 0 | b max | r high | S2-explicito/teste | x | x |')   # fixed by the merging review
  $found = @(Findings $att 'repo')
  $impl, $pair = Score @(Rows $tmp 'repo') $found
  Remove-Item $tmp, $att
  $got = ($pair.Values | ForEach-Object { '{0}>{1} {2}/{3} s2 {4} u{5} f{6}' -f $_.Impl, $_.Rev, $_.Reopened, $_.Reviews, $_.S2, $_.Unclassified, $_.Fixed }) -join ', '
  if ($got -ne 'a high>r high 3/5 s2 2 u0 f0, b max>r high 0/1 s2 0 u0 f1, ?>r high 1/1 s2 0 u1 f0') { throw "Score pairs: $got" }
  if ((ModelName 'claude-opus-5-5 high') -ne 'opus-5.5 high' -or (ModelName 'claude-sonnet-5') -ne 'sonnet-5') { throw 'ModelName: a claude- id must read as its short name' }
  $table = (Render $impl $pair $found) | Where-Object { $_ -like '| a high -> *' }
  if ($table -ne '| a high -> r high | 3 | 0 | 1 | 1 | 1 | 1 |') { throw "Findings table: $table" }
  $b = $impl['b max']
  if ("$($b.Runs) $($b.Failed) $($b.ToReview)" -ne '2 1 1') { throw "Score b: runs/failed/to-review $($b.Runs) $($b.Failed) $($b.ToReview)" }
  if ((Median $impl['a high'].Min) -ne 20 -or $impl['a high'].Priced -ne 1) { throw 'Score a: median or priced' }
  # New evidence must not change old reopening rates or convert unknown flags to zero.
  Set-Content -Encoding UTF8 $att @(
    '| When | ID | Round | Implementer | Reviewer | Label | Finding | Why | Discovery | Origin | Review miss | Review churn |',
    '| 2026-10-03 | T-1 | 1 | a high | r high | S2-implicito | x | report#1 | ticket-review | T-1@abc | yes | no |',
    '| 2026-10-03 | T-1 | - | a high | r high | S2-implicito | x | audit#2 | release-audit | T-1@abc | unknown | unknown |',
    '| 2026-10-03 | - | - | ? | ? | unclassified | x | user#3 | post-release | unknown | unknown | yes |')
  $extra = @(Findings $att 'repo')
  if ($extra.Count -ne 3 -or $extra[1].Origin -ne 'T-1@abc') { throw 'Extended finding schema lost provenance' }
  if ($found[0].Miss -ne 'unknown' -or $found[0].Discovery -ne 'ticket-review') { throw 'Legacy finding flags must be unknown' }
  Set-Content -Encoding UTF8 $tmp '| 2026-10-03 12:00 | T-1 | implement | a high | 1 | to-review | sweatshop/x | 3m | ? | ? | 1.250 |'
  $timed = @(Rows $tmp 'repo')
  if ($timed.Count -ne 1 -or $timed[0].Shutdown -ne 1.25) { throw 'Shutdown timing schema' }
  $events = Join-Path $env:TEMP "interventions-$PID.md"
  Set-Content -Encoding UTF8 $events @(
    '| When | Ticket | Kind | Evidence |',
    '| 2026-10-03 12:00 | T-1 | human-rescue | notes#1 |',
    '| 2026-10-03 12:01 | - | routine-approval | release#1 |')
  $interventions = @(Interventions $events)
  $evidence = (RenderEvidence $timed @($found + $extra) $interventions) -join "`n"
  if ($evidence -notmatch '\| release-audit \| 1 \| 0 / 0 \| 0 / 0 \|' -or
      $evidence -notmatch '\| post-release \| 1 \| 0 / 0 \| 1 / 1 \|' -or
      $evidence -notmatch '\| human-rescue \| 1 \|' -or $evidence -notmatch '1.250s total') { throw "Evidence aggregation: $evidence" }
  $nothing, $externalPairs = Score @() @($extra | Where-Object Discovery -ne 'ticket-review')
  if ($externalPairs.Count) { throw 'Post-approval findings changed reopening rates' }
  Remove-Item -LiteralPath $tmp, $att, $events
  Write-Host 'Self-check OK'; exit 0
}

if (-not $Repos) { throw 'Pass one or more repo paths.' }
$rows = foreach ($r in $Repos) {
  $f = Join-Path $r "$Tracker/run-log.md"
  if (Test-Path $f) { Rows $f (Split-Path $r -Leaf) } else { Write-Warning "no run log: $f" }
}
$findings = foreach ($r in $Repos) {
  $f = Join-Path $r "$Tracker/reopen-attribution.md"
  if (Test-Path $f) { Findings $f (Split-Path $r -Leaf) }
}
$impl, $pair = Score @($rows) @($findings)
Render $impl $pair @($findings)
$interventions = @(foreach ($r in $Repos) {
  $f = Join-Path $r "$Tracker/interventions.md"
  if (Test-Path $f) { Interventions $f }
})
RenderEvidence @($rows) @($findings) $interventions
