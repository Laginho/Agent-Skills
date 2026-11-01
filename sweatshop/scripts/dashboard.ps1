# The driver's side of sweatshop/dashboard (worker.js holds the snapshot's shape): one
# snapshot per lane, POSTed at run start, stage start, stage end and exit, and re-sent by
# DashTick from Invoke-StageProcess's poll as the heartbeat. Reporting never stops a lane:
# a failed post is one console line per run of failures, and the run goes on.
# Off unless both SWEATSHOP_DASH_URL and SWEATSHOP_DASH_TOKEN are set.
$DashUrl = "$env:SWEATSHOP_DASH_URL".TrimEnd('/')
$DashToken = $env:SWEATSHOP_DASH_TOKEN
$DashOn = [bool]($DashUrl -and $DashToken)
$DashEvery = [timespan]::FromMinutes(2)
$DashEvents = [Collections.Generic.List[object]]::new()
$DashSnap = $null; $DashFailing = $false; $DashLastPost = [datetime]::MinValue
# Waiting on a human: the lane's needsHuman, and the tickets whose note the card shows.
$DashHuman = 'blocked', 'to-merge', 'invalid-handoff'
# Every Invoke-StageProcess in this process ticks, the proxy's calls included: a 30-minute
# proxy answer must not read as a dead lane.
$StageTick = { DashTick }
if ($DashOn) { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 }

function Clip($s, $n) { $s = "$s"; if ($s.Length -gt $n) { $s.Substring(0, $n) + '...' } else { $s } }

# Say's lines are the card's events; the last 8 ride in every snapshot.
function Add-DashEvent($text) {
  $DashEvents.Add([ordered]@{ at = (Get-Date).ToUniversalTime().ToString('o'); text = Clip $text 300 })
  while ($DashEvents.Count -gt 8) { $DashEvents.RemoveAt(0) }
}

# A ticket as the card shows it. The title is the file's first line without the id; the
# note only where a human is waited on, as ShowTree prints it.
function DashTicket($t) {
  $title = (("$($t.Text)" -split '\r?\n')[0] -replace '^#+\s*' -replace [regex]::Escape("$($t.Id)") -replace '^[\s:\u2013\u2014-]+').Trim()
  $note = if ($t.Stage -in $DashHuman) { if ($t.HandoffError) { $t.HandoffError } else { ("$($t.LastComment)" -replace '^- ', '').Trim() } }
  [ordered]@{ id = $t.Id; title = $title; state = $t.Stage; note = Clip $note 300 }
}

# Today's spend: the priced Cost cells of today's run-log rows (local date, as the rows are),
# prefixed with U+2265 (>=) when a row of today is `?`. $null when nothing ran today.
function DashCost($logText, $today) {
  $sum = 0.0; $partial = $false; $rows = 0
  foreach ($l in "$logText" -split '\r?\n') {
    $c = @($l -split '\|' | ForEach-Object { $_.Trim() })
    if ($c.Count -ne 13 -or -not $c[1].StartsWith($today)) { continue }   # the current 11-column schema only
    $rows++
    if ($c[10] -match '^\$(\d+(?:\.\d+)?)$') { $sum += [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) }
    else { $partial = $true }
  }
  if (-not $rows) { return $null }
  $(if ($partial) { [string][char]0x2265 } else { '' }) + [string]::Format([Globalization.CultureInfo]::InvariantCulture, '${0:0.000}', $sum)
}

# Rebuild the lane's snapshot from git and the run log, then post it. Costs one git read per
# ticket: called at run start, stage start, stage end and exit, never from the tick.
function Report-Dash($driver = 'running', $current = $null) {
  if (-not $DashOn) { return }
  if (-not $script:DashProject) { $script:DashProject = try { RepoName (GitOk remote get-url origin) } catch { Split-Path $Repo -Leaf } }
  $tickets = if ($script:DashSnap) { $script:DashSnap.tickets }
  try {
    $open = @(AllTickets | Where-Object { $_.Stage -ne 'done' -and (InLane $_) })
    $done = @(CompletedTickets | Where-Object { InLane $_ })
    $tickets = @(@($open) + @($done) | ForEach-Object { DashTicket $_ })
  } catch { Write-Host ("[{0}] dashboard: ticket list unavailable, keeping the last one: {1}" -f (Get-Date -Format HH:mm:ss), $_.Exception.Message) }
  $cost = try { DashCost (Read-StageLog $RunLog) (Get-Date -Format yyyy-MM-dd) } catch { $null }
  $script:DashSnap = [ordered]@{
    project = $script:DashProject; lane = $(if ($Lane) { $Lane } else { 'main' }); pc = [Environment]::MachineName
    foreman = $env:SWEATSHOP_FOREMAN; session = $Loop; driver = $driver; current = $current
    tickets = @($tickets); needsHuman = @($tickets | Where-Object { $_.state -in $DashHuman })
    events = @(); pr = $script:PrUrl; costToday = $cost; updatedAt = $null
  }
  Send-Dash
}

function Send-Dash {
  $script:DashLastPost = Get-Date
  if (-not ($DashOn -and $script:DashSnap)) { return }
  $script:DashSnap.events = @($DashEvents.ToArray())
  $script:DashSnap.updatedAt = (Get-Date).ToUniversalTime().ToString('o')
  $ProgressPreference = 'SilentlyContinue'
  try {
    # Bytes, not a string: PS 5.1 would send a string body as ISO-8859-1.
    $body = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $script:DashSnap -Depth 6 -Compress))
    $null = Invoke-RestMethod -Method Post -Uri "$DashUrl/api/lane" -Headers @{ Authorization = "Bearer $DashToken" } `
      -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 5
    $script:DashFailing = $false
  } catch {
    if (-not $script:DashFailing) { Write-Host ("[{0}] dashboard: post failed, retrying at the next event: {1}" -f (Get-Date -Format HH:mm:ss), $_.Exception.Message) }
    $script:DashFailing = $true
  }
}

# The heartbeat: the held snapshot again, at most once per $DashEvery.
function DashTick { if ((Get-Date) - $script:DashLastPost -ge $DashEvery) { Send-Dash } }
