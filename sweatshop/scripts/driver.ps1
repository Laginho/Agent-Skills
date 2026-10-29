<#
.SYNOPSIS
  Sweatshop: the unattended ticket-flow driver. Feeds bare ticket ids to fresh
  Claude Code, Codex or OpenCode CLI sessions, implement then review, and reads `Stage:` back.
  Merged tickets collect on one `sweatshop/*` session branch; one PR at the end.
  Adds no instructions of its own: behaviour lives in ticket-flow/SKILL.md.

.EXAMPLE
  .\sweatshop.ps1 D:\Desktop\Projects\SIGAA-ME
  .\sweatshop.ps1 D:\Desktop\Projects\SIGAA-ME -Lineup opus   # the `Models (opus):` line
  .\sweatshop.ps1 D:\Desktop\Projects\SIGAA-ME -DryRun     # show what would run
#>
param(
  [Parameter(Mandatory)][string]$Repo,
  [string]$Tracker = '.scratch',
  [int]$ImplementMinutes = 60,
  [int]$ReviewMinutes = 60,
  [switch]$DryRun,
  [switch]$SelfCheck,
  # The `Models (<name>):` line to run. Absent: the one `Models (default):` names.
  [string]$Lineup,
  # A lineup for this run only, in the binding's own syntax: 'stage 2 gpt-6-luna max, stage 3 opus-5.5 high'.
  # Never written to the repo: editing the binding would dirty the tree Preflight wants clean.
  [string]$Models,
  # A tracker folder (`<tracker>/<lane>/issues`). Lanes run side by side, one clone each,
  # each on its own session `sweatshop/<lane>/<stamp>`; only that folder's tickets run.
  [string]$Lane
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'stage-runtime.ps1')
. (Join-Path $PSScriptRoot 'ticket-state.ps1') -Repo $Repo
. (Join-Path $PSScriptRoot 'gate-evidence.ps1') -Repo $Repo
. (Join-Path $PSScriptRoot 'proxy.ps1') -Repo $Repo
Set-Location $Repo
$Repo = (Get-Location).Path
if ($Lane -and -not $SelfCheck -and -not (Test-Path "$Tracker/$Lane/issues")) { throw "Lane '$Lane': no $Tracker/$Lane/issues in $Repo." }

