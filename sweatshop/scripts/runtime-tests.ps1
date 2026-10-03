# Local regression tests: no agent, network, user repository, or live app is started.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'stage-runtime.ps1')
$testRoot = Join-Path $env:TEMP ('sweatshop-runtime-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $testRoot | Out-Null
$shellExe = (Get-Command powershell.exe).Source
function Assert($condition, $message) { if (-not $condition) { throw $message } }
function Encoded($script) { '-NoProfile -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script)) }
function Load-Functions($path) {
  $errors = $null; $tokens = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
  Assert (-not $errors) "Syntax: $errors"
  $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false) |
    ForEach-Object { $_.Extent.Text }
}
$unrelated = $null
try {
  Assert (-not (Test-StageCompleted '{"type":"item.completed","text":"turn.completed"}' 'Codex')) 'Quoted completion is not a runtime event'
  Assert (Test-StageCompleted '{"type":"result","result":"done"}' 'Claude') 'Claude result not recognized'
  Assert (-not (Test-StageCompleted '{"type":"turn.completed"' 'Codex')) 'Partial JSON accepted'
  $unrelated = Start-Process $shellExe -ArgumentList (Encoded 'Start-Sleep -Seconds 60') -WindowStyle Hidden -PassThru
  $childScript = Encoded 'Start-Sleep -Seconds 60'
  $pidFile = Join-Path $testRoot 'child.pid'
  $script = "`$child = Start-Process '$shellExe' -ArgumentList '$childScript' -NoNewWindow -PassThru; [IO.File]::WriteAllText('$pidFile', [string]`$child.Id); Write-Output '{`"type`":`"turn.completed`",`"usage`":{`"input_tokens`":1}}'; Start-Sleep -Seconds 60"
  $log = Join-Path $testRoot 'complete.txt'
  $run = Invoke-StageProcess $shellExe (Encoded $script) $testRoot $log 'Codex' 15 0.5
  Assert ($run.Result -eq 'runtime completed' -and $run.Forced -and -not $run.InfrastructureError) "Completion: $($run | ConvertTo-Json -Compress)"
  Assert ($run.ShutdownSeconds -ge 0.5 -and $run.ShutdownSeconds -lt 8) 'Completion waited for the stage timeout'
  $childPid = [int](Get-Content $pidFile)
  Start-Sleep -Milliseconds 200
  Assert (-not (Get-Process -Id $childPid -ErrorAction SilentlyContinue)) 'Owned child survived cleanup'
  Assert (-not $unrelated.HasExited) 'Cleanup touched another execution'

  # Natural parent exit must also stop its descendants, without waiting for inherited stdout.
  $script = $script -replace '; Start-Sleep -Seconds 60$', ''
  $run = Invoke-StageProcess $shellExe (Encoded $script) $testRoot (Join-Path $testRoot 'exit.txt') 'Codex' 15 2
  Assert ($run.Result -eq 'exit 0' -and -not $run.InfrastructureError) 'Natural process exit failed'
  Start-Sleep -Milliseconds 200
  Assert (-not (Get-Process -Id ([int](Get-Content $pidFile)) -ErrorAction SilentlyContinue)) 'Orphan after natural exit'

  $run = Invoke-StageProcess $shellExe (Encoded 'Start-Sleep -Seconds 60') $testRoot (Join-Path $testRoot 'timeout.txt') 'Codex' 1 0.5
  Assert ($run.Result -eq 'timeout' -and $null -eq $run.CompletedUtc) 'Genuine timeout misclassified'

  $batch = Join-Path $testRoot 'CLI with spaces.cmd'
  [IO.File]::WriteAllText($batch, "@echo off`r`necho {`"type`":`"turn.completed`"}`r`n")
  $run = Invoke-StageProcess $batch '' $testRoot (Join-Path $testRoot 'batch.txt') 'Codex' 15
  Assert ($run.Result -eq 'exit 0' -and $run.CompletedUtc -and -not $run.InfrastructureError) 'Batch CLI path quoting failed'

  $locked = Join-Path $testRoot 'locked.txt'
  [IO.File]::WriteAllText($locked, 'evidence')
  $handle = [IO.File]::Open($locked, 'Open', 'ReadWrite', 'None')
  try {
    $failed = $false
    try { $null = Read-StageLog $locked } catch [IO.IOException] { $failed = $true }
    Assert $failed 'Exclusive lock silently became empty evidence'
    $run = Invoke-StageProcess $shellExe (Encoded 'Write-Output x') $testRoot $locked 'Codex' 1
    Assert ($run.InfrastructureError -and (Test-Path "$locked.runtime.json")) 'Locked log lost infrastructure record'
  } finally { $handle.Dispose() }
  $handle = [IO.File]::Open($locked, 'Open', 'ReadWrite', 'ReadWrite')
  try { Assert ((Read-StageLog $locked) -eq 'evidence') 'Shared writer prevented a log read' } finally { $handle.Dispose() }

  # Load production functions without executing the driver's update, launch, or GitHub paths.
  . ([scriptblock]::Create((Load-Functions (Join-Path $PSScriptRoot 'sweatshop.ps1')) -join "`n"))
  $Repo = Join-Path $testRoot 'repo'; New-Item -ItemType Directory $Repo | Out-Null
  GitOk -C $Repo init -q
  GitOk -C $Repo config user.email test@example.invalid
  GitOk -C $Repo config user.name 'Runtime test'
  Push-Location $Repo
  try {
    [IO.File]::WriteAllText((Join-Path $Repo 'tracked.txt'), 'base')
    GitOk add .; GitOk commit -qm base; $Loop = GitOk branch --show-current
    GitOk checkout -qb t-1
    [IO.File]::WriteAllText((Join-Path $Repo 'tracked.txt'), 'committed work')
    GitOk commit -qam work
    $work = GitOk rev-parse HEAD
    [IO.File]::WriteAllText((Join-Path $Repo 'tracked.txt'), 'unfinished work')
    [IO.File]::WriteAllText((Join-Path $Repo 'new.txt'), 'untracked work')
    $RunDir = $testRoot; $script:LastLog = Join-Path $testRoot 'recovery-log.txt'
    $ticket = [pscustomobject]@{ Id = 'T-1'; Branch = 't-1' }
    Reset-Tree $ticket -DropBranch
    $ref = GitOk for-each-ref --format='%(refname)' refs/sweatshop-recovery/
    Assert ((GitOk show "${ref}:tracked.txt") -eq 'unfinished work') 'Recovery lost tracked edits'
    Assert ((GitOk show "${ref}^3:new.txt") -eq 'untracked work') 'Recovery lost untracked work'
    Assert ((GitOk rev-parse "${ref}^1") -eq $work) 'Recovery lost committed work'
    Assert (-not (GitOk status --porcelain)) 'Recovery did not restore clean session'

    $RunLog = Join-Path $testRoot 'ledger.md'; [IO.File]::WriteAllText($RunLog, '')
    $script:LastUsage = $null; $script:LastShutdownSeconds = 0.5
    $handle = [IO.File]::Open($RunLog, 'Open', 'ReadWrite', 'None')
    try {
      LogStage $ticket implement 'model high' 1 'to-review' (Get-Date)
      Assert ($script:LogWriteFailed -and (Test-Path "$script:LastLog.row.txt")) 'Locked ledger lost stage outcome'
      $summary = (ShowSummary 6>&1 | Out-String)
      Assert ($summary -match 'Summary unavailable') 'Locked ledger crashed summary'
    } finally { $handle.Dispose() }
    [IO.File]::WriteAllText($RunLog, [IO.File]::ReadAllText("$script:LastLog.row.txt"))
    $summary = (ShowSummary 6>&1 | Out-String)
    Assert ($summary -match '1 stages') 'Summary dropped new run-log schema'
    # Exercise parking without pushing a notification commit to any remote.
    function Note($t, $line, $stage) { $script:TestNoteStage = $stage }
    $script:LastInfrastructureError = 'Uncommitted work'; $script:LastFailureKind = 'incomplete handoff'
    Assert (Park-Infrastructure $ticket implement 'model high' 1 (Get-Date)) 'Incomplete handoff not parked'
    Assert ((Read-StageLog "$script:LastLog.row.txt") -match 'failed \(incomplete handoff\), blocked') 'Agent handoff failure charged to infrastructure'
    Assert ($script:TestNoteStage -eq 'blocked') 'Parking did not block the ticket'
    $script:LastInfrastructureError = 'Log unavailable'; $script:LastFailureKind = 'infrastructure'
    Assert (Park-Infrastructure $ticket implement 'model high' 1 (Get-Date)) 'Infrastructure failure not parked'
    Assert ((Read-StageLog "$script:LastLog.row.txt") -match 'infrastructure, blocked') 'Infrastructure failure charged to implementer'
  } finally { Pop-Location }
  Write-Host 'Runtime regression tests passed (completion, ownership, timeout, log locks, recovery, durable outcome).'
} finally {
  if ($unrelated) { if (-not $unrelated.HasExited) { $unrelated.Kill(); $null = $unrelated.WaitForExit(5000) }; $unrelated.Dispose() }
  # Retain the isolated evidence for inspection; no recursive deletion is needed.
  Write-Host "Test evidence: $testRoot"
}
