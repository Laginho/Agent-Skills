# Weekly Codex quota spent per stage and per model since a run's launch, for the foreman report.
# Source: rate_limits in ~/.codex/sessions rollouts (`codex exec --json` does not print them).
# One quota covers every Codex thread on the account, so a rollout outside the run's stages counts apart.
[CmdletBinding()]
param([string]$Tracker, [datetime]$Since, [datetime]$Until = [datetime]::MaxValue, [switch]$SelfCheck)
$ErrorActionPreference = 'Stop'

# Telescoping: each rollout spent its last reading minus the previous rollout's last reading,
# so the run total is exact while one stage is ±1 point (Codex rounds used_percent to integers).
function Measure-Spend($rollouts, $baseline) {
  $prev = $baseline
  foreach ($r in $rollouts | Sort-Object End) {
    # resets_at jitters by seconds between readings; a new window moves it by days.
    $reset = $prev -and [math]::Abs([double]$prev.Reset - [double]$r.Reset) -gt 3600
    $spent = if (-not $prev) { $r.Last - $r.First } elseif ($reset) { $r.Last } else { $r.Last - $prev.Last }
    $r | Add-Member -Force Spent $spent; $r | Add-Member -Force WindowReset $reset
    $prev = $r
  }
}

function Read-Rollout($file) {
  $hits = Select-String -LiteralPath $file -Pattern '"timestamp":"([^"]+)".*"used_percent":([\d.]+),"window_minutes":10080,"resets_at":(\d+)'
  if (-not $hits) { return }
  $model = (Select-String -LiteralPath $file -Pattern '"type":"turn_context".*?"model":"([^"]+)".*?"effort":"([^"]+)"' | Select-Object -First 1)
  $id = [regex]::Match($file.Name, '([0-9a-f]{8}-[0-9a-f-]{27})\.jsonl$').Groups[1].Value
  $g = { param($h, $i) $h.Matches[0].Groups[$i].Value }
  [pscustomobject]@{
    Thread = $id; File = $file.FullName
    Start = ([datetime](& $g $hits[0] 1)).ToLocalTime(); End = ([datetime](& $g $hits[-1] 1)).ToLocalTime()
    First = [double](& $g $hits[0] 2); Last = [double](& $g $hits[-1] 2); Reset = & $g $hits[-1] 3
    Model = if ($model) { "$($model.Matches[0].Groups[1].Value) $($model.Matches[0].Groups[2].Value)" } else { '?' }
  }
}

if ($SelfCheck) {
  $a = [pscustomobject]@{ End = 1; First = 10; Last = 12; Reset = 1000 }
  $b = [pscustomobject]@{ End = 2; First = 12; Last = 15; Reset = 1004 }
  $c = [pscustomobject]@{ End = 3; First = 1; Last = 2; Reset = 605000 }
  Measure-Spend @($c, $b, $a) ([pscustomobject]@{ Last = 9; Reset = 1000 })
  if ("$($a.Spent) $($b.Spent) $($c.Spent) $($c.WindowReset)" -ne '3 3 2 True') { throw "Measure-Spend: $($a.Spent) $($b.Spent) $($c.Spent)" }
  Measure-Spend @($a) $null
  if ($a.Spent -ne 2) { throw 'Measure-Spend without baseline' }
  'selftest ok'; return
}

$home_ = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
# .NET on Linux reports CreationTime as the last write, so there the start comes from the content or the name.
$all = Get-ChildItem (Join-Path $home_ 'sessions') -Recurse -Filter 'rollout-*.jsonl' |
  Where-Object { $_.LastWriteTime -ge $Since.AddDays(-2) -and ($IsLinux -or $_.CreationTime -le $Until) } |
  ForEach-Object { Read-Rollout $_ } | Where-Object { $_ }
$baseline = $all | Where-Object { $_.End -lt $Since } | Sort-Object End | Select-Object -Last 1
$run = @($all | Where-Object { $_.End -ge $Since -and $_.Start -le $Until })

# Stage logs name the ticket and stage; their first JSON line names the Codex thread.
$stages = Get-ChildItem (Join-Path $Tracker 'run-log') -Filter '*.txt' |
  Where-Object { $_.Name -match '^(.+)-(implement|review)-(\d{8}-\d{6})\.txt$' } |
  Where-Object { [datetime]::ParseExact($Matches[3], 'yyyyMMdd-HHmmss', $null) -ge $Since.AddMinutes(-1) } |
  ForEach-Object {
    $first = Get-Content -LiteralPath $_.FullName -TotalCount 1
    [pscustomobject]@{ Stage = $_.BaseName; Thread = [regex]::Match("$first", '"thread_id":"([^"]+)"').Groups[1].Value
      From = $(if ($IsLinux) { [datetime]::ParseExact(($_.BaseName -split '-')[-2..-1] -join '-', 'yyyyMMdd-HHmmss', $null) } else { $_.CreationTime }); To = $_.LastWriteTime }
  }
foreach ($r in $run) {
  $s = $stages | Where-Object { $_.Thread -eq $r.Thread } | Select-Object -First 1
  # A thread a stage spawned (proxy, subagent) runs inside that stage's time span.
  if (-not $s) { $s = $stages | Where-Object { $r.Start -ge $_.From -and $r.Start -le $_.To } | Select-Object -First 1 }
  $r | Add-Member -Force Stage $(if ($s) { $s.Stage } else { '(outside stages)' })
}
# Auto-review and subagent threads bill to the model of the stage that spawned them.
foreach ($r in $run) {
  $s = $stages | Where-Object { $_.Stage -eq $r.Stage } | Select-Object -First 1
  $main = if ($s) { $run | Where-Object { $_.Thread -eq $s.Thread } | Select-Object -First 1 }
  $r | Add-Member -Force StageModel $(if ($main) { $main.Model } else { $r.Stage })
}
Measure-Spend $run $baseline
"Baseline: $(if ($baseline) { "$($baseline.Last) % at $($baseline.End)" } else { 'none; first rollout counts from its first reading' })"
$run | Group-Object Stage | ForEach-Object { [pscustomobject]@{ Stage = $_.Name; Model = $_.Group[0].StageModel
    Threads = $_.Count; 'Weekly %' = ($_.Group | Measure-Object Spent -Sum).Sum; WindowReset = [bool]($_.Group | Where-Object WindowReset) } } |
  Format-Table -AutoSize | Out-String -Width 200
$run | Group-Object StageModel |
  ForEach-Object { [pscustomobject]@{ Model = $_.Name; Rollouts = $_.Count; 'Weekly %' = ($_.Group | Measure-Object Spent -Sum).Sum } } |
  Format-Table -AutoSize | Out-String
"Run total: $(($run | Measure-Object Spent -Sum).Sum) points of the weekly quota"
