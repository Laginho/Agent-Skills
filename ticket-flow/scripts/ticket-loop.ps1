<#
.SYNOPSIS
  Unattended ticket-flow driver. Feeds bare ticket ids to `claude -p`, one at a
  time, implement then review, and reads `Stage:` back. Adds no instructions of
  its own: behaviour lives in ticket-flow/SKILL.md.

.EXAMPLE
  .\ticket-loop.ps1 D:\Desktop\Projects\SIGAA-ME
  .\ticket-loop.ps1 D:\Desktop\Projects\SIGAA-ME -DryRun     # show what would run
#>
param(
  [Parameter(Mandatory)][string]$Repo,
  [string]$Tracker = '.scratch',
  [int]$ImplementMinutes = 45,
  [int]$ReviewMinutes = 20,
  [switch]$DryRun,
  [switch]$SelfCheck
)
$ErrorActionPreference = 'Stop'
Set-Location $Repo
$Repo = (Get-Location).Path

# PS 5.1 turns any stderr line (even a git warning) into a terminating error under
# 2>&1 with ErrorActionPreference=Stop, so judge git by its exit code only.
function GitOk {
  $ErrorActionPreference = 'Continue'
  $out = & git @args 2>&1 | ForEach-Object { "$_" }
  if ($LASTEXITCODE) { throw "git $args`n$($out -join "`n")" }
  $out
}
function Say($m) { Write-Host ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m) }

# --- bindings -----------------------------------------------------------------
$agents = if (Test-Path AGENTS.md) { 'AGENTS.md' } else { 'CLAUDE.md' }
$block = (Get-Content $agents -Raw -Encoding UTF8) -split '(?m)^## ' | Where-Object { $_ -like 'Bindings do fluxo*' }
if (-not $block) { throw "No '## Bindings do fluxo' block in $agents" }
$Gate   = [regex]::Match($block, 'Gate:\s*`([^`]+)`').Groups[1].Value
$Base   = [regex]::Match($block, 'Base branch:\s*`([^`]+)`').Groups[1].Value
$Model2 = [regex]::Match($block, 'stage 2 (\w+)').Groups[1].Value.ToLower()
$Model3 = [regex]::Match($block, 'stage 3 (\w+)').Groups[1].Value.ToLower()
if (-not ($Gate -and $Base -and $Model2 -and $Model3)) { throw "Bindings block incomplete:`n$block" }
$GateCmd = ($Gate -split ' ')[0]
# Prefix form `Bash(x:*)`, not glob `Bash(x *)`: measured 2026-09-12, `Bash(npx *)`
# was denied while `Bash(npx:*)` ran.
$Allowed = ('Bash(git:*)', 'Bash(gh:*)', "Bash(${GateCmd}:*)", 'Bash(npx:*)', 'Read', 'Edit', 'Write', 'Glob', 'Grep' | ForEach-Object { "`"$_`"" }) -join ' '

# --- local-only files (never dirty the tree) -----------------------------------
$RunLog = Join-Path $Repo "$Tracker/run-log.md"
$RunDir = Join-Path $Repo "$Tracker/run-log"
$exclude = '.git/info/exclude'
foreach ($p in "$Tracker/run-log.md", "$Tracker/run-log/") {
  if (-not (Select-String -Path $exclude -Pattern ([regex]::Escape($p)) -Quiet)) { Add-Content $exclude $p }
}
New-Item -ItemType Directory -Force $RunDir | Out-Null

# --- pre-flight: refuse unless conditions are ideal -----------------------------
function Preflight {
  if (GitOk status --porcelain) { throw 'Working tree not clean.' }
  $cur = GitOk rev-parse --abbrev-ref HEAD
  if ($cur -ne $Base) { throw "On '$cur', expected '$Base'." }
  GitOk fetch --quiet
  if ((GitOk rev-parse HEAD) -ne (GitOk rev-parse '@{u}')) { throw "Local $Base differs from remote." }
  # Stage 2 commits `implementing` on the ticket's branch, so the worktree copy still
  # reads `to-implement`. Read stages the way the loop does, or a run killed mid-stage
  # leaves a ticket no stage matches: skipped forever instead of stopping the next run.
  $inflight = @(AllTickets | Where-Object { $_.Stage -in 'implementing', 'reviewing' })
  if ($inflight) { throw "Tickets mid-run: $($inflight.Id -join ', ')" }
}

# --- tickets --------------------------------------------------------------------
function Field($text, $name) { [regex]::Match($text, "(?m)^$name`:\s*(.+?)\s*$").Groups[1].Value }
function Ticket($file) {
  $rel = (Resolve-Path -Relative $file) -replace '^\.[\\/]', '' -replace '\\', '/'
  $text = Get-Content $file -Raw -Encoding UTF8
  $id = [regex]::Match(($text -split "`n")[0], '\p{Lu}[\p{Lu}0-9]*-\d+').Value
  $branch = $id.ToLower()
  # Stage lives on the ticket's branch until merge: read it there if unmerged.
  # ...except `blocked` on the base branch, which is the driver parking it: that wins.
  if ($id -and (Field $text 'Stage') -ne 'blocked' -and (git branch --list $branch) -and -not (git branch --merged $Base --list $branch)) {
    $text = (git show "${branch}:$rel" 2>$null) -join "`n"
  }
  $blocked = (Field $text 'Blocked by') -split '[,\s]+' | Where-Object { $_ -match '^\p{Lu}[\p{Lu}0-9]*-\d+$' }
  $last = ([regex]::Matches($text, '(?m)^- .+$') | Select-Object -Last 1).Value
  [pscustomobject]@{ Id = $id; File = $rel; Branch = $branch; Stage = (Field $text 'Stage'); BlockedBy = $blocked; LastComment = $last }
}
function AllTickets { Get-ChildItem "$Tracker/*/issues/*.md" | Sort-Object FullName | ForEach-Object { Ticket $_.FullName } | Where-Object Id }
function NextTicket {
  $all = AllTickets
  $done = $all | Where-Object Stage -eq 'done' | ForEach-Object Id
  $r = $all | Where-Object Stage -eq 'to-review' | Select-Object -First 1
  if ($r) { return $r }
  $all | Where-Object { $_.Stage -eq 'to-implement' -and -not ($_.BlockedBy | Where-Object { $_ -notin $done }) } | Select-Object -First 1
}

# --- one claude session ----------------------------------------------------------
function RunStage($t, $model, $minutes, $label) {
  $log = Join-Path $RunDir ("{0}-{1}-{2}.txt" -f $t.Id, $label, (Get-Date -Format yyyyMMdd-HHmmss))
  $cliArgs = "-p `"$($t.Id)`" --model $model --effort high --permission-mode acceptEdits --allowedTools $Allowed"
  Say "$($t.Id) $label ($model, ${minutes}m) -> $log"
  if ($DryRun) { return 'dry-run' }
  $script:LastLog = $log
  $p = Start-Process claude -ArgumentList $cliArgs -WorkingDirectory $Repo -NoNewWindow -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err"
  $null = $p.Handle   # PS 5.1: without touching Handle, ExitCode reads back as null
  if (-not $p.WaitForExit($minutes * 60 * 1000)) {
    & taskkill /PID $p.Id /T /F | Out-Null
    return 'timeout'
  }
  # A session that dies before doing anything (auth, bad flags) is our problem,
  # not the ticket's: stop the run instead of blaming the ticket and retrying.
  if ($p.ExitCode -ne 0 -and (Get-Item $log).Length -lt 300) {
    throw "claude failed to start:`n$(Get-Content $log -Raw)`n$(Get-Content "$log.err" -Raw)"
  }
  $code = $p.ExitCode; $p.Dispose()
  return 'exit ' + $(if ($null -eq $code) { '?' } else { $code })
}

# The session's last words, one line: when stage 2 stops to ask, this is the question.
function LogTail($log, $chars = 1200) {
  $text = [IO.File]::ReadAllText($log)   # not Get-Content: works while the redirect handle is still open
  if ($text.Length -gt $chars) { $text = '...' + $text.Substring($text.Length - $chars) }
  ($text -replace '\r?\n', ' / ').Trim()
}

# Back to a clean base branch; drop the ticket's branch if asked.
function Reset-Tree($t, [switch]$DropBranch) {
  git checkout -q -f $Base; git reset -q --hard; git clean -qfd
  if ($DropBranch -and (git branch --list $t.Branch)) { git branch -q -D $t.Branch }
}

# Append to `## Comments` on the base branch and commit (the driver's only edits).
function Note($t, $line, $stage) {
  $text = Get-Content $t.File -Raw -Encoding UTF8
  if ($text -notmatch '(?m)^## Comments') { $text = $text.TrimEnd() + "`n`n## Comments`n" }
  $text = $text.TrimEnd() + "`n`n- $(Get-Date -Format yyyy-MM-dd) $line`n"
  if ($stage) { $text = $text -replace '(?m)^Stage: .+$', "Stage: $stage" }
  [IO.File]::WriteAllText((Join-Path $Repo $t.File), $text, [Text.UTF8Encoding]::new($false))
  # -F, not -m: a log tail with quotes or `--flags` inside splits into git options under PS 5.1.
  $msg = Join-Path $env:TEMP 'ticket-loop-commit.txt'
  [IO.File]::WriteAllText($msg, "chore: $line ($($t.Id))", [Text.UTF8Encoding]::new($false))
  GitOk add $t.File; GitOk commit -q -F $msg | Out-Null
  GitOk push -q
}

# One row per stage, not per ticket: the model and the time it burned are the two
# axes worth correlating later, and a per-ticket row cannot hold either.
function LogStage($t, $stage, $model, $attempt, $outcome, $started) {
  # The PR exists only once a review opened one; skip the network call otherwise.
  $pr = if ($stage -eq 'review') { gh pr list --head $t.Branch --state all --json url --jq '.[0].url' 2>$null }
  $mins = [int]((Get-Date) - $started).TotalMinutes
  Add-Content -Encoding UTF8 $RunLog ('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7}m |' -f `
    (Get-Date -Format 'yyyy-MM-dd HH:mm'), $t.Id, $stage, $model, $attempt, $outcome, $pr, $mins)
  Say "$($t.Id) $stage ($model): $outcome"
}

# --- what is left ------------------------------------------------------------------
# An indented tree, not a 2D graph: a terminal reads nesting, and this needs to cost
# nothing to look at. Only open tickets -- the done ones are in git if anyone asks.
function Walk($t, $depth, $open, $seen) {
  $pad = '  ' * ($depth + 1)
  if ($seen.ContainsKey($t.Id)) { Write-Host ('{0}{1} ...' -f $pad, $t.Id); return }
  $seen[$t.Id] = $true
  Write-Host ('{0}{1,-14}{2}' -f $pad, $t.Id, $t.Stage)
  # For anything parked on a human, the question itself. Printed, never stored: it
  # already lives in the ticket's `## Comments`, which is in git.
  if ($t.Stage -in 'blocked', 'to-merge') {
    $c = ($t.LastComment -replace '^- ', '').Trim()
    if ($c) { Write-Host ('{0}> {1}' -f $pad, $(if ($c.Length -gt 110) { $c.Substring(0, 110) + '...' } else { $c })) }
  }
  $open | Where-Object { $_.BlockedBy -contains $t.Id } | ForEach-Object { Walk $_ ($depth + 1) $open $seen }
}
function ShowTree($label) {
  $all = AllTickets
  $open = @($all | Where-Object Stage -ne 'done')
  if (-not $open) { Write-Host "`n${label}: nothing left."; return }
  $doneIds = $all | Where-Object Stage -eq 'done' | ForEach-Object Id
  $seen = @{}
  Write-Host ("`n{0} -- {1} open, indented under what blocks them:" -f $label, $open.Count)
  $open | Where-Object { -not ($_.BlockedBy | Where-Object { $_ -notin $doneIds }) } | ForEach-Object { Walk $_ 0 $open $seen }
  # A cycle, or a blocker that is itself unreachable, would otherwise print nothing.
  $open | Where-Object { -not $seen.ContainsKey($_.Id) } | ForEach-Object { Walk $_ 0 $open $seen }
}

function Median($v) { $s = @($v | Sort-Object); $s[[int][math]::Floor($s.Count / 2)] }

# Not the analysis -- the trigger for it. Correlating ticket shape against model and
# duration needs something that reads prose; this just says when it is worth asking.
function ShowSummary {
  if (-not (Test-Path $RunLog)) { return }
  $rows = @(foreach ($l in (Get-Content $RunLog -Encoding UTF8)) {
    $c = @($l -split '\|' | ForEach-Object { $_.Trim() })
    if ($c.Count -eq 10 -and $c[1] -match '^\d{4}-\d\d-\d\d') { , $c }
  })
  if (-not $rows) { return }
  $med = { param($stage)
    $v = @($rows | Where-Object { $_[3] -eq $stage } | ForEach-Object { [int]($_[8] -replace '\D', '') })
    if ($v.Count) { '{0}m' -f (Median $v) } else { 'n/a' } }
  $n = { param($pat) @($rows | Where-Object { $_[6] -match $pat }).Count }
  Write-Host ("`n{0} stages | {1} merged | {2} reopened | {3} retries | implement {4} ({5}) | review {6} ({7})" -f `
    $rows.Count, (& $n '^merged$'), (& $n '^reopened$'), (& $n '^failed'), (& $med 'implement'), $Model2, (& $med 'review'), $Model3)
}

if ($SelfCheck) {
  # Median is the only arithmetic here and it was wrong once: [int](3/2) is 2 in PS.
  if ((Median @(12, 45, 20)) -ne 20) { throw 'Median: odd count' }
  if ((Median @(5, 8)) -ne 8) { throw 'Median: even count' }
  if ((Median @(7)) -ne 7) { throw 'Median: single' }
  Write-Host 'Self-check OK'; exit 0
}

# --- main loop --------------------------------------------------------------------
# Before Preflight on purpose: a run it refuses should still tell you where you are.
ShowTree 'Before this run'
if (-not $DryRun) { Preflight }
$hdr = '| When | ID | Stage | Model | Attempt | Outcome | PR | Took |'
$sep = '|---|---|---|---|---|---|---|---|'
if (-not (Test-Path $RunLog)) { Set-Content -Encoding UTF8 $RunLog "$hdr`n$sep" }
elseif (-not (Select-String -Path $RunLog -SimpleMatch $hdr -Quiet)) {
  # Old rows were one per ticket and carried no model. Backfilling the split would
  # invent durations that were never measured: leave them, start a second table.
  Add-Content -Encoding UTF8 $RunLog "`n### Schema change: one row per stage, with the model`n`n$hdr`n$sep"
}
Say "Gate '$Gate', base '$Base', stage 2 $Model2, stage 3 $Model3"

try {
while ($t = NextTicket) {
  $attempt = 1 + ((Get-Content $t.File -Raw -Encoding UTF8) | Select-String -AllMatches 'Attempt \d+ failed').Matches.Count
  if ($t.Stage -eq 'to-implement') {
    # A reopened ticket's branch holds the previous pass (tests + code): only a
    # branch this attempt created is safe to drop.
    $hadBranch = [bool](git branch --list $t.Branch)
    $started = Get-Date
    $res = RunStage $t $Model2 $ImplementMinutes 'implement'
    if ($DryRun) { break }
    $t = Ticket (Join-Path $Repo $t.File)
    if ($t.Stage -ne 'to-review') {
      $tail = LogTail $script:LastLog
      Reset-Tree $t -DropBranch:(-not $hadBranch)
      if ($attempt -ge 2) { Note $t "Attempt $attempt failed: $res; blocked after two attempts. Log tail: $tail" 'blocked'; LogStage $t 'implement' $Model2 $attempt "failed ($res), blocked" $started }
      else { Note $t "Attempt $attempt failed: $res. Log tail: $tail"; LogStage $t 'implement' $Model2 $attempt "failed ($res), will retry" $started }
      continue
    }
    LogStage $t 'implement' $Model2 $attempt 'to-review' $started
  }
  $started = Get-Date
  $res = RunStage $t $Model3 $ReviewMinutes 'review'
  if ($DryRun) { break }
  Reset-Tree $t
  GitOk pull -q --ff-only
  $t = Ticket (Join-Path $Repo $t.File)
  $names = @{ 'done' = 'merged'; 'to-merge' = 'waiting for you'; 'to-implement' = 'reopened' }
  $outcome = if ($names[$t.Stage]) { $names[$t.Stage] } else { "review ended at $($t.Stage) ($res)" }
  LogStage $t 'review' $Model3 $attempt $outcome $started
  # A review that stopped short of a verdict (`to-review`, `reviewing`) would be
  # picked again forever or never again: park it for a human.
  if (-not $names[$t.Stage]) { Note $t "Review ended at $($t.Stage) ($res); branch $($t.Branch) holds the review; left for a human" 'blocked' }
}
Say 'Nothing runnable. Done.'
} finally {
  # A run that crashed is when you most want the state, so this lives in finally --
  # after Reset-Tree, or the tree would read tickets off whatever branch it died on.
  if (-not $DryRun) { Reset-Tree $null }
  ShowTree 'After this run'
  ShowSummary
}