# PS 5.1 turns any stderr line (even a git warning) into a terminating error under
# 2>&1 with ErrorActionPreference=Stop, so judge git by its exit code only. Merged
# stderr comes back as ErrorRecord: keep it for the throw, never in the return value.
# Measured 2026-09-15: push's "remote: Create a pull request" banner rode out of
# Use-Session, $Loop became an array, and every later `git ... $Loop` was a pathspec error.
function GitOk {
  $ErrorActionPreference = 'Continue'
  # Windows PowerShell decodes native output with the console's OEM code page, so a
  # ticket's `Débito humano` came back as mojibake and dropped out of the PR body.
  try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
  $out = & git @args 2>&1
  if ($LASTEXITCODE) { throw "git $args`n$(($out | ForEach-Object { "$_" }) -join "`n")" }
  $out | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] } | ForEach-Object { "$_" }
}
function Say($m) { Write-Host ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m) }
# Runs in parallel on other repos share this machine. A named mutex dies with its
# process, so a killed run never leaves one held. $null when $ms runs out.
function Lock($name, $ms) {
  $m = [Threading.Mutex]::new($false, $name)
  try { if (-not $m.WaitOne($ms)) { $m.Dispose(); return $null } } catch [Threading.AbandonedMutexException] { }
  $m
}

# --- bindings -----------------------------------------------------------------
$agents = if (Test-Path AGENTS.md) { 'AGENTS.md' } else { 'CLAUDE.md' }
$block = (Get-Content $agents -Raw -Encoding UTF8) -split '(?m)^## ' | Where-Object { $_ -like 'Bindings do fluxo*' }
if (-not $block) { throw "No '## Bindings do fluxo' block in $agents" }
$Gate   = [regex]::Match($block, 'Gate:\s*`([^`]+)`').Groups[1].Value
$Base   = [regex]::Match($block, 'Base branch:\s*`([^`]+)`').Groups[1].Value
# What a test-only commit may touch. `Test files:` adds a repo's fixtures that live beside
# production (EasyMath's shared JSON cases); the tracker is metadata, allowed in any commit.
$TestFiles = '(?i)(^|/)(tests?|__tests__|__snapshots__|fixtures|integration_test|androidTest|e2e)/|[._-](test|spec)\.[^/.]+$|(^|/)test_[^/]+$'
$extraTests = [regex]::Match($block, 'Test files:\s*`([^`]+)`').Groups[1].Value
if ($extraTests) { $TestFiles += "|$extraTests" }
# `opus 5.5` and `opus-5.5` both read as `opus-5.5`, the bench's label; effort is
# optional and defaults to high. A trailing `fast` (Codex's /fast, the priority tier)
# logs as `<model>-fast`: another row in the scoreboard, and `?` cost until priced.
# Returns model, effort; $null when the stage is absent.
# $n is a stage number, or `hard` for the implementer of hard tickets.
function StageModel($line, $n) {
  $key = if ("$n" -match '^\d+$') { "stage $n" } else { $n }
  $m = [regex]::Match("$line", "\b$key (\w[\w./#-]*(?: \d+(?:\.\d+)*)?)(?: (low|medium|high|xhigh|max|ultra))?( fast)?")
  if (-not $m.Success) { return $null }
  # An OpenCode id goes to its CLI as written: a provider's ids may be mixed-case.
  if ($m.Groups[1].Value -match '/') { $m.Groups[1].Value + $(if ($m.Groups[3].Success) { '-fast' }) }
  # One label per model in the run log: `claude-opus-5-5` from a binding reads as `opus-5.5`.
  else { (($m.Groups[1].Value -replace ' ', '-').ToLower() -replace '^claude-([a-z]+)-(\d+)-(\d+)$', '$1-$2.$3' -replace '^claude-', '') + $(if ($m.Groups[3].Success) { '-fast' }) }
  if ($m.Groups[2].Success) { $m.Groups[2].Value } else { 'high' }
}

# A lineup is one `Models (<name>):` line. `Models (default): <name>` names the
# lineup a run without -Lineup takes. Only the default falls back to the legacy
# `Models (Claude):`, then `Models:`; a named lineup that is missing is refused, never borrowed.
# Not `$models`: PowerShell names are case-blind, and that is the -Models parameter.
if ($Models -and $Lineup) { throw 'Pass -Lineup or -Models, not both.' }
function LineupLine($name) { [regex]::Match($block, "(?im)^\s*-\s*Models \($([regex]::Escape($name))\):\s*(.+)$").Groups[1].Value.Trim() }
$LineupName = if ($Models) { 'ad hoc' } elseif ($Lineup) { $Lineup } else { 'default' }
$line = if ($Models) { $Models } else { LineupLine $LineupName }
if ($line -match '^[\w.-]+$') { $LineupName = $line; $line = LineupLine $LineupName }
if (-not $line -and -not $Lineup -and -not $Models) { $LineupName = 'Claude'; $line = LineupLine 'Claude' }
if (-not $line -and -not $Lineup -and -not $Models) { $line = [regex]::Match($block, '(?im)^\s*-\s*Models:\s*(.+)$').Groups[1].Value }
$Model2, $Effort2 = StageModel $line 2
$Model3, $Effort3 = StageModel $line 3
# Only the implementer changes for a hard ticket: the reviewer has to be good enough for all of them.
$ModelHard, $EffortHard = StageModel $line 'hard'
# The limits catch a hung session, not a slow one. Measured 2026-10-17: with four lanes a
# review that commits a fix reruns a 9-15 min gate, and five such reviews died at 20 min;
# implements reached 44-45 of 45 min.
if (-not ($Gate -and $Base -and $Model2 -and $Model3)) { throw "Bindings block incomplete for lineup '$LineupName' (Gate, Base branch, stage 2 and 3 models):`n$(if ($Models) { $Models } else { $block })" }
# An unversioned alias moves when Anthropic ships the next model, and the lineup
# changes under a run with nobody told. Pin it.
foreach ($m in @($Model2, $Model3, $ModelHard) | Where-Object { $_ }) {
  if ((RuntimeOf $m) -ne 'Codex' -and $m -match '-fast$') { throw "fast is Codex's service tier; '$m' runs on $(RuntimeOf $m)." }
  if ((RuntimeOf $m) -eq 'Claude' -and $m -notmatch '\d') { throw "Claude model '$m' has no version. Write it as opus-5.5, sonnet-5, fable-5.1 or haiku-4.5." }
}

# --- CLIs -------------------------------------------------------------------------
$Cli = @{}
foreach ($rt in @($Model2, $Model3, $ModelHard) | Where-Object { $_ -and -not ($DryRun -or $SelfCheck) } | ForEach-Object { RuntimeOf $_ } | Select-Object -Unique) {
  $Cli[$rt] = FindCli $rt
  Say "${rt}: $($Cli[$rt])"
  if ($rt -eq 'Codex' -and -not ($DryRun -or $SelfCheck)) {
    $ErrorActionPreference = 'Continue'
    $null = & $Cli[$rt] login status 2>&1
    $loginCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($loginCode) { throw 'Codex CLI is not logged in. Run codex login before starting the driver.' }
  }
}
$Loop = $Base   # the loop's base: the session branch once Use-Session picks one
$GateCmd = ($Gate -split ' ')[0]
# Prefix form `Bash(x:*)`, not glob `Bash(x *)`: measured 2026-09-12, `Bash(npx *)`
# was denied while `Bash(npx:*)` ran. The same prefixes again for the PowerShell tool:
# measured 2026-10-02, sonnet-5.5 on Windows ran the gate through it, every call was
# denied, and SYN-019 burned an attempt asking for approval in 2 minutes.
$Allowed = (@('git', 'gh', $GateCmd, 'npx', 'node', 'powershell', 'flutter', 'dart') | ForEach-Object { "Bash(${_}:*)"; "PowerShell(${_}:*)" }) + ('Read', 'Edit', 'Write', 'Glob', 'Grep', 'Agent') | ForEach-Object { "`"$_`"" }
$Allowed = $Allowed -join ' '

# --- local-only files (never dirty the tree) -----------------------------------
$RunLog = Join-Path $Repo "$Tracker/run-log.md"
$RunDir = Join-Path $Repo "$Tracker/run-log"
$exclude = '.git/info/exclude'
if (-not ($DryRun -or $SelfCheck)) {
foreach ($p in "$Tracker/run-log.md", "$Tracker/run-log/") {
  if (-not (Select-String -Path $exclude -Pattern ([regex]::Escape($p)) -Quiet)) { Add-Content $exclude $p }
}
New-Item -ItemType Directory -Force $RunDir | Out-Null
}

# --- pre-flight: refuse unless conditions are ideal -----------------------------
function Preflight {
  if (GitOk status --porcelain) { throw 'Working tree not clean.' }
  $cur = GitOk rev-parse --abbrev-ref HEAD
  if ($cur -ne $Base) { throw "On '$cur', expected '$Base'." }
  GitOk pull -q --ff-only   # the human merged a session PR on GitHub; bring it here
}
# Stage 2 commits `implementing` on the ticket's branch, so the worktree copy still
# reads `to-implement`. Read stages the way the loop does, or a run killed mid-stage
# leaves a ticket no stage matches: skipped forever instead of stopping the next run.
# After Use-Session: a branch already merged into the session must not count.
function NoneInflight {
  # Another lane's tickets are mid-run on its own session, by design.
  $mine = @(AllTickets | Where-Object { InLane $_ })
  $invalid = @($mine | Where-Object HandoffError)
  if ($invalid) { throw ($invalid.HandoffError -join "`n") }
  $inflight = @($mine | Where-Object { $_.Stage -in 'implementing', 'reviewing' })
  if ($inflight) { throw "Tickets mid-run: $($inflight.Id -join ', ')" }
}

# --- session branch -----------------------------------------------------------------
# Every merged ticket of a run lands here, and the human gets one PR at the end
# instead of one per ticket. ticket-flow sessions find it by name, so the prompt
# stays a bare id. Reused until its PR is merged; remote first, the other machine
# may have started it.
function Use-Session {
  if (-not $DryRun) { GitOk fetch -q --prune }
  $remoteRefs = @(GitOk for-each-ref --no-merged $Base --format='%(refname:short)' 'refs/remotes/origin/sweatshop')
  $localRefs = @(GitOk for-each-ref --no-merged $Base --format='%(refname:short)' 'refs/heads/sweatshop')
  $open = @(@($remoteRefs + $localRefs) | ForEach-Object { $_ -replace '^origin/', '' } | Select-Object -Unique)
  # A run without a lane takes every tracker folder, so it never shares the repo with lanes.
  $laned = @($open | Where-Object { $_ -match '^sweatshop/[^/]+/' })
  if ($Lane -and $open.Count -gt $laned.Count) { throw "A session without a lane is open: $(($open | Where-Object { $_ -notin $laned }) -join ', '). Merge it before running lanes." }
  if (-not $Lane -and $laned) { throw "Lane sessions are open: $($laned -join ', '). Run with -Lane <folder>, or merge them first." }
  if ($Lane) {
    $remoteRefs = @($remoteRefs | Where-Object { $_ -like "origin/sweatshop/$Lane/*" })
    $localRefs = @($localRefs | Where-Object { $_ -like "sweatshop/$Lane/*" })
  }
  $sessions = @(@($remoteRefs + $localRefs) | ForEach-Object { $_ -replace '^origin/', '' } | Select-Object -Unique)
  if ($sessions.Count -gt 1) { throw "Ambiguous open sessions: $($sessions -join ', '). Choose/reconcile the session before running." }
  $remote = $remoteRefs | Select-Object -First 1
  $local = $localRefs | Select-Object -First 1
  if ($remote) {
    $s = $remote -replace '^origin/', ''
    if (-not $DryRun) { GitOk checkout -q $s; GitOk pull -q --ff-only }
  } elseif ($local) {
    $s = $local
    if (-not $DryRun) { GitOk checkout -q $s; GitOk push -q -u origin $s }
  } else {
    $s = 'sweatshop/' + $(if ($Lane) { "$Lane/" }) + (Get-Date -Format yyyy-MM-dd-HHmm)
    # The empty commit is load-bearing: a session equal to its base counts as merged
    # into it, so the search above and ticket-flow's both miss it. Measured
    # 2026-09-24: SYN-011's review took main as its base and merged a PR there.
    if (-not $DryRun) { GitOk checkout -q -b $s $Base; GitOk commit -q --allow-empty -m "chore: open session $s"; GitOk push -q -u origin $s }
  }
  if ($DryRun -and $remote -and -not $local) { $remote } else { $s }
}

# --- tickets --------------------------------------------------------------------
# Headers come in both shapes: `Stage: x` (this loop's template) and `**Stage:** x`
# (what the vendored tracker writes around it). Measured 2026-09-15: the plain-only
# regex read every bold ticket as stageless -- open tickets closed, nothing runnable.
function Field($text, $name) { [regex]::Match($text, "(?m)^\*{0,2}$name\*{0,2}`:\*{0,2}\s*(.+?)\s*$").Groups[1].Value }
# Stage 2 often writes the receipt as a bullet with a note: `- Gate evidence: <path> (note)`.
# Measured 2026-10-24: that shape parked three valid P-Chess handoffs. Only this field
# takes bullets; a comment bullet such as `- Stage: ...` must not move a ticket. A note is
# dropped only after `.json`, so `C:\a (x86)\r.json` and `receipt (1)` stay whole paths.
function GateEvidenceField($text) { [regex]::Match($text, '(?m)^(?:[-*]\s+)?\*{0,2}Gate evidence\*{0,2}:\*{0,2}\s*(.+?)(?:(?<=\.(?i:json))\s+\(.*\))?\s*$').Groups[1].Value }
function Ticket($file) {
  $rel = [IO.Path]::GetFullPath($file).Substring($Repo.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
  $text = (GitOk show "${Loop}:$rel") -join "`n"
  $id = [regex]::Match(($text -split "`n")[0], '\p{Lu}[\p{Lu}0-9]*-\d+').Value
  # Stage 2 names the branch `<prefix>/<ID>-<slug>` (AGENTS.md); the slug is the
  # agent's, so find it instead of guessing. Measured 2026-09-14: guessing `phy-20`
  # never matched `phy/PHY-20-...`, so every unmerged ticket read its stage off main.
  # An ambiguous branch is this ticket's problem, not the run's: every loop reads every
  # ticket. Measured 2026-10-11: a pushed EDIT-001, rebased locally by review, threw
  # here once per loop and killed the driver with six tickets runnable.
  $activeBranch = $null; $lookupError = $null
  if ($id) { try { $activeBranch = Find-TicketBranch $Repo $id -Remote } catch { $lookupError = $_.Exception.Message } }
  $branch = $activeBranch
  if (-not $branch) { $branch = $id.ToLower() }
  # Stage lives on the ticket's branch until merge: read it there if unmerged.
  # ...except `blocked` on the base branch, which is the driver parking it: that wins.
  $unmerged = $activeBranch -and -not (Test-GitAncestor $Repo $branch $Loop) -and -not (Test-SpentBranch $branch $rel)
  $sessionStage = Field $text 'Stage'
  if ($unmerged -and $sessionStage -ne 'blocked') {
    $text = (git show "${branch}:$rel" 2>$null) -join "`n"
  }
  $blocked = (Field $text 'Blocked by') -split '[,\s]+' | Where-Object { $_ -match '^\p{Lu}[\p{Lu}0-9]*-\d+$' }
  $last = ([regex]::Matches($text, '(?m)^- .+$') | Select-Object -Last 1).Value
  # Tickets that predate this loop carry only the vendored `Status:`. A closed one is
  # done; an open one has no stage to dispatch on, so it shows in the tree and never runs.
  $stage = Field $text 'Stage'
  if (-not $stage -and (Field $text 'Status') -in 'complete', 'resolved', 'wontfix') { $stage = 'done' }
  # Parked `blocked` on the session already waits for a human; the ambiguity rides along in its note.
  $handoffError = if ($lookupError -and $stage -ne 'blocked') { $lookupError }
  elseif ($unmerged -and $stage -eq 'done') { "$id claims done on unmerged branch $branch; inspect and merge or reopen the preserved work." }
  if ($handoffError) { $stage = 'invalid-handoff' }
  # The last verdict is the review that closed it; a reopened ticket carries older ones.
  $vm = [regex]::Matches($text, '(?m)^Verdict:\s*(.+?)\s*$')
  $verdict = if ($vm.Count) { $vm[$vm.Count - 1].Groups[1].Value }
  [pscustomobject]@{ Id = $id; File = $rel; Branch = $branch; Stage = $stage; BlockedBy = $blocked; LastComment = $last
                     Review = $(if (Field $text 'Review') { Field $text 'Review' } else { 'agent' }); Verdict = $verdict
                     Difficulty = Field $text 'Difficulty'; Reopens = Reopens $text; Text = $text
                     GateEvidence = GateEvidenceField $text; HandoffError = $handoffError }
}
# A rebased PR leaves its pre-rebase branch unmerged by ancestry. It is spent when the
# session or base already says done and every commit of it landed by patch-id (`git cherry`
# prints no `+`). Measured 2026-10-25: four such P-Chess branches read done tickets as
# to-review; CLEAN-002 was reviewed again and committed blocked.
# shortcut: a squash merge matches no patch-id, so its branch still reads; delete such branches after merge.
function Test-SpentBranch($branch, $rel) {
  foreach ($ref in @($Loop, $Base | Select-Object -Unique)) {
    $text = try { (GitOk show "${ref}:$rel") -join "`n" } catch { '' }
    if ((Field $text 'Stage') -eq 'done' -and -not (@(GitOk cherry $ref $branch) -match '^\+')) { return $true }
  }
  $false
}
# Every reopen leaves a `Verdict: Reopen ...` line in the ticket (ticket-flow, Reopening).
function Reopens($text) { ([regex]::Matches($text, '(?m)^Verdict:\s*Reopen')).Count }
# Stage 1 marks the tickets it expects to be hard; two reopens show the ones it missed.
# Measured 2026-09-29: CONT-005 took five passes on gpt-6-luna, then two on sonnet-5.5.
# No `hard` in the lineup: every ticket runs on stage 2's model.
function Implementer($t) {
  if ($ModelHard -and ($t.Difficulty -eq 'hard' -or $t.Reopens -ge 2)) { return $ModelHard, $EffortHard }
  $Model2, $Effort2
}
function AllTickets {
  GitOk ls-tree -r --name-only $Loop -- "$Tracker/" | Where-Object { $_ -like "$Tracker/*/issues/*.md" } |
    Sort-Object | ForEach-Object { Ticket (Join-Path $Repo $_) } | Where-Object Id
}
# Blockers count as done from any folder; only the lane's own tickets run.
function InLane($t) { -not $Lane -or $t.File -like "$Tracker/$Lane/issues/*" }
function NextTicket {
  $all = AllTickets
  $done = $all | Where-Object Stage -eq 'done' | ForEach-Object Id
  $mine = @($all | Where-Object { InLane $_ })
  $r = $mine | Where-Object Stage -eq 'to-review' | Select-Object -First 1
  if ($r) { return $r }
  $mine | Where-Object { $_.Stage -eq 'to-implement' -and -not ($_.BlockedBy | Where-Object { $_ -notin $done }) } | Select-Object -First 1
}

# --- one fresh CLI session -------------------------------------------------------
# A ticket stage and the proxy ping run with the same flags, so the ping proves what stages get.
function StageArgs($rt, $model, $effort, $prompt, $title, $final) {
  if ($rt -eq 'Claude') {
    # JSON for the usage; its `result` goes to `.final`, the same place Codex puts its last message.
    "-p `"$prompt`" --model $(CliModel $model) --effort $effort --output-format json --permission-mode acceptEdits --allowedTools $Allowed"
  } elseif ($rt -eq 'OpenCode') {
    # OpenCode takes its project from an inherited PWD over its real cwd; a driver launched
    # from Git Bash ran stage 2 in the shell's repo (measured 2026-10-27).
    $env:PWD = $Repo
    # Its own server per stage (--standalone), so a timeout kill stops the agent too, and
    # not the user's background service. --auto approves what the config does not deny.
    # No effort flag: a variant is model-specific (`#high` is refused where the model has
    # none), so it rides in the model id. It reads no global CLAUDE.md, so the bare-id
    # rule is not there: name the skill (routing, not behaviour; measured 2026-10-27).
    "run --standalone --auto --format json --model $model --title `"$title`" `"$prompt`""
  } else {
    # Sandboxed, with escalations judged by Codex's automatic reviewer: the Windows
    # workspace-write sandbox keeps .git read-only and cannot reach the keyring, so
    # git and gh fail once and pass on the approved retry (measured 2026-10-02).
    $tier = if ($model -match '-fast$') { ' --config service_tier=fast' }
    "exec --model $($model -replace '-fast$') --config model_reasoning_effort=$effort$tier --approve-for-me --json --output-last-message `"$final`" `"$prompt`""
  }
}

function RunStage($t, $model, $effort, $minutes, $label) {
  $log = Join-Path $RunDir ("{0}-{1}-{2}.txt" -f $t.Id, $label, (Get-Date -Format yyyyMMdd-HHmmss))
  $rt = RuntimeOf $model; $exe = $Cli[$rt]
  $prompt = if ($rt -eq 'OpenCode') { "Use the ticket-flow skill on $($t.Id)." } else { $t.Id }
  $cliArgs = StageArgs $rt $model $effort $prompt "$($t.Id) $label" "$log.final"
  Say "$($t.Id) $label ($model $effort, ${minutes}m) -> $log"
  if ($DryRun) { Say "$exe $cliArgs"; return 'dry-run' }
  $script:LastLog = $log; $script:LastUsage = $null
  $script:LastInfrastructureError = $null
  $script:LastFailureKind = 'infrastructure'
  # Only commits this stage makes face the test/production check: a reopen keeps the last pass.
  $from = & git rev-parse -q --verify "$($t.Branch)^{commit}" 2>$null
  $env:SWEATSHOP_PROXY = if ($script:ProxyVia -and $script:ProxyVia[$rt] -eq 'driver') { 'driver' } else { $null }
  $run = Invoke-StageProcess $exe $cliArgs $Repo $log $rt ($minutes * 60)
  $env:SWEATSHOP_PROXY = $null
  $script:LastInfrastructureError = $run.InfrastructureError
  $script:LastShutdownSeconds = $run.ShutdownSeconds
  try {
    if ($rt -eq 'Claude') {
      try { $j = (Read-StageLog $log) | ConvertFrom-Json } catch { $j = $null }
      if ($j) { [IO.File]::WriteAllText("$log.final", "$($j.result)") }
    }
    if ($rt -eq 'OpenCode') { [IO.File]::WriteAllText("$log.final", (OpenCodeFinal (Read-StageLog $log))) }
    $script:LastUsage = Usage $log $model
    if ($null -ne $run.ExitCode -and $run.ExitCode -ne 0 -and ($rt -ne 'Claude' -or -not $j -or $j.num_turns -le 1)) {
      Add-Content $log "`nAPI Error: $rt exited $($run.ExitCode)`n$(Read-StageLog "$log.err")"
    }
    # A stage is handed off by commits, never by a dirty Stage: line or final message.
    if (-not $script:LastInfrastructureError -and (GitOk status --porcelain)) {
      $script:LastFailureKind = 'incomplete handoff'
      $script:LastInfrastructureError = 'Stage left uncommitted work; saved for recovery.'
    }
    if (-not $script:LastInfrastructureError) {
      try {
        $handoff = Ticket (Join-Path $Repo $t.File)
        if ($handoff.HandoffError) { throw $handoff.HandoffError }
        Assert-ProxyReceipts $t.Id $t.Text $handoff.Text
        if ($label -eq 'implement' -and $handoff.Stage -eq 'to-review') { Assert-TestFirst $handoff $from }
        if ($handoff.Stage -in 'to-review', 'done', 'to-merge') {
          $ref = if ($handoff.Stage -eq 'done') { $Loop } else { $handoff.Branch }
          Assert-GateEvidence $handoff $ref
        }
      } catch {
        $script:LastFailureKind = 'incomplete handoff'
        $script:LastInfrastructureError = "Invalid committed handoff: $($_.Exception.Message)"
      }
    }
  } catch { $script:LastInfrastructureError = "Stage evidence unavailable: $($_.Exception.Message)" }
  return $run.Result
}

# Test-first, checked by a script rather than by the reviewer reading `diff --stat`: each
# commit the stage made is test-only or production-only. The tracker is metadata, allowed in either.
function Assert-TestFirst($t, $from) {
  $range = @($t.Branch, "^$Loop") + @(if ($from) { "^$from" })
  $mixed = foreach ($c in @(GitOk rev-list --no-merges @range)) {
    $files = @(GitOk -c core.quotepath=false diff-tree --no-commit-id --name-only -r $c | Where-Object { $_ -notlike "$Tracker/*" })
    $tests = @($files | Where-Object { $_ -match $TestFiles }); $prod = @($files | Where-Object { $_ -notmatch $TestFiles })
    if ($tests -and $prod) { '{0} mixes {1} with {2}' -f $c.Substring(0, 8), $tests[0], $prod[0] }
  }
  if ($mixed) { throw "test and production in one commit: $($mixed -join '; '). Split it; a test fixture kept beside production goes in the binding's ``Test files:``." }
}

# A runtime/logging failure parks only this ticket; its evidence survives reset.
function Park-Infrastructure($t, $stage, $model, $attempt, $started) {
  if (-not $script:LastInfrastructureError) { return $false }
  Reset-Tree $t
  $outcome = if ($script:LastFailureKind -eq 'incomplete handoff') { 'failed (incomplete handoff), blocked' } else { 'infrastructure, blocked' }
  LogStage $t $stage $model $attempt $outcome $started
  Note $t "Stage stopped ($script:LastFailureKind): $script:LastInfrastructureError See $script:LastLog.runtime.json and run-log/recovery.txt; inspect the saved work before retrying." 'blocked'
  return $true
}

# The session's last words, one line: when stage 2 stops to ask, this is the question.
function LogTail($log, $chars = 1200) {
  $source = if ((Test-Path "$log.final") -and (Get-Item "$log.final").Length) { "$log.final" } else { $log }
  $text = (Read-StageLog $source)
  if ($text.Length -gt $chars) { $text = '...' + $text.Substring($text.Length - $chars) }
  ($text -replace '\r?\n', ' / ').Trim()
}

# Why a stage stopped short. An API outage is ours, not the ticket's, so it must not
# spend an attempt. A session that ended on a question gains nothing from a retry
# that will only ask again: park it for a human now. Everything else is a failure.
function Verdict($log) {
  $text = (Read-StageLog $log).TrimEnd()
  if ($text -match '(?m)^API Error') { return 'api-error' }
  # Claude's outage lands in its JSON `result`, which RunStage copied to `.final`.
  if (Test-Path "$log.final") { $text = (Read-StageLog "$log.final").TrimEnd() }
  if ($text -match '^API Error') { return 'api-error' }
  if ($text -match '\?\W*$') { return 'asked' }
  'failed'
}

# What a stage consumed, priced at API list price: the one measure both runtimes can
# give. No subscription bills it; it is the number to hold against the plan's price.
# Claude prices its own sessions (`total_cost_usd`); Codex reports only tokens.
# Per 1M tokens: input, cached input, cache write, output. developers.openai.com/api/docs/pricing, read 2026-09-24.
# ponytail: short-context prices; Codex gives one total per turn, so a stage past the
# long-context threshold reads low. Split it if the log ever reports per request.
$CodexPrices = @{
  'gpt-6-astra' = 10.00, 1.00, 12.50, 50.00
  'gpt-6-sol'   = 2.00, 0.20, 2.50, 10.00
  'gpt-6.1-sol' = 2.00, 0.20, 2.50, 10.00
  'gpt-6-luna'  = 0.10, 0.01, 0.125, 0.50
  'gpt-5.6-sol' = 4.00, 0.40, 5.00, 20.00   # promo price, through at least 2026-11-21
  # Not on OpenAI's price page, backing model unknown; priced as gpt-5.6-luna (standard tier).
  'codex-auto-review' = 0.20, 0.02, 0.25, 1.20
}
# Not Measure-Object: a field an older CLI does not emit is an error there, a 0 here.
function Sum($objs, $name) { $s = 0.0; foreach ($o in $objs) { $s += [double]$o.$name }; $s }
# Codex keeps one rollout per thread under $CODEX_HOME/sessions, named by the thread id (codex-quota.ps1 reads the same name).
function CodexRollouts {
  $home_ = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
  Get-ChildItem (Join-Path $home_ 'sessions') -Recurse -Filter 'rollout-*.jsonl' -ErrorAction SilentlyContinue | ForEach-Object {
    $id = [regex]::Match($_.Name, '([0-9a-f]{8}-[0-9a-f-]{27})\.jsonl$').Groups[1].Value
    # A subagent's first line names its parent thread; a root thread's does not.
    if ($id) { try { $meta = Get-Content -LiteralPath $_.FullName -TotalCount 1 } catch { $meta = '' }
      [pscustomobject]@{ Thread = $id; File = $_.FullName; Parent = [regex]::Match("$meta", '"thread_spawn":\{"parent_thread_id":"([^"]+)"').Groups[1].Value } }
  }
}
# The last token_count that carries info is the thread's running total; info is null on rate-limit-only events.
function RolloutUsage($file) {
  $lines = (Read-StageLog $file) -split "`n"
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notlike '*"token_count"*') { continue }
    try { $e = $lines[$i] | ConvertFrom-Json } catch { continue }
    if ($e.type -eq 'event_msg' -and $e.payload.info) { return $e.payload.info.total_token_usage }
  }
}
function Usage($log, $model) {
  $text = (Read-StageLog $log)
  if ((RuntimeOf $model) -eq 'OpenCode') {
    # OpenCode prices each step itself; `input` excludes cache reads (measured 2026-10-27).
    # shortcut: subagent (task tool) sessions are not in this stream; read them from opencode.db if they matter.
    # shortcut: Out adds reasoning as if OpenCode reports it apart; unchecked against a paid bill, cost is unaffected.
    $s = @(foreach ($l in $text -split "`n") {
      if ($l -like '{"type":"step_finish"*') { try { ($l | ConvertFrom-Json).part } catch { } }
    })
    if (-not $s) { return $null }
    $t = @($s | ForEach-Object tokens); $c = @($t | ForEach-Object cache)
    $cached = Sum $c 'read'
    return [pscustomobject]@{ In = (Sum $t 'input') + $cached + (Sum $c 'write'); Cached = $cached
                              Out = (Sum $t 'output') + (Sum $t 'reasoning'); Cost = Sum $s 'cost' }
  }
  if ((RuntimeOf $model) -eq 'Claude') {
    try { $j = $text | ConvertFrom-Json } catch { return $null }
    $m = @($j.modelUsage.PSObject.Properties | ForEach-Object Value)   # every model, subagents included
    $cached = Sum $m 'cacheReadInputTokens'
    return [pscustomobject]@{ In = $cached + (Sum $m 'inputTokens') + (Sum $m 'cacheCreationInputTokens')
                              Cached = $cached; Out = Sum $m 'outputTokens'; Cost = $j.total_cost_usd }
  }
  $u = @(foreach ($l in $text -split "`n") {
    if ($l -like '*turn.completed*') { try { $e = $l | ConvertFrom-Json; if ($e.type -eq 'turn.completed') { $e.usage } } catch { } }
  })
  # A stage killed by time has no turn.completed: its own rollout is the record. Subagent rollouts
  # (any depth) bill to the stage either way; they add tokens, so pricing the sum is pricing each one.
  $tid = [regex]::Match($text, '"thread_id":"([^"]+)"').Groups[1].Value
  if ($tid) {
    $rollouts = @(CodexRollouts)
    if (-not $u) { $u = @($rollouts | Where-Object { $_.Thread -eq $tid } | ForEach-Object { RolloutUsage $_.File }) }
    $threads = @($tid)
    for ($i = 0; $i -lt $threads.Count; $i++) {
      foreach ($kid in @($rollouts | Where-Object { $_.Parent -eq $threads[$i] -and $threads -notcontains $_.Thread })) {
        $threads += $kid.Thread; $u += @(RolloutUsage $kid.File)
      }
    }
  }
  if (-not $u) { return $null }
  # OpenAI counts cached and cache-write tokens inside input_tokens; reasoning inside output_tokens.
  $in = Sum $u 'input_tokens'; $cached = Sum $u 'cached_input_tokens'; $write = Sum $u 'cache_write_input_tokens'; $out = Sum $u 'output_tokens'
  # The fast (priority) tier bills exactly twice the standard price (Bruno, 2026-10-04).
  $p = $CodexPrices[$model -replace '-fast$']; $tier = if ($model -match '-fast$') { 2 } else { 1 }
  $cost = if ($p) { $tier * (($in - $cached - $write) * $p[0] + $cached * $p[1] + $write * $p[2] + $out * $p[3]) / 1e6 }
  [pscustomobject]@{ In = $in; Cached = $cached; Out = $out; Cost = $cost }
}
# Invariant: a pt-BR machine writes `$1,23`, and the summary could not add it back up.
function Inv($f) { [string]::Format([Globalization.CultureInfo]::InvariantCulture, $f, [object[]]$args) }
function Tok($n) { if ($n -ge 1e6) { Inv '{0:0.0}M' ($n / 1e6) } else { Inv '{0:0}k' ($n / 1e3) } }
# The two run-log cells; `?` where the stage left no usage (timeout) or the model has no price.
function UsageCells($u) {
  if (-not $u) { return '?', '?' }
  $pct = if ($u.In) { [int](100 * $u.Cached / $u.In) } else { 0 }
  ('{0} in ({1}% cached), {2} out' -f (Tok $u.In), $pct, (Tok $u.Out)), $(if ($null -ne $u.Cost) { Inv '${0:0.000}' $u.Cost } else { '?' })
}
# Two outages in a row is the network, not luck: stop instead of looping on it.
function NetFail($tail) { if (++$script:NetFails -ge 2) { throw "API unreachable twice; stopping. Last: $tail" } }
# A usage limit is not an outage: the CLI says when it lifts. Measured 2026-09-30, Codex:
# "You've hit your usage limit. ... try again at 1:38 PM." (local time). Two in a row
# stopped the run and a human had to relaunch after the reset; wait for it instead.
function LimitReset($log) {
  # Only the tail: a session that read this file or SKILL.md has the phrase earlier in its log.
  $text = (Read-StageLog $log)
  if ($text.Length -gt 2000) { $text = $text.Substring($text.Length - 2000) }
  $m = [regex]::Match($text, 'usage limit.*?try again at (\d{1,2}:\d{2}\s?[AP]M)')
  if (-not $m.Success) { return $null }
  $at = [datetime]::ParseExact(($m.Groups[1].Value -replace '\s', ' ' -replace '(\d)([AP])', '$1 $2'), 'h:mm tt', [Globalization.CultureInfo]::InvariantCulture)
  # A reset a minute ago is today, not tomorrow; one at 11:59 PM read at 00:01 was yesterday.
  if ($at -lt (Get-Date).AddHours(-1)) { $at = $at.AddDays(1) }
  elseif ($at -gt (Get-Date).AddHours(23)) { $at = $at.AddDays(-1) }
  $at.AddMinutes(2)
}
# A refused request is not an outage: a retry sends the same request and gets the same
# answer. Measured 2026-10-01: Codex CLI 0.156.1 sent `gpt-6.1-sol` and got 400 "not
# supported when using Codex with a ChatGPT account"; read as an outage, it took two
# stages to stop, and `codex update` was the fix.
function Refused($log) {
  $text = (Read-StageLog $log)
  if ($text.Length -gt 2000) { $text = $text.Substring($text.Length - 2000) }
  $m = [regex]::Match($text, 'invalid_request_error\\?"\s*,\s*\\?"message\\?"\s*:\s*\\?"(.+?)\\?"')
  if ($m.Success) { return $m.Groups[1].Value }
  # OpenCode's unknown model or variant (measured 2026-10-27): a typo, never an outage.
  $m = [regex]::Match($text, '"provider\.no-route","message":"(.+?)"')
  if ($m.Success) { $m.Groups[1].Value }
}
# ponytail: only the "at h:mm AM" shape waits; a dated reset (weekly limit) still stops the run.
function ApiDown($tail) {
  $why = Refused $script:LastLog
  if ($why) { throw "The API refused the request, which is not an outage, so no retry: $why" }
  $at = LimitReset $script:LastLog
  if (-not $at) { NetFail $tail; return }
  Say "usage limit; waiting until $($at.ToString('HH:mm'))"
  Start-Sleep -Seconds ([int][math]::Max(0, ($at - (Get-Date)).TotalSeconds))
  $script:NetFails = 0
}

# A pause asked from outside: a `STOP` file in the run-log folder ends the run between
# stages, through the normal finally (tree reset, PR published). Measured 2026-10-01:
# the only pause was killing the driver mid-stage, twice, with no finally.
function StopAsked {
  if ($script:LogWriteFailed) { $script:Stopped = $true; return $true }
  $f = Join-Path $RunDir 'STOP'
  if (-not (Test-Path $f)) { return $false }
  Remove-Item $f; Say 'STOP file found; stopping between stages.'; $script:Stopped = $true; $true
}

# A stage may check the ticket's branch out in its own worktree (`.artifacts-build/<id>`).
# Left there, it holds the branch: `branch -D` fails and the next attempt reads the
# stale `implementing`. Measured 2026-10-16: CLEAN-033 retry ended the run that way.
function Remove-TicketWorktrees($t) {
  $path = $null
  foreach ($line in @(GitOk worktree list --porcelain)) {
    if ($line -like 'worktree *') { $path = $line.Substring(9) }
    elseif ($line -eq "branch refs/heads/$($t.Branch)" -and $path -and
            [IO.Path]::GetFullPath($path).TrimEnd('\', '/') -ne $Repo.TrimEnd('\', '/')) {
      if (GitOk -C $path status --porcelain) {
        $stamp = [guid]::NewGuid().ToString('N')
        GitOk -C $path stash push --include-untracked -m "sweatshop recovery $stamp" | Out-Null
        $head = GitOk -C $path rev-parse 'stash@{0}'
        GitOk update-ref "refs/sweatshop-recovery/$stamp" $head
        $record = "refs/sweatshop-recovery/$stamp $head; ticket $($t.Id) worktree $path; log $script:LastLog"
        Add-Content -Encoding UTF8 (Join-Path $RunDir 'recovery.txt') $record
        Say "Saved recovery: $record"
      }
      GitOk worktree remove --force $path | Out-Null
      Say "$($t.Id): removed worktree $path"
    }
  }
}

# Back to a clean loop base (the session); drop the ticket's branch if asked.
function Reset-Tree($t, [switch]$DropBranch) {
  if ($t) { Remove-TicketWorktrees $t }
  # Save before checkout -f/clean, including untracked files and committed attempts.
  if ((GitOk status --porcelain) -or $DropBranch) {
    $stamp = [guid]::NewGuid().ToString('N')
    $ref = "refs/sweatshop-recovery/$stamp"
    $head = GitOk rev-parse HEAD
    if (GitOk status --porcelain) {
      GitOk stash push --include-untracked -m "sweatshop recovery $stamp" | Out-Null
      $head = GitOk rev-parse 'stash@{0}'
    } elseif ($t -and (git branch --list $t.Branch)) { $head = GitOk rev-parse $t.Branch }
    GitOk update-ref $ref $head
    $record = "$ref $head; ticket $(if ($t) { $t.Id }); log $script:LastLog"
    Add-Content -Encoding UTF8 (Join-Path $RunDir 'recovery.txt') $record
    Say "Saved recovery: $record"
  }
  # Checked, not bare: a failed checkout leaves HEAD on the ticket branch, and the rest
  # of the run then commits notes there and reads every stage off it. Measured
  # 2026-09-15: that turned one bad $Loop into 70 minutes of wrong work.
  GitOk checkout -q -f $Loop | Out-Null
  git reset -q --hard; git clean -qfd
  if ($DropBranch -and (git branch --list $t.Branch)) { git branch -q -D $t.Branch }
}

# Append to `## Comments` on the loop base and commit (the driver's only edits).
# $details (a proxy's full answer) goes quoted under the line.
function Note($t, $line, $stage, $details) {
  $text = Get-Content $t.File -Raw -Encoding UTF8
  if ($text -notmatch '(?m)^## Comments') { $text = $text.TrimEnd() + "`n`n## Comments`n" }
  $text = $text.TrimEnd() + "`n`n- $(Get-Date -Format yyyy-MM-dd) $line`n"
  if ($details) { $text += (@($details -split '\r?\n' | ForEach-Object { "  > $_" }) -join "`n") + "`n" }
  if ($stage) { $text = $text -replace '(?m)^(\*{0,2}Stage\*{0,2}:\*{0,2})\s*.+$', "`$1 $stage" }
  [IO.File]::WriteAllText((Join-Path $Repo $t.File), $text, [Text.UTF8Encoding]::new($false))
  # -F, not -m: a log tail with quotes or `--flags` inside splits into git options under PS 5.1.
  # $PID: runs on other repos share %TEMP%; one fixed name commits their message here.
  $msg = Join-Path $env:TEMP "sweatshop-commit-$PID.txt"
  $subject, $body = $line -split ' Log tail: ', 2
  [IO.File]::WriteAllText($msg, "chore: $subject ($($t.Id))$(if ($body) { "`n`nLog tail: $body" })", [Text.UTF8Encoding]::new($false))
  GitOk add $t.File; GitOk commit -q -F $msg | Out-Null
  GitOk push -q
}

# --- the proxy ------------------------------------------------------------------------
# Live checks before the first stage: the proxy answers, and each runtime of the lineup can
# reach it from inside its own session, with a stage's own flags. A runtime that cannot runs
# its stages with SWEATSHOP_PROXY=driver: proxy.ps1 fails there at once, the stage stops with
# its question, and Answer-Asked puts it to the proxy from here, outside any sandbox.
function Ping-Proxy {
  $p = Invoke-Proxy $Repo $null $null -Ping -minutes 10
  if ($p.Decision -notmatch '^pong\W*$') { throw "Proxy ping: $($p.Who) answered '$($p.Decision)', not pong. Receipt $($p.Receipt)" }
  Say "proxy: $($p.Who) answered the ping"
  $script:ProxyVia = @{}
  foreach ($pair in @(@($Model2, $Effort2), @($Model3, $Effort3), @($ModelHard, $EffortHard))) {
    $model = $pair[0]; if (-not $model) { continue }
    $rt = RuntimeOf $model; if ($script:ProxyVia.Contains($rt)) { continue }
    $log = Join-Path $RunDir ('ping-{0}-{1}.txt' -f $rt, (Get-Date -Format yyyyMMdd-HHmmss))
    $since = Get-Date
    $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File $ProxyScript -Repo $Repo -Ping"
    $prompt = "Connectivity check from the sweatshop driver, not a ticket: read nothing and change nothing. Run exactly this one command and reply with its output: $cmd"
    # shortcut: the command rides unquoted in the prompt; a path with spaces needs quoting here.
    $run = Invoke-StageProcess $Cli[$rt] (StageArgs $rt $model 'low' $prompt 'proxy ping' "$log.final") $Repo $log $rt 600
    $why = Refused $log
    if ($run.InfrastructureError -or $why) { throw "$rt ($model) failed its ping session: $($run.InfrastructureError)$why. Log $log" }
    if (GitOk status --porcelain) { Reset-Tree $null }
    # Only a receipt counts, not the run files a call that hung leaves beside it.
    $reached = @(Get-ChildItem $ProxyDir -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '-ping-[0-9a-f]{6}\.json$' -and $_.LastWriteTime -gt $since })
    $script:ProxyVia[$rt] = if ($reached) { 'stage' } else { 'driver' }
    Say "proxy from $rt sessions: $(if ($reached) { 'reached directly' } else { "unreachable; the driver asks for them (log $log)" })"
  }
}

# An asking attempt's branch, renamed out of the ticket's way. Under its own name it would keep
# its stale `blocked` (an unmerged branch's Stage wins over the session's), so an answer on the
# session would never run; a reopened ticket's branch, holding the last pass, included.
function Keep-Asked($t) {
  if (-not (git branch --list $t.Branch)) { return '' }
  $kept = "recovery/asked/$(Get-Date -Format yyyyMMdd-HHmmss)/$($t.Id)"
  GitOk branch -q -m $t.Branch $kept | Out-Null
  " (its commits are on branch ``$kept``)"
}

# A stage that stopped to ask, with no proxy escalation of its own, gets the proxy's answer
# here; a Decision sends it back to stage 2. Twice per ticket per run at most.
function Answer-Asked($t, $before, $question) {
  if (@(New-ProxyLines $before $t.Text | Where-Object { $_.Groups[1].Value -eq 'escalated' }).Count) { return }
  if (-not $script:Asked) { $script:Asked = @{} }
  if (++$script:Asked[$t.Id] -gt 2) { Say "$($t.Id): asked a third time this run; left for a human"; return }
  $q = "Stage 2 of $($t.Id) stopped to ask; it could not reach you itself. Its last message:`n`n$question`n`nYour answer is recorded under the ticket's ## Comments and stage 2 runs again."
  try { $p = Invoke-Proxy $Repo $t.Id $q }
  catch { Say "$($t.Id): the driver could not reach the proxy: $($_.Exception.Message)"; return }
  if ($p.Kind -eq 'decided') { Note $t $p.Line 'to-implement' $p.Answer } else { Note $t $p.Line $null $p.Answer }
  Say "$($t.Id): $($p.Line)"
}

# One row per stage, not per ticket: the model and the time it burned are the two
# axes worth correlating later, and a per-ticket row cannot hold either. Usage is the
# stage RunStage just ran. $model carries its effort (`sonnet-5 xhigh`): the same model
# at another effort is another row in scoreboard.ps1.
function LogStage($t, $stage, $model, $attempt, $outcome, $started) {
  $mins = [int]((Get-Date) - $started).TotalMinutes
  $tokens, $cost = UsageCells $script:LastUsage
  $shutdown = if ($null -ne $script:LastShutdownSeconds) { Inv '{0:0.000}' $script:LastShutdownSeconds } else { '?' }
  $row = '| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7}m | {8} | {9} | {10} |' -f `
    (Get-Date -Format 'yyyy-MM-dd HH:mm'), $t.Id, $stage, $model, $attempt, $outcome, $Loop, $mins, $tokens, $cost, $shutdown
  # The sidecar is durable even when a reader has locked the cumulative ledger.
  [IO.File]::WriteAllText("$script:LastLog.row.txt", $row)
  try { Add-Content -Encoding UTF8 $RunLog $row }
  catch { $script:LogWriteFailed = $true; Say "Run log unavailable; row saved at $script:LastLog.row.txt. Stopping after this stage: $_" }
  Say "$($t.Id) $stage ($model): $outcome, $cost"
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
  if ($t.Stage -in 'blocked', 'to-merge', 'invalid-handoff') {
    $c = if ($t.HandoffError) { $t.HandoffError } else { ($t.LastComment -replace '^- ', '').Trim() }
    if ($c) { Write-Host ('{0}> {1}' -f $pad, $(if ($c.Length -gt 110) { $c.Substring(0, 110) + '...' } else { $c })) }
  }
  $open | Where-Object { $_.BlockedBy -contains $t.Id } | ForEach-Object { Walk $_ ($depth + 1) $open $seen }
}
function ShowTree($label) {
  $all = AllTickets
  $open = @($all | Where-Object { $_.Stage -ne 'done' -and (InLane $_) })
  if (-not $open) { Write-Host "`n${label}: nothing left$(if ($Lane) { " in lane $Lane" })."; return }
  $doneIds = $all | Where-Object Stage -eq 'done' | ForEach-Object Id
  $seen = @{}
  Write-Host ("`n{0} -- {1} open, indented under what blocks them:" -f $label, $open.Count)
  $open | Where-Object { -not ($_.BlockedBy | Where-Object { $_ -notin $doneIds }) } | ForEach-Object { Walk $_ 0 $open $seen }
  # A cycle, or a blocker that is itself unreachable, would otherwise print nothing.
  $open | Where-Object { -not $seen.ContainsKey($_.Id) } | ForEach-Object { Walk $_ 0 $open $seen }
}

# --- the session PR ------------------------------------------------------------------
# The lines that want a human first: no `Approve`, or `Review: human`. Read from the
# top, stop when it turns boring.
function PrBody($tickets) {
  $hot = { param($t) [int]($t.Verdict -notmatch '^Approve' -or $t.Review -eq 'human') }
  $lines = foreach ($t in ($tickets | Sort-Object { -(& $hot $_) }, Id)) {
    '- {0} `Review: {1}` -- {2}' -f $t.Id, $t.Review, $(if ($t.Verdict) { $t.Verdict } else { 'no verdict' })
  }
  $disclosures = foreach ($t in $tickets) {
    $link = if ($t.File) { "[$($t.Id)]($($t.File))" } else { $t.Id }
    $acceptance = Field $t.Text 'Acceptance'
    "### $link - product acceptance: $(if ($acceptance) { $acceptance } else { 'unknown (legacy record; not established by Approve)' })"
    $notes = @($t.Text -split '\r?\n' | Where-Object { $_ -match 'Proxy decided|D[eé]bito humano|(?i)^Disclosure:' })
    if ($notes) {
      $notes | ForEach-Object {
        if ($_ -match '(?i)^Disclosure:') { "  - $_" }
        else { "  - $_ (evidence: $link; integration/release impact: unknown unless stated)" }
      }
    } else { '  - No structured disclosures recorded; legacy omissions remain unknown.' }
  }
  "Session ``$Loop``. Ticket implementation approval and product acceptance are separate.`n`n" + ($lines -join "`n") + "`n`n## Decisions, pending acceptance and deferred defects`n`n" + ($disclosures -join "`n")
}
function ChangedSessionTickets {
  foreach ($f in @(GitOk diff --name-only --diff-filter=ACMRT "$Base...$Loop" -- "$Tracker/*/issues/*")) {
    $t = Ticket (Join-Path $Repo $f); if ($t.Id) { $t }
  }
}
function CompletedTickets {
  foreach ($t in @(ChangedSessionTickets)) {
    if ($t.Stage -ne 'done') { continue }
    $ErrorActionPreference = 'Continue'
    $old = (& git show "${Base}:$($t.File)" 2>$null) -join "`n"
    $oldStage = Field $old 'Stage'
    $oldDone = $oldStage -eq 'done' -or (-not $oldStage -and (Field $old 'Status') -in 'complete', 'resolved', 'wontfix')
    $recompleted = $false
    if ($oldDone) {
      foreach ($commit in @(GitOk log --format='%H' "$Base..$Loop" -- $t.File)) {
        $prior = (GitOk show "${commit}:$($t.File)") -join "`n"
        if ((Field $prior 'Stage') -in 'to-implement', 'implementing', 'to-review', 'reviewing') { $recompleted = $true; break }
      }
    }
    if (-not $oldDone -or $recompleted) { $t }
  }
}
function SessionBody {
  $completed = @(CompletedTickets)
  $body = PrBody $completed
  $context = @(ChangedSessionTickets | Where-Object { $_.Id -notin $completed.Id -and $_.Text -match 'Proxy decided|D[eé]bito humano|(?i)Disclosure:|Acceptance:' })
  if ($context) { $body += "`n`n## Updated ticket context (excluded from completed count)`n`n" + (PrBody $context) }
  $body
}
# The repo leads the title: with several projects' session PRs in one inbox, a bare
# `sweatshop: sweatshop/2026-10-29-1430` named no project.
function SessionTitle($origin, $branch) { (($origin -replace '[\\/]+$' -replace '\.git$') -split '[\\/:]')[-1] + ': ' + ($branch -replace '/', ' ') }
# Opened when the run stops, never earlier: nobody reviews half a session. Body
# regenerated every time, so a second run on the same session just grows the list.
function Publish-Session {
  if ($Loop -eq $Base -or -not [int](git rev-list --count "$Base..$Loop")) { Say "session ${Loop}: nothing merged, no PR"; return }
  GitOk push -q
  $done = @(CompletedTickets)
  $body = Join-Path $env:TEMP "sweatshop-pr-$PID.md"
  [IO.File]::WriteAllText($body, (SessionBody), [Text.UTF8Encoding]::new($false))
  # gh is a native command: a failure is only an exit code, so check it or the run
  # ends saying "session PR:" with nothing after the colon.
  $url = gh pr list --head $Loop --base $Base --state open --json url --jq '.[0].url'
  if ($LASTEXITCODE) { throw "gh pr list exited $LASTEXITCODE" }
  $title = SessionTitle (GitOk remote get-url origin) $Loop
  if ($url) { gh pr edit $url --title $title --body-file $body | Out-Null }
  else { $url = gh pr create --base $Base --head $Loop --title $title --body-file $body }
  if ($LASTEXITCODE) { throw "gh exited $LASTEXITCODE; body kept at $body" }
  Say "session PR ($($done.Count) tickets): $url"
}

function Median($v) { $s = @($v | Sort-Object); $s[[int][math]::Floor($s.Count / 2)] }

# Not the analysis -- the trigger for it. Correlating ticket shape against model and
# duration needs something that reads prose; this just says when it is worth asking.
function ShowSummary {
  if (-not (Test-Path $RunLog)) { return }
  try { $lines = (Read-StageLog $RunLog) -split "`n" }
  catch { Say "Summary unavailable: run log locked; stage outcomes remain in $RunDir/*.row.txt"; return }
  $rows = @(foreach ($l in $lines) {
    $c = @($l -split '\|' | ForEach-Object { $_.Trim() })
    if ($c.Count -in 10, 12, 13 -and $c[1] -match '^\d{4}-\d\d-\d\d') { , $c }
  })
  if (-not $rows) { return }
  $priced = @($rows | Where-Object { $_.Count -ge 12 -and $_[10] -match '^\$' } | ForEach-Object { [double]($_[10] -replace '\$', '') })
  $med = { param($stage)
    $v = @($rows | Where-Object { $_[3] -eq $stage } | ForEach-Object { [int]($_[8] -replace '\D', '') })
    if ($v.Count) { '{0}m' -f (Median $v) } else { 'n/a' } }
  $n = { param($pat) @($rows | Where-Object { $_[6] -match $pat }).Count }
  Write-Host ("`n{0} stages | {1} merged | {2} reopened | {3} retries | implement {4} ({5}) | review {6} ({7}) | {8} over {9} priced stages" -f `
    $rows.Count, (& $n '^merged$'), (& $n '^reopened$'), (& $n '^failed'), (& $med 'implement'), $Model2, (& $med 'review'), $Model3,
    (Inv '${0:0.000}' ([double]($priced | Measure-Object -Sum).Sum)), $priced.Count)
}

if ($SelfCheck) {
  # Median is the only arithmetic here and it was wrong once: [int](3/2) is 2 in PS.
  if ((Median @(12, 45, 20)) -ne 20) { throw 'Median: odd count' }
  if ((Median @(5, 8)) -ne 8) { throw 'Median: even count' }
  if ((Median @(7)) -ne 7) { throw 'Median: single' }
  # Field reading only `Stage:` is why a whole tracker once read as stageless.
  foreach ($shape in 'Stage: to-review', '**Stage:** to-review', '**Stage**: to-review') {
    if ((Field "# T-1: x`n$shape`n" 'Stage') -ne 'to-review') { throw "Field: $shape" }
  }
  # A bullet receipt with a note parked valid handoffs; a path with parentheses must survive.
  foreach ($case in @(@('Gate evidence: C:\t\r.json', 'C:\t\r.json'), @('- Gate evidence: C:\t\r.json (gate 119/0)', 'C:\t\r.json'),
                      @('* **Gate evidence:** C:\t\r.json', 'C:\t\r.json'), @('Gate evidence: C:\a (x86)\r.json', 'C:\a (x86)\r.json'),
                      @('- Gate evidence: C:\a (x86)\r.json (gate 119/0 (full))', 'C:\a (x86)\r.json'), @('Gate evidence: C:\t\receipt (1)', 'C:\t\receipt (1)'))) {
    if ((GateEvidenceField "# T-1: x`nStage: to-review`n$($case[0])`n") -ne $case[1]) { throw "GateEvidenceField: $($case[0])" }
  }
  foreach ($case in @(@('https://github.com/Laginho/Agent-Skills.git', 'sweatshop/2026-10-29-1430', 'Agent-Skills: sweatshop 2026-10-29-1430'),
                      @('git@github.com:Laginho/P-Chess.git', 'sweatshop/ui/2026-10-29-1430', 'P-Chess: sweatshop ui 2026-10-29-1430'),
                      @('C:\t\target-origin.git\','sweatshop/x', 'target-origin: sweatshop x'))) {
    if ((SessionTitle $case[0] $case[1]) -ne $case[2]) { throw "SessionTitle: $($case[0])" }
  }
  # Verdict decides whether an attempt is spent; the shapes are the two real logs of 2026-09-14.
  $tmp = Join-Path $env:TEMP "sweatshop-verdict-$PID.txt"
  foreach ($case in @(@("API Error: Unable to connect to API (ENOTFOUND)`n", 'api-error'),
                      @("Three options.`n`nWhich one do you want?`n", 'asked'),
                      @("Done for stage 2, gate green.`n", 'failed'))) {
    [IO.File]::WriteAllText($tmp, $case[0]); $got = Verdict $tmp
    if ($got -ne $case[1]) { throw "Verdict: expected $($case[1]), got $got" }
  }
  # Claude's outage is inside its JSON; RunStage copies `result` to `.final`.
  [IO.File]::WriteAllText($tmp, '{"result":"API Error: 529"}'); [IO.File]::WriteAllText("$tmp.final", 'API Error: 529')
  if ((Verdict $tmp) -ne 'api-error') { throw 'Verdict: Claude outage in .final' }
  Remove-Item "$tmp.final"
  # LimitReset turns a waitable outage into a sleep; the shape is Codex's of 2026-09-30.
  [IO.File]::WriteAllText($tmp, "{`"type`":`"error`",`"message`":`"You've hit your usage limit. Upgrade to Pro, visit x or try again at 1:38 PM.`"}`n")
  $at = LimitReset $tmp
  if (-not $at -or $at.ToString('HH:mm') -ne '13:40') { throw "LimitReset: got $at" }
  [IO.File]::WriteAllText($tmp, "API Error: Unable to connect to API (ENOTFOUND)`n")
  if ($null -ne (LimitReset $tmp)) { throw 'LimitReset: an outage is not a usage limit' }
  $ago = (Get-Date).AddMinutes(-1).ToString('h:mm tt', [Globalization.CultureInfo]::InvariantCulture)
  [IO.File]::WriteAllText($tmp, "usage limit, try again at $ago.`n")
  if (((LimitReset $tmp) - (Get-Date)).TotalMinutes -gt 2) { throw 'LimitReset: a reset just past is not tomorrow' }
  [IO.File]::WriteAllText($tmp, "usage limit, try again at 1:38 PM.`n" + ('x' * 3000) + "`nAPI Error: 529`n")
  if ($null -ne (LimitReset $tmp)) { throw 'LimitReset: a quote early in the log is not this outage' }
  # Refused stops on a 400, never on an outage or a capacity error. Shape: Codex's of 2026-10-01.
  [IO.File]::WriteAllText($tmp, "{`"type`":`"error`",`"message`":`"{\`"type\`":\`"error\`",\`"status\`":400,\`"error\`":{\`"type\`":\`"invalid_request_error\`",\`"message\`":\`"The 'gpt-6.1-sol' model is not supported.\`"}}`"}`n")
  if ((Refused $tmp) -ne "The 'gpt-6.1-sol' model is not supported.") { throw "Refused: got $(Refused $tmp)" }
  [IO.File]::WriteAllText($tmp, "{`"type`":`"error`",`"message`":`"Selected model is at capacity. Please try a different model.`"}`n")
  if ($null -ne (Refused $tmp)) { throw 'Refused: a capacity error is an outage' }
  [IO.File]::WriteAllText($tmp, "{`"type`":`"error`",`"timestamp`":1,`"sessionID`":`"ses_x`",`"error`":{`"type`":`"provider.no-route`",`"message`":`"Model unavailable: nope/nothing`"}}`n`nAPI Error: OpenCode exited 1`n")
  if ((Refused $tmp) -ne 'Model unavailable: nope/nothing') { throw "Refused: OpenCode no-route got $(Refused $tmp)" }
  # A mixed lineup routes each stage by its model; a wrong route runs the wrong CLI.
  foreach ($case in @(@('gpt-6-luna', 'Codex'), @('gpt-6-sol', 'Codex'), @('opus', 'Claude'), @('claude-opus-5-5', 'Claude'), @('sonnet', 'Claude'), @('opencode/big-pickle', 'OpenCode'), @('openai/gpt-6-sol', 'OpenCode'))) {
    if ((RuntimeOf $case[0]) -ne $case[1]) { throw "RuntimeOf: $($case[0]) should run on $($case[1])" }
  }
  # The binding's spelling, the run log's label and the CLI's id must stay one model.
  $l = 'stage 1 x, stage 2 Opus 5.5 max, stage 3 gpt-6-luna'
  if ("$(StageModel $l 2) / $(StageModel $l 3)" -ne 'opus-5.5 max / gpt-6-luna high') { throw "StageModel: $(StageModel $l 2) / $(StageModel $l 3)" }
  if ("$(StageModel 'stage 2 sonnet-5 low' 2)" -ne 'sonnet-5 low') { throw "StageModel: $(StageModel 'stage 2 sonnet-5 low' 2)" }
  if ("$(StageModel 'stage 2 claude-opus-5-5 high, stage 3 claude-sonnet-5' 2) / $(StageModel 'stage 2 claude-opus-5-5 high, stage 3 claude-sonnet-5' 3)" -ne 'opus-5.5 high / sonnet-5 high') { throw 'StageModel: a claude- id must log as its short name' }
  if ("$(StageModel 'stage 2 gpt-6.1-sol high fast, hard gpt-6.1-sol fast' 2) / $(StageModel 'stage 2 gpt-6.1-sol high fast, hard gpt-6.1-sol fast' 'hard')" -ne 'gpt-6.1-sol-fast high / gpt-6.1-sol-fast high') { throw 'StageModel: fast' }
  if ($null -ne (StageModel 'stage 2 opus-5.5' 3)) { throw 'StageModel: an absent stage must be $null' }
  $l = 'stage 2 opencode/big-pickle, stage 3 OpenRouter/Qwen-4#high max'
  if ("$(StageModel $l 2) / $(StageModel $l 3)" -ne 'opencode/big-pickle high / OpenRouter/Qwen-4#high max') { throw "StageModel: OpenCode $(StageModel $l 2) / $(StageModel $l 3)" }
  # A hard ticket, by its header or by two reopens, gets the `hard` implementer; nothing else does.
  if ("$(StageModel 'stage 2 gpt-6.1-sol high, hard sonnet-5.5 xhigh, stage 3 gpt-6.1-sol max' 'hard')" -ne 'sonnet-5.5 xhigh') { throw 'StageModel: hard' }
  $Model2, $Effort2, $ModelHard, $EffortHard = 'easy', 'high', 'strong', 'xhigh'
  $txt = "# T-1: x`nStage: to-implement`n**Difficulty:** hard`n"
  $tix = [pscustomobject]@{ Difficulty = Field $txt 'Difficulty'; Reopens = 0 }, [pscustomobject]@{ Difficulty = ''; Reopens = Reopens "Verdict: Reopen (1)`nx`nVerdict: Reopen - 2`nVerdict: Approve`n" },
         [pscustomobject]@{ Difficulty = 'normal'; Reopens = 1 }
  $got = ($tix | ForEach-Object { (Implementer $_)[0] }) -join ' '
  if ($got -ne 'strong strong easy') { throw "Implementer: $got" }
  $ModelHard = $null
  if ((Implementer $tix[0])[0] -ne 'easy') { throw 'Implementer: no hard model must fall back to stage 2' }
  foreach ($case in @(@('opus-5.5', 'claude-opus-5-5'), @('haiku-4.5', 'claude-haiku-4-5'), @('gpt-6-luna', 'gpt-6-luna'), @('claude-sonnet-5', 'claude-sonnet-5'))) {
    if ((CliModel $case[0]) -ne $case[1]) { throw "CliModel: $($case[0]) gave $(CliModel $case[0])" }
  }
  # Usage is the report's cost column. Shapes cut from the real logs of 2026-09-24.
  [IO.File]::WriteAllText($tmp, '{"total_cost_usd":0.5,"modelUsage":{"a":{"inputTokens":10,"outputTokens":100,"cacheReadInputTokens":900,"cacheCreationInputTokens":90},"b":{"inputTokens":0,"outputTokens":50,"cacheReadInputTokens":0,"cacheCreationInputTokens":0}}}')
  $u = Usage $tmp 'x'
  if ("$($u.In) $($u.Cached) $($u.Out) $($u.Cost)" -ne '1000 900 150 0.5') { throw "Usage: Claude $u" }
  if ((UsageCells $u)[0] -ne '1k in (90% cached), 0k out') { throw "UsageCells: $((UsageCells $u)[0])" }
  [IO.File]::WriteAllText($tmp, "{`"type`":`"item.completed`",`"text`":`"turn.completed`"}`n{`"type`":`"turn.completed`",`"usage`":{`"input_tokens`":2000000,`"cached_input_tokens`":1000000,`"output_tokens`":100000,`"reasoning_output_tokens`":60000}}`n")
  # luna: 1M uncached * 0.10 + 1M cached * 0.01 + 0.1M out * 0.50 = 0.160
  if ((UsageCells (Usage $tmp 'gpt-6-luna'))[1] -ne '$0.160') { throw "Usage: Codex $((UsageCells (Usage $tmp 'gpt-6-luna'))[1])" }
  if ((UsageCells (Usage $tmp 'gpt-unpriced'))[1] -ne '?') { throw 'Usage: unpriced model must read ?' }
  if ((UsageCells (Usage $tmp 'gpt-6-luna-fast'))[1] -ne '$0.320') { throw 'Usage: fast must bill twice the base' }
  # OpenCode prices its own steps; the last text event is the final message. Shape: the probe of 2026-10-27.
  $step = { param($in, $out, $read, $cost) "{`"type`":`"step_finish`",`"sessionID`":`"s`",`"part`":{`"type`":`"step-finish`",`"cost`":$cost,`"tokens`":{`"input`":$in,`"output`":$out,`"reasoning`":10,`"cache`":{`"read`":$read,`"write`":0}}}}" }
  [IO.File]::WriteAllText($tmp, (@((& $step 7669 74 1017 0.25), '{"type":"text","sessionID":"s","part":{"type":"text","text":"first"}}', (& $step 153 37 8688 0.5),
                                   '{"type":"text","sessionID":"s","part":{"type":"text","text":"Which one?"}}') -join "`n"))
  $u = Usage $tmp 'opencode/big-pickle'
  if ("$($u.In) $($u.Cached) $($u.Out) $($u.Cost)" -ne '17527 9705 131 0.75') { throw "Usage: OpenCode $u" }
  if ((OpenCodeFinal (Read-StageLog $tmp)) -ne 'Which one?') { throw 'OpenCodeFinal: not the last text' }
  [IO.File]::WriteAllText($tmp, '{"type":"error","error":{"type":"provider.no-route","message":"x"}}')
  if ($null -ne (Usage $tmp 'opencode/big-pickle')) { throw 'Usage: OpenCode without steps must read ?' }
  Remove-Item $tmp
  # Killed stage (no turn.completed) priced from its rollout; subagent rollouts at any depth add to it.
  $codexHome = Join-Path $env:TEMP ('sweatshop-codexhome-' + [guid]::NewGuid().ToString('N'))
  $savedHome = $env:CODEX_HOME; $env:CODEX_HOME = $codexHome
  try {
    $day = Join-Path $codexHome 'sessions\2026\10\20'; New-Item -ItemType Directory -Force $day | Out-Null
    $tok = { param($in, $out) @{ type = 'event_msg'; payload = @{ type = 'token_count'; info = @{ total_token_usage = @{ input_tokens = $in; cached_input_tokens = 0; cache_write_input_tokens = 0; output_tokens = $out } } } } | ConvertTo-Json -Compress -Depth 9 }
    $rollout = { param($id, $parent, [string[]]$events)
      $src = if ($parent) { @{ subagent = @{ thread_spawn = @{ parent_thread_id = $parent } } } } else { 'cli' }
      $meta = @{ type = 'session_meta'; payload = @{ id = $id; source = $src } } | ConvertTo-Json -Compress -Depth 9
      [IO.File]::WriteAllLines((Join-Path $day "rollout-2026-10-20T10-00-00-$id.jsonl"), [string[]](@($meta) + $events)) }
    $root, $kid, $grand, $done, $doneKid = 'aaaaaaaa-0000-7000-8000-000000000001', 'aaaaaaaa-0000-7000-8000-000000000002', 'aaaaaaaa-0000-7000-8000-000000000003', 'aaaaaaaa-0000-7000-8000-000000000004', 'aaaaaaaa-0000-7000-8000-000000000005'
    # Root: an earlier reading, a rate-limit-only event (info null), then the last total = 1M uncached input = $0.100 on luna.
    & $rollout $root $null @((& $tok 500000 0), '{"type":"event_msg","payload":{"type":"token_count","info":null}}', (& $tok 1000000 0))
    & $rollout $kid $root @((& $tok 1000000 0))           # + $0.100
    & $rollout $grand $kid @((& $tok 0 1000000))           # + $0.500 (output)
    & $rollout $doneKid $done @((& $tok 1000000 0))        # completed stage's subagent: + $0.100
    $killed = Join-Path $codexHome 'killed.txt'
    [IO.File]::WriteAllText($killed, "{`"type`":`"thread.started`",`"thread_id`":`"$root`"}`n{`"type`":`"item.started`"}`n")
    if ((UsageCells (Usage $killed 'gpt-6-luna'))[1] -ne '$0.700') { throw "Usage: killed stage with subagents $((UsageCells (Usage $killed 'gpt-6-luna'))[1])" }
    if ((UsageCells (Usage $killed 'gpt-6-luna'))[0] -notmatch '^2\.0M in') { throw 'Usage: killed stage tokens' }
    $done_ = Join-Path $codexHome 'done.txt'
    [IO.File]::WriteAllText($done_, "{`"type`":`"thread.started`",`"thread_id`":`"$done`"}`n{`"type`":`"turn.completed`",`"usage`":{`"input_tokens`":2000000,`"cached_input_tokens`":1000000,`"output_tokens`":100000}}`n")
    # Completed stage: turn.completed $0.160 plus its subagent $0.100.
    if ((UsageCells (Usage $done_ 'gpt-6-luna'))[1] -ne '$0.260') { throw "Usage: completed stage with subagent $((UsageCells (Usage $done_ 'gpt-6-luna'))[1])" }
    $none = Join-Path $codexHome 'none.txt'
    [IO.File]::WriteAllText($none, "{`"type`":`"thread.started`",`"thread_id`":`"ffffffff-0000-7000-8000-000000000009`"}`n")
    if ((UsageCells (Usage $none 'gpt-6-luna'))[1] -ne '?') { throw 'Usage: killed stage without rollout must read ?' }
    $env:CODEX_HOME = Join-Path $codexHome 'missing'
    if ((UsageCells (Usage $killed 'gpt-6-luna'))[1] -ne '?') { throw 'Usage: no CODEX_HOME sessions must read ?' }
  } finally { $env:CODEX_HOME = $savedHome; Remove-Item -Recurse -Force $codexHome }
  # PrBody's order is what the human reads first: human-review and non-Approve on top.
  $body = PrBody @([pscustomobject]@{ Id = 'A-1'; Review = 'agent'; Verdict = 'Approve' },
                   [pscustomobject]@{ Id = 'A-2'; Review = 'human'; Verdict = 'Approve' },
                   [pscustomobject]@{ Id = 'A-3'; Review = 'agent'; Verdict = 'Needs your call: x' })
  if ((($body -split "`n") -like '- *') -join ' ' -notmatch 'A-2 .* A-3 .* A-1') { throw "PrBody: order`n$body" }
  # GitOk must return stdout only: `checkout -b` says "Switched to a new branch" on stderr.
  $tmp = Join-Path $env:TEMP ('sweatshop-git-' + [guid]::NewGuid())
  New-Item -ItemType Directory -Force $tmp | Out-Null
  GitOk -C $tmp init -q | Out-Null
  $leak = @(GitOk -C $tmp checkout -b probe)
  Remove-Item -Recurse -Force $tmp
  if ($leak.Count) { throw "GitOk: stderr leaked into output: $($leak -join ' / ')" }
  # Lock is all that keeps two drivers off one repo: a second process must not get it.
  $l = Lock "sweatshop-selfcheck-$PID" 0
  $other = powershell -NoProfile -Command "[Threading.Mutex]::new(`$false, 'sweatshop-selfcheck-$PID').WaitOne(0)"
  $l.ReleaseMutex(); $l.Dispose()
  if ("$other" -ne 'False') { throw "Lock: a second process got it ($other)" }
  Write-Host 'Self-check OK'; exit 0
}

# --- main loop --------------------------------------------------------------------
# The tree reads off the session, so it comes after Use-Session -- but a run
# Preflight refuses should still tell you where you are.
# Two drivers on one worktree would check out branches under each other.
if (-not $DryRun) {
  $RepoLock = Lock ('sweatshop-repo-' + ($Repo.ToLower() -replace '[\\/:]', '_')) 0
  if (-not $RepoLock) { throw "Another sweatshop is already running on $Repo." }
}
try {
try { if (-not $DryRun) { Preflight } } catch { ShowTree 'Before this run (refused)'; throw }
$session = @(Use-Session)[-1]   # [-1]: the branch is emitted last, so git chatter cannot ride out
Say "session: $session$(if ($DryRun) { ' (read-only local preview; no checkout)' })"
if (-not $DryRun -or $session -in @(GitOk for-each-ref --format='%(refname:short)' refs/heads/ refs/remotes/)) { $Loop = $session }
ShowTree 'Before this run'
if (-not $DryRun) { NoneInflight }
if ($DryRun) {
  Say "Read-only preview; local refs may be stale. Gate '$Gate'; lineup '$LineupName'."
  $preview = NextTicket
  if ($preview) {
    $pm, $pe = if ($preview.Stage -eq 'to-review') { $Model3, $Effort3 } else { Implementer $preview }
    Say "Would run $($preview.Id), $($preview.Stage), $pm $pe on $(RuntimeOf $pm). CLI discovery/authentication deferred to a real run."
  } else { Say 'Nothing runnable in committed local state.' }
  return
}
$hdr = '| When | ID | Stage | Model | Attempt | Outcome | Session | Took | Tokens | Cost | Shutdown s |'
$sep = '|---|---|---|---|---|---|---|---|---|---|---|'
if (-not (Test-Path $RunLog)) { Set-Content -Encoding UTF8 $RunLog "$hdr`n$sep" }
elseif (-not (Select-String -Path $RunLog -SimpleMatch $hdr -Quiet)) {
  # Old rows had another shape. Backfilling would invent values that were never
  # measured: leave them, start a second table.
  Add-Content -Encoding UTF8 $RunLog "`n### Schema change`n`n$hdr`n$sep"
}
Say "Gate '$Gate', base '$Base', lineup '$LineupName': stage 2 $Model2 $Effort2 ($(RuntimeOf $Model2)), stage 3 $Model3 $Effort3 ($(RuntimeOf $Model3)), hard $(if ($ModelHard) { "$ModelHard $EffortHard ($(RuntimeOf $ModelHard))" } else { 'none: stage 2 for every ticket' })"

try {
while (-not (StopAsked) -and ($t = NextTicket)) {
  $attempt = 1 + ((Get-Content $t.File -Raw -Encoding UTF8) | Select-String -AllMatches 'Attempt \d+ failed').Matches.Count
  if (-not $script:ProxyVia) { Ping-Proxy }
  $before = $t.Text
  if ($t.Stage -eq 'to-implement') {
    # A reopened ticket's branch holds the previous pass (tests + code): only a
    # branch this attempt created is safe to drop.
    $hadBranch = [bool](git branch --list $t.Branch)
    $m2, $e2 = Implementer $t
    $impl = "$m2 $e2"
    if ($m2 -ne $Model2) { Say "$($t.Id): hard implementer ($(if ($t.Difficulty -eq 'hard') { 'Difficulty: hard' } else { "$($t.Reopens) reopens" }))" }
    $started = Get-Date
    $res = RunStage $t $m2 $e2 $ImplementMinutes 'implement'
    if ($DryRun) { break }
    if (Park-Infrastructure $t 'implement' $impl $attempt $started) { continue }
    $t = Ticket (Join-Path $Repo $t.File)
    if ($t.Stage -ne 'to-review') {
      $tail = LogTail $script:LastLog; $why = Verdict $script:LastLog
      # A session that committed `blocked` itself stopped to ask, question mark or not.
      # Measured 2026-09-24: PHY-32 ended on prose, read as a failure, burned attempt 2
      # and lost its question with the dropped branch. Keep the whole last message.
      if ($t.Stage -eq 'blocked') { $why = 'asked'; $tail = LogTail $script:LastLog 6000 }
      Reset-Tree $t -DropBranch:(-not $hadBranch -and $why -ne 'asked')
      if ($why -eq 'api-error') { LogStage $t 'implement' $impl $attempt 'api error, not counted' $started; ApiDown $tail; continue }
      if ($why -eq 'asked') {
        # Keep what the attempt built, under another name. Measured 2026-09-30: four asks
        # lost their diagnosis and mutate-verify tables with the dropped branch, and the
        # answers said "resume from these commits".
        $kept = Keep-Asked $t
        Note $t "Attempt $attempt stopped to ask$($kept): $tail" 'blocked'; LogStage $t 'implement' $impl $attempt 'asked, blocked' $started
        Answer-Asked $t $before $tail; continue
      }
      if ($attempt -ge 2) { Note $t "Attempt $attempt failed: $res; blocked after two attempts. Log tail: $tail" 'blocked'; LogStage $t 'implement' $impl $attempt "failed ($res), blocked" $started }
      else { Note $t "Attempt $attempt failed: $res. Log tail: $tail"; LogStage $t 'implement' $impl $attempt "failed ($res), will retry" $started }
      continue
    }
    LogStage $t 'implement' $impl $attempt 'to-review' $started
    if (StopAsked) { break }
  }
  $started = Get-Date
  $res = RunStage $t $Model3 $Effort3 $ReviewMinutes 'review'
  if ($DryRun) { break }
  if (Park-Infrastructure $t 'review' "$Model3 $Effort3" $attempt $started) { continue }
  Reset-Tree $t
  GitOk pull -q --ff-only
  $t = Ticket (Join-Path $Repo $t.File)
  $names = @{ 'done' = 'merged'; 'to-merge' = 'waiting for you'; 'to-implement' = 'reopened' }
  if (-not $names[$t.Stage] -and (Verdict $script:LastLog) -eq 'api-error') {
    LogStage $t 'review' "$Model3 $Effort3"$attempt 'api error, not counted' $started; ApiDown (LogTail $script:LastLog); continue
  }
  $outcome = if ($names[$t.Stage]) { $names[$t.Stage] } else { "review ended at $($t.Stage) ($res)" }
  LogStage $t 'review' "$Model3 $Effort3"$attempt $outcome $started
  if ($outcome -eq 'reopened' -and $t.Reopens -eq 2) {
    Note $t 'Second reopen: foreman diagnosis required before retrying. Classify new defect, earlier review miss, contract gap, or review-induced churn; record cause and next action, then return to-implement only when ready.' 'blocked'
  }
  # A review that stopped short of a verdict (`to-review`, `reviewing`) would be
  # picked again forever or never again: park it for a human.
  if (-not $names[$t.Stage]) { Note $t "Review ended at $($t.Stage) ($res); branch $($t.Branch) holds the review; left for a human" 'blocked' }
}
if (-not $DryRun -and -not $script:Stopped) { Say 'Nothing runnable. Done.' }
} finally {
  # A run that crashed is when you most want the state, so this lives in finally --
  # after Reset-Tree, or the tree would read tickets off whatever branch it died on.
  if (-not $DryRun) { Reset-Tree $null }
  ShowTree 'After this run'
  if (-not $DryRun) {
    try { Publish-Session } catch { Say "session PR failed: $_" }
    git checkout -q $Base   # Preflight wants the base next time
  }
  ShowSummary
}
} finally { if ($RepoLock) { $RepoLock.ReleaseMutex(); $RepoLock.Dispose() } }
