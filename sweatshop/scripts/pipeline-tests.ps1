# Offline production regressions. Every repository and CLI here is disposable.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP ('sweatshop-pipeline-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $root | Out-Null
$failures = @(); $checks = 0
function Check($name, [scriptblock]$body) {
  $script:checks++
  try { & $body; Write-Host "PASS $name" } catch { $script:failures += "$name : $_"; Write-Host "FAIL $name : $_" }
}
function Assert($condition, $message) { if (-not $condition) { throw $message } }
function LoadFunctions($path) {
  $tokens = $null; $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
  if ($errors) { throw "Syntax: $errors" }
  ($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]}, $false) | ForEach-Object { $_.Extent.Text }) -join "`n"
}
$driver = Join-Path $PSScriptRoot 'driver.ps1'
if (-not (Test-Path $driver)) { $driver = Join-Path $PSScriptRoot 'sweatshop.ps1' }
. ([scriptblock]::Create((LoadFunctions $driver)))
foreach ($helper in 'ticket-state.ps1', 'gate-evidence.ps1') {
  $path = Join-Path $PSScriptRoot $helper
  if (Test-Path $path) { . ([scriptblock]::Create((LoadFunctions $path))) }
}
. (Join-Path $PSScriptRoot 'proxy.ps1')
$ProxyDir = Join-Path $root 'proxy-receipts'
# The driver's own test-path pattern, not a copy that could drift from it.
$tokens = $null; $errors = $null
$assign = [Management.Automation.Language.Parser]::ParseFile($driver, [ref]$tokens, [ref]$errors).FindAll({param($n)
  $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$TestFiles' -and $n.Operator -eq 'Equals' }, $false)
. ([scriptblock]::Create($assign[0].Extent.Text))
# A fake Codex: the proxy's read-only call answers $env:FAKE_PROXY_ANSWER into --output-last-message.
$fakeBin = Join-Path $root 'bin'; New-Item -ItemType Directory $fakeBin -Force | Out-Null
[IO.File]::WriteAllText("$fakeBin/fake-codex.ps1", @'
$i = [array]::IndexOf($args, '--output-last-message')
if ($env:FAKE_PROXY_ANSWER -and $i -ge 0) { [IO.File]::WriteAllText($args[$i + 1], $env:FAKE_PROXY_ANSWER) }
Write-Output '{"type":"turn.completed","usage":{"input_tokens":1}}'
'@)
[IO.File]::WriteAllText("$fakeBin/codex.cmd", "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$fakeBin/fake-codex.ps1`" %*`r`n")
$fakeCard = Join-Path $root 'proxy.md'
[IO.File]::WriteAllText($fakeCard, "---`nname: proxy`nmodel: gpt-fake`neffort: high`n---`n`nYou stand in for the owner.`n")
$ProxyCard = $fakeCard
$env:PATH = "$fakeBin;$env:PATH"
function Fixture($name) {
  $script:Repo = Join-Path $root $name
  New-Item -ItemType Directory "$Repo/.scratch/feature/issues" -Force | Out-Null
  GitOk -C $Repo init -qb main
  GitOk -C $Repo config user.name 'Pipeline regression'
  GitOk -C $Repo config user.email test@example.invalid
  $ignore = Join-Path $root 'empty.ignore'; [IO.File]::WriteAllText($ignore, '')
  GitOk -C $Repo config core.excludesFile $ignore
  $script:Tracker = '.scratch'; $script:Loop = 'sweatshop/test'; $script:Base = 'main'
}
function WriteTicket($id, $stage, $blocked = 'none', $extra = '') {
  [IO.File]::WriteAllText("$Repo/.scratch/feature/issues/$id.md", "# ${id}: Fixture`nStage: $stage`nBlocked by: $blocked`nReview: agent`n`n## Comments`n$extra`n")
}
function StartSession { GitOk add .; GitOk commit -qm base; GitOk checkout -qb $Loop; GitOk commit -q --allow-empty -m session }
Check 'unmerged done cannot release a dependency' {
  Fixture topology; Push-Location $Repo
  try {
    WriteTicket T-1 to-implement; WriteTicket T-2 to-implement T-1; StartSession
    GitOk checkout -qb t-1; WriteTicket T-1 done none 'Verdict: Approve'
    [IO.File]::WriteAllText("$Repo/feature.txt", 'not integrated'); GitOk add .; GitOk commit -qm invalid
    GitOk checkout -q $Loop
    $t = Ticket "$Repo/.scratch/feature/issues/T-1.md"
    Assert ($t.Stage -ne 'done' -and $t.HandoffError) 'Unmerged done counted as delivered'
    Assert (-not (NextTicket)) 'Dependent started without its implementation'
    GitOk merge -q --no-ff t-1 -m merge
    Assert ((Ticket "$Repo/.scratch/feature/issues/T-1.md").Stage -eq 'done') 'Real merge rejected'
    Assert ((NextTicket).Id -eq 'T-2') 'Real merge did not release dependent'
    GitOk checkout -q t-1; WriteTicket T-1 to-implement none 'Verdict: Reopen - regression'; GitOk commit -qam reopen
    GitOk checkout -q $Loop
    Assert ((NextTicket).Id -eq 'T-1') 'Reopened flow did not retain the active branch'
  } finally { Pop-Location }
}
Check 'asked branches preserve work but cannot hide a session answer' {
  Fixture asked; Push-Location $Repo
  try {
    WriteTicket PHY-1 to-implement; StartSession
    GitOk checkout -qb phy/PHY-1-example; WriteTicket PHY-1 blocked; GitOk commit -qam ask
    GitOk checkout -q $Loop; GitOk branch -m phy/PHY-1-example phy/PHY-1-example-asked-20261004-1800
    WriteTicket PHY-1 to-implement none '- Proxy decided: answered'; GitOk commit -qam answer
    Assert ((NextTicket).Id -eq 'PHY-1') 'Retained question shadows answered ticket'
    Assert (git branch --list phy/PHY-1-example-asked-20261004-1800) 'Preserved work disappeared'
  } finally { Pop-Location }
}
Check 'prefixed and exact lowercase discovery agree and reject ambiguity' {
  Fixture discovery; Push-Location $Repo
  try {
    WriteTicket PHY-7 to-implement; StartSession
    GitOk checkout -qb phy/PHY-7-example; WriteTicket PHY-7 to-review; GitOk commit -qam ready
    GitOk checkout -q $Loop
    Assert ((Ticket "$Repo/.scratch/feature/issues/PHY-7.md").Stage -eq 'to-review') 'Prefix branch ignored'
    GitOk branch phy-7 phy/PHY-7-example
    $t = Ticket "$Repo/.scratch/feature/issues/PHY-7.md"
    Assert ($t.Stage -eq 'invalid-handoff' -and $t.HandoffError -match 'Ambiguous') 'Ambiguous branches silently chose a candidate'
  } finally { Pop-Location }
}
Check 'committed session state wins over dirty working ticket' {
  Fixture dirtyticket; Push-Location $Repo
  try {
    WriteTicket T-1 to-implement; StartSession; WriteTicket T-1 done
    Assert ((Ticket "$Repo/.scratch/feature/issues/T-1.md").Stage -eq 'to-implement') 'Dirty done became committed delivery'
  } finally { Pop-Location }
}
Check 'pre-rebase copy of a merged ticket branch is spent, new work on it is not' {
  Fixture rebased; Push-Location $Repo
  try {
    WriteTicket T-1 to-implement; StartSession
    GitOk checkout -qb t-1; [IO.File]::WriteAllText("$Repo/feature.txt", 'work'); GitOk add .; GitOk commit -qm work
    WriteTicket T-1 to-review; GitOk commit -qam ready
    # The PR lands rebased: same patches, new hashes, then review closes it on the session.
    GitOk checkout -q $Loop; WriteTicket T-2 to-implement; GitOk add .; GitOk commit -qm other
    GitOk cherry-pick "$Loop..t-1" | Out-Null; WriteTicket T-1 done none 'Verdict: Approve'; GitOk commit -qam close
    Assert ((Ticket "$Repo/.scratch/feature/issues/T-1.md").Stage -eq 'done') 'Stale pre-rebase branch reopened a done ticket'
    Assert ((NextTicket).Id -eq 'T-2') 'Stale branch was dispatched for review again'
    GitOk checkout -q t-1; [IO.File]::WriteAllText("$Repo/feature.txt", 'more'); WriteTicket T-1 to-review; GitOk commit -qam more
    GitOk checkout -q $Loop
    Assert ((Ticket "$Repo/.scratch/feature/issues/T-1.md").Stage -eq 'to-review') 'Unmerged commits on the branch were ignored'
  } finally { Pop-Location }
}
Check 'remote-only stage and linear local/origin histories follow the same discovery contract' {
  Fixture remote; Push-Location $Repo
  try {
    WriteTicket PHY-9 to-implement; StartSession
    GitOk checkout -qb phy/PHY-9-work; WriteTicket PHY-9 implementing; GitOk commit -qam starting
    GitOk update-ref refs/remotes/origin/phy/PHY-9-work HEAD
    WriteTicket PHY-9 to-review; GitOk commit -qam ready
    Assert ((Find-TicketBranch $Repo PHY-9 -Remote) -eq 'phy/PHY-9-work') 'Normal unpushed local work became ambiguity'
    GitOk update-ref refs/remotes/origin/phy/PHY-9-work HEAD
    GitOk checkout -q $Loop; GitOk branch -q -D phy/PHY-9-work
    Assert ((Ticket "$Repo/.scratch/feature/issues/PHY-9.md").Stage -eq 'to-review') 'Remote-only stage differs from dispatch'
    GitOk checkout -qb phy/PHY-9-work $Loop
    WriteTicket PHY-9 to-review; GitOk commit -qam divergent
    GitOk checkout -q $Loop; WriteTicket PHY-10 to-implement; GitOk add .; GitOk commit -qm other
    $t = Ticket "$Repo/.scratch/feature/issues/PHY-9.md"
    Assert ($t.Stage -eq 'invalid-handoff' -and $t.HandoffError -match 'Ambiguous') 'Divergent local/origin histories silently selected a stage'
    Assert ((NextTicket).Id -eq 'PHY-10') 'One ambiguous ticket stopped the others'
    WriteTicket PHY-9 blocked; GitOk commit -qam parked
    $t = Ticket "$Repo/.scratch/feature/issues/PHY-9.md"
    Assert ($t.Stage -eq 'blocked' -and -not $t.HandoffError) 'Parked ambiguous ticket still refuses the next run'
  } finally { Pop-Location }
}
Check 'PR preserves decisions debt deferred defects and unknown legacy acceptance' {
  Fixture disclosure; Push-Location $Repo
  try {
    WriteTicket T-3 done none "Verdict: Approve`n- Proxy decided: criterion 4 removed.`n- Débito humano: real-device playtest.`nDisclosure: deferred | release | [BUG-8](BUG-8.md) known stale output"
    StartSession
    $body = PrBody @((Ticket "$Repo/.scratch/feature/issues/T-3.md"))
    Assert ($body -match 'Proxy decided' -and $body -match 'Débito humano' -and $body -match 'BUG-8' -and $body -match 'release') 'PR loses material disclosure'
    Assert ($body -match '(?i)acceptance.*unknown') 'Legacy missing acceptance falsely appears complete'
  } finally { Pop-Location }
}
Check 'old done comment edit is disclosure context not a newly completed ticket' {
  Fixture completed; Push-Location $Repo
  try {
    WriteTicket T-1 done; WriteTicket T-2 to-implement; StartSession
    WriteTicket T-1 done none '- Proxy decided: context only'; WriteTicket T-2 done
    GitOk add .; GitOk commit -qm completion
    $done = @(CompletedTickets)
    Assert ($done.Count -eq 1 -and $done[0].Id -eq 'T-2') 'Old done counted as produced'
    $body = SessionBody
    Assert ($body -match 'T-1' -and $body -match 'context only') 'Old ticket material context disappeared'
    GitOk rm -q .scratch/feature/issues/T-1.md; GitOk commit -qm retire
    Assert (@(CompletedTickets).Count -eq 1) 'Deleted historical ticket broke session publication'
  } finally { Pop-Location }
}
Check 'gate evidence accepts metadata close but rejects stale skill or script code' {
  Fixture gate; Push-Location $Repo
  try {
    WriteTicket T-1 to-implement
    [IO.File]::WriteAllText("$Repo/SKILL.md", 'production instructions')
    [IO.File]::WriteAllText("$Repo/code.ps1", 'production script')
    StartSession
    $log = Join-Path $root 'gate.log'; [IO.File]::WriteAllText($log, "OK`nExitCode: 0`n")
    $receipt = Join-Path $root 'gate.json'; $Gate = 'fixture gate'
    Save-GateEvidence $Repo $Gate 0 $log $receipt
    WriteTicket T-1 to-review none "Gate evidence: $receipt"; GitOk commit -qam handoff
    $t = Ticket "$Repo/.scratch/feature/issues/T-1.md"
    Assert-GateEvidence $t $Loop
    # Rewritten history can retain identical production, so a new green run is waste.
    GitOk checkout -q --orphan rewritten
    GitOk add .; GitOk commit -qm rewritten
    Assert-GateEvidence $t rewritten
    GitOk checkout -q $Loop
    foreach ($file in 'SKILL.md', 'code.ps1') {
      [IO.File]::WriteAllText("$Repo/$file", 'changed'); GitOk commit -qam changed
      $caught = $false; try { Assert-GateEvidence $t $Loop } catch { $caught = $true }
      Assert $caught "Changed $file accepted stale receipt"
      GitOk reset -q --hard HEAD~1
    }
    [IO.File]::WriteAllText("$Repo/code.ps1", 'dirty')
    $caught = $false; try { Save-GateEvidence $Repo $Gate 0 $log $receipt } catch { $caught = $true }
    Assert $caught 'Dirty production received evidence'
    GitOk reset -q --hard
    $caught = $false; try { Save-GateEvidence $Repo $Gate 1 $log $receipt } catch { $caught = $true }
    Assert $caught 'Failed gate received green evidence'
  } finally { Pop-Location }
}
Check 'recompleted old ticket counts only after a committed reopen cycle' {
  Fixture recompleted; Push-Location $Repo
  try {
    WriteTicket T-1 done; StartSession
    WriteTicket T-1 done none '- old comment'; GitOk commit -qam comment
    Assert (@(CompletedTickets).Count -eq 0) 'Old comment became completion'
    WriteTicket T-1 to-implement none 'Verdict: Reopen - confirmed defect'; GitOk commit -qam reopen
    WriteTicket T-1 done none 'Verdict: Approve'; GitOk commit -qam repair
    Assert (@(CompletedTickets).Count -eq 1) 'Real reopened delivery disappeared from completed work'
  } finally { Pop-Location }
}
Check 'legacy closed status on an unmerged branch cannot release a dependency' {
  Fixture legacy; Push-Location $Repo
  try {
    WriteTicket T-1 to-implement; WriteTicket T-2 to-implement T-1; StartSession
    GitOk checkout -qb t-1
    [IO.File]::WriteAllText("$Repo/.scratch/feature/issues/T-1.md", "# T-1: legacy`nStatus: resolved`n")
    GitOk commit -qam invalid; GitOk checkout -q $Loop
    Assert ((Ticket "$Repo/.scratch/feature/issues/T-1.md").HandoffError -and -not (NextTicket)) 'Legacy closed status bypassed topology guard'
  } finally { Pop-Location }
}
Check 'gate runner records actual exit and invalidates reused evidence on failure' {
  Fixture gaterunner; Push-Location $Repo
  try {
    WriteTicket T-1 to-implement; StartSession
    $log = Join-Path $root 'gate with spaces.log'; $receipt = Join-Path $root 'gate with spaces.json'
    $runner = Join-Path $PSScriptRoot 'gate-evidence.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Repo $Repo -Command 'Write-Output green' -Log $log -Receipt $receipt *> (Join-Path $root 'gate-success-transcript.log')
    Assert ($LASTEXITCODE -eq 0 -and (Test-Path $receipt)) 'Successful wrapper did not record green evidence'
    Assert ((Get-Content $log -Raw) -match 'green[\s\S]*ExitCode: 0') 'Gate output or actual status missing'
    # A gate grandchild that outlives the gate (a preview server) must not hold the helper or its caller open.
    $leak = Measure-Command { & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Repo $Repo -Command 'cmd /c start /b powershell -NoProfile -c Start-Sleep 30; Write-Output green' -Log $log -Receipt $receipt *> (Join-Path $root 'gate-leak-transcript.log') }
    Assert ($LASTEXITCODE -eq 0 -and $leak.TotalSeconds -lt 20 -and (Test-Path $receipt)) "Gate helper waited $([int]$leak.TotalSeconds)s for a leaked grandchild"
    # PS 5.1 promotes native stderr under Stop; this child is expected to fail.
    $ErrorActionPreference = 'Continue'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Repo $Repo -Command 'exit 7' -Log $log -Receipt $receipt *> (Join-Path $root 'gate-failure-transcript.log')
    $failedExit = $LASTEXITCODE; $ErrorActionPreference = 'Stop'
    Assert ($failedExit -ne 0 -and -not (Test-Path $receipt)) 'Failed rerun retained old green receipt'
    Assert ((Get-Content $log -Raw) -match 'ExitCode: 7') 'Wrapper dropped real failure exit code'
    $ErrorActionPreference = 'Continue'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Repo $Repo -Command 'git commit -q --allow-empty -m changed' -Log $log -Receipt $receipt *> (Join-Path $root 'gate-changing-transcript.log')
    $changedExit = $LASTEXITCODE; $ErrorActionPreference = 'Stop'
    Assert ($changedExit -ne 0 -and -not (Test-Path $receipt)) 'Gate attributed evidence after moving HEAD'
  } finally { Pop-Location }
}
Check 'lanes keep to their own folder and session' {
  Fixture lanes; Push-Location $Repo
  try {
    $origin = Join-Path $root 'lanes-origin.git'; GitOk init -q --bare -b main $origin
    New-Item -ItemType Directory "$Repo/.scratch/other/issues" -Force | Out-Null
    $other = "$Repo/.scratch/other/issues/O-1.md"
    WriteTicket L-1 to-implement; [IO.File]::WriteAllText($other, "# O-1: Other`nStage: to-implement`nBlocked by: none`n")
    GitOk add .; GitOk commit -qm base; GitOk remote add origin $origin; GitOk push -q -u origin main
    # The other lane is mid-run: its own session and a pushed ticket branch at `implementing`.
    GitOk checkout -qb sweatshop/other/2026-01-01-0000; GitOk commit -q --allow-empty -m 'open other'; GitOk push -q -u origin HEAD
    GitOk checkout -qb o-1; [IO.File]::WriteAllText($other, "# O-1: Other`nStage: implementing`nBlocked by: none`n")
    GitOk commit -qam claim; GitOk push -q -u origin HEAD; GitOk checkout -q main
    $script:Lane = 'feature'; $script:Loop = 'main'
    $s = @(Use-Session)[-1]
    Assert ($s -like 'sweatshop/feature/*') "Lane session named $s"
    $script:Loop = $s
    NoneInflight
    Assert ((NextTicket).Id -eq 'L-1') 'Lane ran outside its folder'
    $script:Lane = 'other'; $script:Loop = 'main'; GitOk checkout -q main
    Assert (@(Use-Session)[-1] -eq 'sweatshop/other/2026-01-01-0000') 'Lane did not resume its own session'
    $script:Lane = $null; GitOk checkout -q main
    $refused = try { Use-Session; '' } catch { "$_" }
    Assert ($refused -match 'Lane sessions are open') "Run without a lane took a lane session: $refused"
    GitOk checkout -qb sweatshop/2026-01-01-0000; GitOk commit -q --allow-empty -m 'open lane-less'; GitOk checkout -q main
    $script:Lane = 'feature'
    $refused = try { Use-Session; '' } catch { "$_" }
    Assert ($refused -match 'A session without a lane is open') "Lane ran beside a lane-less session: $refused"
  } finally { $script:Lane = $null; Pop-Location }
}
Check 'retry drops a ticket branch held by a leftover stage worktree and keeps its work' {
  Fixture worktree; Push-Location $Repo
  try {
    WriteTicket T-1 to-implement; StartSession
    $script:RunDir = Join-Path $root 'worktree-run'; New-Item -ItemType Directory $RunDir -Force | Out-Null
    $wt = Join-Path $root 'worktree-T-1'
    GitOk worktree add -q -b t-1 $wt $Loop
    [IO.File]::WriteAllText("$wt/attempt.txt", 'uncommitted attempt')
    Reset-Tree ([pscustomobject]@{ Id = 'T-1'; Branch = 't-1' }) -DropBranch
    Assert (-not (Test-Path $wt)) 'Leftover worktree survived the reset'
    Assert (-not (git branch --list t-1)) 'Ticket branch survived, so the retry reads a stale stage'
    $saved = (Get-Content (Join-Path $RunDir 'recovery.txt')) -match 'worktree'
    Assert $saved 'Worktree recovery not recorded'
    $ref = ($saved[0] -split ' ')[0]
    Assert ((GitOk show "${ref}^3:attempt.txt") -eq 'uncommitted attempt') 'Uncommitted worktree work lost'
  } finally { Pop-Location }
}
Check 'a commit mixing test and production fails the handoff; split commits, metadata and listed fixtures pass' {
  Fixture testfirst; Push-Location $Repo
  try {
    WriteTicket T-1 to-implement; StartSession
    $saved = $TestFiles; $script:TestFiles = "$TestFiles|^shared/cases\.json$"
    $commit = { param($msg, [string[]]$files) foreach ($f in $files) { New-Item -ItemType Directory -Force (Split-Path "$Repo/$f") | Out-Null; [IO.File]::WriteAllText("$Repo/$f", "$msg $f") }; GitOk add .; GitOk commit -qm $msg }
    # Mixed work already on the session is not this stage's.
    & $commit 'session mix' 'old.test.ts', 'old.ts'
    GitOk checkout -qb t-1
    & $commit 'red' 'app/src/soma.test.ts', 'flutter/test/soma_test.dart'
    & $commit 'green' 'app/src/soma.ts', '.scratch/feature/issues/T-1.md'
    & $commit 'fixture' 'shared/cases.json', 'tools/test_soma.py'
    $t = [pscustomobject]@{ Id = 'T-1'; Branch = 't-1' }
    Assert-TestFirst $t $null
    $from = GitOk rev-parse t-1
    & $commit 'mixed' 'app/src/sub.test.ts', 'app/src/sub.ts'
    $caught = try { Assert-TestFirst $t $null; '' } catch { "$_" }
    Assert ($caught -match 'mixes app/src/sub\.test\.ts with app/src/sub\.ts') "Mixed commit passed: $caught"
    GitOk reset -q --hard HEAD~1
    # A reopen keeps the last pass: commits before the stage started are not re-judged.
    & $commit 'earlier pass' 'b.test.ts', 'b.ts'; $from = GitOk rev-parse t-1
    & $commit 'this pass' 'c.test.ts'
    Assert-TestFirst $t $from
    # Bringing the session in by merge is not a commit of the stage.
    GitOk checkout -q $Loop; & $commit 'session mix 2' 'd.test.ts', 'd.ts'; GitOk checkout -q t-1; GitOk merge -q --no-edit $Loop
    Assert-TestFirst $t $from
  } finally { $script:TestFiles = $saved; Pop-Location }
}
Check 'proxy lines need a receipt from proxy.ps1 for that ticket and model; history and quotes pass' {
  Fixture receipts; Push-Location $Repo
  try {
    $env:FAKE_PROXY_ANSWER = "**Decision:** use the seam in soma.ts — the spec names it`n`nDraft criterion: 4. ..."
    $p = Invoke-Proxy $Repo 'T-1' 'Which seam?'
    Assert ($p.Kind -eq 'decided' -and $p.Who -eq 'gpt-fake high' -and $p.Decision -eq 'use the seam in soma.ts — the spec names it') "Answer misread: $($p | ConvertTo-Json)"
    Assert ((Get-Content $p.Receipt -Raw | ConvertFrom-Json).Answer -match 'Draft criterion') 'Receipt lost the full answer'
    $legacy = "## Comments`n- 2026-10-01 Proxy decided: legacy, no receipt`n- Proxy decided (opus): legacy`n"
    $after = "$legacy- 2026-10-29 $($p.Line)`nAs duas linhas ``Proxy decided`` foram revisadas.`nDisclosure: decision | none | Proxy decided (opus), Comments`n"
    Assert-ProxyReceipts 'T-1' $legacy $after
    foreach ($bad in @("- Proxy decided (gpt-fake high): typed by the stage", "- 2026-10-29 Proxy escalated: no who",
                       ($p.Line -replace 'gpt-fake high', 'opus-5.5 xhigh'), ($p.Line -replace 'Proxy decided', 'Proxy escalated'))) {
      $caught = try { Assert-ProxyReceipts 'T-1' $legacy "$legacy$bad`n"; '' } catch { "$_" }
      Assert $caught "Accepted: $bad"
    }
    $caught = try { Assert-ProxyReceipts 'T-2' '' "- $($p.Line)"; '' } catch { "$_" }
    Assert ($caught -match 'does not match') "Receipt for T-1 accepted on T-2: $caught"
    $env:FAKE_PROXY_ANSWER = "Escalate: deleting the progress table loses data`n`nQuestion for the owner: ..."
    Assert ((Invoke-Proxy $Repo 'T-1' 'Drop the table?').Line -match '^Proxy escalated \(gpt-fake high\): deleting') 'Escalation misread'
    $env:FAKE_PROXY_ANSWER = 'I think seam A.'
    $caught = try { Invoke-Proxy $Repo 'T-1' 'Which?'; '' } catch { "$_" }
    Assert ($caught -match 'no Decision or Escalate') "Unlabelled answer accepted: $caught"
  } finally { $env:FAKE_PROXY_ANSWER = $null; Pop-Location }
}
Check 'proxy.ps1 from a session: answers, pings, and fails fast where the ping failed' {
  Fixture proxycli; Push-Location $Repo
  try {
    $card = Join-Path $root 'proxycli-install'; New-Item -ItemType Directory "$card/scripts" -Force | Out-Null
    Copy-Item (Join-Path $PSScriptRoot '*.ps1'), (Join-Path $PSScriptRoot 'StageProcess.cs') "$card/scripts"
    Copy-Item $fakeCard "$card/proxy.md"
    $script = "$card/scripts/proxy.ps1"; $ErrorActionPreference = 'Continue'
    $env:FAKE_PROXY_ANSWER = 'Decision: pong'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Repo $Repo -Ping 2>&1 | Out-String; $code = $LASTEXITCODE
    Assert ($code -eq 0 -and $out -match 'Decision: pong') "Ping: $code $out"
    $env:FAKE_PROXY_ANSWER = 'Decision: yes — fixture'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Repo $Repo -Ticket T-1 -Question 'Is it?' 2>&1 | Out-String
    Assert ($LASTEXITCODE -eq 0 -and $out -match '(?m)^- Proxy decided \(gpt-fake high\): yes — fixture \(receipt .+\.json\)') "Answer: $out"
    $env:SWEATSHOP_PROXY = 'driver'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Repo $Repo -Ticket T-1 -Question 'Is it?' 2>&1 | Out-String
    Assert ($LASTEXITCODE -eq 3 -and $out -match 'Stage: blocked') "Fail-fast: $LASTEXITCODE $out"
    $env:SWEATSHOP_PROXY = $null; $env:FAKE_PROXY_ANSWER = $null
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Repo $Repo -Ticket T-1 -Question 'Is it?' 2>&1 | Out-String
    Assert ($LASTEXITCODE -eq 2 -and $out -match 'Proxy failed' -and $out -match 'Stage: blocked') "Failure: $LASTEXITCODE $out"
  } finally { $env:SWEATSHOP_PROXY = $null; $env:FAKE_PROXY_ANSWER = $null; $ErrorActionPreference = 'Stop'; Pop-Location }
}
Check 'the driver puts an asked stage to the proxy: decision resumes, escalation stays, a third ask waits' {
  Fixture asked2; Push-Location $Repo
  try {
    $origin = Join-Path $root 'asked2-origin.git'; GitOk init -q --bare -b main $origin
    WriteTicket T-1 to-implement; StartSession; GitOk remote add origin $origin; GitOk push -q -u origin $Loop
    $before = (Ticket "$Repo/.scratch/feature/issues/T-1.md").Text
    $ask = { WriteTicket T-1 blocked none '- Which seam?'; GitOk commit -qam ask; Ticket "$Repo/.scratch/feature/issues/T-1.md" }
    $env:FAKE_PROXY_ANSWER = "Decision: seam A — the spec names it`nDraft: criterion 5."
    Answer-Asked (& $ask) $before 'Which seam?'
    $t = Ticket "$Repo/.scratch/feature/issues/T-1.md"
    Assert ($t.Stage -eq 'to-implement' -and $t.Text -match '(?m)^- \d{4}-\d\d-\d\d Proxy decided \(gpt-fake high\): seam A' -and $t.Text -match '(?m)^  > Draft: criterion 5\.') "Decision not recorded: $($t.Text)"
    Assert-ProxyReceipts 'T-1' $before $t.Text
    $env:FAKE_PROXY_ANSWER = 'Escalate: it spends money'
    Answer-Asked (& $ask) $before 'Pay?'
    $t = Ticket "$Repo/.scratch/feature/issues/T-1.md"
    Assert ($t.Stage -eq 'blocked' -and $t.Text -match 'Proxy escalated \(gpt-fake high\): it spends money') "Escalation not recorded: $($t.Text)"
    $third = & $ask
    Answer-Asked $third $before 'Third?'
    Assert ((Ticket "$Repo/.scratch/feature/issues/T-1.md").Text -eq $third.Text) 'Third ask went to the proxy'
    # A stage that reached the proxy itself and got Escalate is the human's already.
    $script:Asked = @{}
    $p = Invoke-Proxy $Repo 'T-1' 'x'
    $stageText = "$before`n- $($p.Line)"
    $env:FAKE_PROXY_ANSWER = 'Decision: should not be asked'
    $last = (Ticket "$Repo/.scratch/feature/issues/T-1.md").Text
    Answer-Asked ([pscustomobject]@{ Id = 'T-1'; File = '.scratch/feature/issues/T-1.md'; Text = $stageText }) $before 'x'
    Assert ((Ticket "$Repo/.scratch/feature/issues/T-1.md").Text -eq $last) 'Asked the proxy again after its escalation'
  } finally { $env:FAKE_PROXY_ANSWER = $null; $script:Asked = $null; Pop-Location }
}
Check 'an asked reopen resumes after the answer: its stale blocked branch is kept aside' {
  Fixture askedreopen; Push-Location $Repo
  try {
    $origin = Join-Path $root 'askedreopen-origin.git'; GitOk init -q --bare -b main $origin
    WriteTicket T-1 to-implement; StartSession; GitOk remote add origin $origin; GitOk push -q -u origin $Loop
    $before = (Ticket "$Repo/.scratch/feature/issues/T-1.md").Text
    # The previous pass lives on the ticket's branch; this attempt asked on top of it.
    GitOk checkout -qb t-1; [IO.File]::WriteAllText("$Repo/pass1.ts", 'previous pass'); GitOk add .; GitOk commit -qm pass1
    WriteTicket T-1 blocked none '- Which seam?'; GitOk commit -qam ask; GitOk checkout -q $Loop
    $t = Ticket "$Repo/.scratch/feature/issues/T-1.md"
    $kept = Keep-Asked $t
    Note $t "Attempt 1 stopped to ask$($kept): Which seam?" 'blocked'
    $env:FAKE_PROXY_ANSWER = 'Decision: seam A - resume from the kept branch'
    Answer-Asked $t $before 'Which seam?'
    Assert ((NextTicket).Id -eq 'T-1' -and (NextTicket).Stage -eq 'to-implement') 'The answer did not make the reopened ticket runnable'
    Assert ($kept -match 'recovery/asked/\d{8}-\d{6}/T-1') "Asked branch not kept aside: '$kept'"
    $branch = [regex]::Match($kept, '`([^`]+)`').Groups[1].Value
    Assert ((GitOk show "${branch}:pass1.ts") -eq 'previous pass') 'The previous pass was lost'
  } finally { $env:FAKE_PROXY_ANSWER = $null; $script:Asked = $null; Pop-Location }
}
Write-Host "$checks checks; $($failures.Count) failures. Fixtures: $root"
if ($failures) { throw ($failures -join "`n") }
