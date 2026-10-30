# Complete entry-point tests with local repositories and fake command-line runtimes.
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('sweatshop-entry-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $root | Out-Null
$ignore = Join-Path $root 'empty.ignore'; [IO.File]::WriteAllText($ignore, '')
$oldPath = $env:PATH; $checks = 0
$OnWindows = [Environment]::OSVersion.Platform -eq 'Win32NT'
$PowerShellExe = if ($OnWindows) { 'powershell' } else { 'pwsh' }
# A fake CLI in $bin: a .cmd on Windows, an executable shell script elsewhere.
function FakeCli($name, $cmd, $sh) {
  if ($OnWindows) { [IO.File]::WriteAllText("$bin/$name.cmd", "@echo off`r`n$cmd`r`n") }
  else { [IO.File]::WriteAllText("$bin/$name", "#!/bin/sh`n$sh`n"); chmod +x "$bin/$name" }
}
function G {
  $ErrorActionPreference = 'Continue'
  $out = & git @args 2>&1
  if ($LASTEXITCODE) { throw "git $args : $out" }
  $out | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] } | ForEach-Object { "$_" }
}
function Assert($condition, $message) { if (-not $condition) { throw $message } }
function Init($path) {
  New-Item -ItemType Directory $path -Force | Out-Null
  G -C $path init -qb main; G -C $path config user.name Fixture; G -C $path config user.email test@example.invalid
  G -C $path config core.excludesFile $ignore
}
function Snapshot($path) {
  (Get-ChildItem -LiteralPath $path -Recurse -Force -File | Sort-Object FullName | ForEach-Object {
    $_.FullName.Substring($path.Length) + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash
  }) -join "`n"
}
function Target($path, $stage) {
  Init $path; New-Item -ItemType Directory "$path/.scratch/feature/issues" -Force | Out-Null
  [IO.File]::WriteAllText("$path/AGENTS.md", "## Bindings do fluxo`n- Gate: ``fixture gate```n- Base branch: ``main```n- Models (Codex): stage 2 gpt-6.1-sol high, stage 3 gpt-6.1-sol max`n")
  [IO.File]::WriteAllText("$path/.scratch/feature/issues/T-1.md", "# T-1: fixture`nStage: $stage`nBlocked by: none`n")
  G -C $path add .; G -C $path commit -qm base
}
function CopyScripts($path) {
  New-Item -ItemType Directory "$path/sweatshop" -Force | Out-Null
  Copy-Item -LiteralPath $PSScriptRoot -Destination "$path/sweatshop/scripts" -Recurse
  # A Codex-model card: the proxy runs on the fake codex, never on a real CLI.
  [IO.File]::WriteAllText("$path/sweatshop/proxy.md", "---`nname: proxy`nmodel: gpt-6.1-sol`neffort: high`n---`n`nYou stand in for the owner.`n")
}
try {
  $source = Join-Path $root 'standalone'; CopyScripts $source
  $target = Join-Path $root 'dirty offline target'; Target $target to-implement
  G -C $target remote add origin (Join-Path $root 'missing-offline.git')
  G -C $target checkout -qb sweatshop/existing; G -C $target commit -q --allow-empty -m session
  [IO.File]::WriteAllText("$target/.scratch/feature/issues/T-2.md", "# T-2: session-only`nStage: to-review`nBlocked by: none`n")
  G -C $target add .; G -C $target commit -qm sessionticket; G -C $target checkout -q main
  [IO.File]::WriteAllText("$target/.scratch/feature/issues/T-1.md", "# T-1: dirty uncommitted lie`nStage: done`n")
  [IO.File]::WriteAllText("$target/new-uncommitted.txt", 'dirty')
  $bin = Join-Path $root 'bin'; New-Item -ItemType Directory $bin | Out-Null
  $calls = Join-Path $root 'unexpected-cli.txt'
  FakeCli codex "echo unexpected>>`"$calls`"`r`nexit /b 99" "echo unexpected >>'$calls'; exit 99"
  $env:PATH = "$bin$([IO.Path]::PathSeparator)$oldPath"
  $beforeTarget = Snapshot $target; $beforeSource = Snapshot $source
  $log = Join-Path $root 'dryrun.log'
  & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File "$source/sweatshop/scripts/sweatshop.ps1" -Repo $target -Lineup Codex -DryRun *> $log
  Assert ($LASTEXITCODE -eq 0) "DryRun failed: $(Get-Content $log -Raw)"
  Assert ((Snapshot $target) -eq $beforeTarget -and (Snapshot $source) -eq $beforeSource) 'DryRun changed source or dirty/offline target'
  Assert (-not (Test-Path $calls)) 'DryRun called/authenticated a runtime'
  Assert ((Get-Content $log -Raw) -match 'Would run T-2') 'Preview omitted session-only committed ticket'
  $checks++; Write-Host 'PASS dirty/offline DryRun is read-only and sees session-only tickets'
  & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File "$source/sweatshop/scripts/sweatshop.ps1" -Repo (Join-Path $root 'does-not-exist') -SelfCheck *> (Join-Path $root 'selfcheck.log')
  Assert ($LASTEXITCODE -eq 0 -and (Snapshot $source) -eq $beforeSource -and -not (Test-Path $calls)) 'SelfCheck touched source or depended on target/CLI'
  $checks++; Write-Host 'PASS SelfCheck is isolated from supplied target and CLI'

  # Pull V2, reparse entry point, then load only V2 runtime/helpers. Target has no
  # runnable stage here; fake CLIs permit startup/publication without credentials.
  $updating = Join-Path $root 'updating'; CopyScripts $updating; Init $updating
  foreach ($file in 'sweatshop.ps1', 'driver.ps1', 'stage-runtime.ps1') {
    $p = "$updating/sweatshop/scripts/$file"; $s = [IO.File]::ReadAllText($p)
    if ($file -eq 'sweatshop.ps1') { $s = $s.Replace('$runtime = Join-Path', "Write-Host 'BOOT_V1'`n`$runtime = Join-Path") }
    elseif ($file -eq 'driver.ps1') { $s = $s.Replace('# --- bindings', "Write-Host 'RUNTIME_V1'`n# --- bindings") }
    else { $s = "Write-Host 'HELPER_V1'`n" + $s }
    [IO.File]::WriteAllText($p, $s, [Text.UTF8Encoding]::new($true))
  }
  G -C $updating add .; G -C $updating commit -qm v1
  $remote = Join-Path $root 'skills-origin.git'; G init -q --bare -b main $remote
  G -C $updating remote add origin $remote; G -C $updating push -qu origin main
  $publisher = Join-Path $root 'publisher'; G clone -q $remote $publisher
  G -C $publisher config user.name Fixture; G -C $publisher config user.email test@example.invalid; G -C $publisher config core.excludesFile $ignore
  foreach ($file in 'sweatshop.ps1', 'driver.ps1', 'stage-runtime.ps1') {
    $p = "$publisher/sweatshop/scripts/$file"; [IO.File]::WriteAllText($p, ([IO.File]::ReadAllText($p)).Replace('_V1', '_V2'), [Text.UTF8Encoding]::new($true))
  }
  G -C $publisher add .; G -C $publisher commit -qm v2; G -C $publisher push -q
  $target2 = Join-Path $root 'updatetarget'; Target $target2 blocked
  $targetRemote = Join-Path $root 'target-origin.git'; G init -q --bare -b main $targetRemote
  G -C $target2 remote add origin $targetRemote; G -C $target2 push -qu origin main
  FakeCli codex 'exit /b 0' 'exit 0'
  FakeCli gh "if `"%2`"==`"create`" echo https://fixture.invalid/pull/1`r`nexit /b 0" '[ "$2" = create ] && echo https://fixture.invalid/pull/1; exit 0'
  $log = Join-Path $root 'update.log'
  & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File "$updating/sweatshop/scripts/sweatshop.ps1" -Repo $target2 -Lineup Codex -ImplementMinutes 2 -ReviewMinutes 3 *> $log
  Assert ($LASTEXITCODE -eq 0) "Updated driver failed: $(Get-Content $log -Raw)"
  $output = Get-Content $log -Raw
  Assert ($output -match 'BOOT_V2' -and $output -match 'RUNTIME_V2' -and $output -match 'HELPER_V2' -and $output -notmatch '_V1') 'Update mixed executing versions'
  $expectedHash = (Get-FileHash "$updating/sweatshop/scripts/driver.ps1").Hash
  Assert ($output -match $expectedHash -and $output -match "lineup 'Codex'") 'Executed hash or original lineup lost at restart'
  $checks++; Write-Host 'PASS update reparses V2 entry/runtime/helper and preserves arguments'

  # A junction reaches the real skills checkout and retains its update contract.
  $link = Join-Path $root 'linked-skill'
  New-Item -ItemType $(if ($OnWindows) { 'Junction' } else { 'SymbolicLink' }) -Path $link -Target "$updating/sweatshop" | Out-Null
  $log = Join-Path $root 'junction.log'
  & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File "$link/scripts/sweatshop.ps1" -Repo $target2 -Lineup Codex *> $log
  Assert ($LASTEXITCODE -eq 0 -and (Get-Content $log -Raw) -match 'RUNTIME_V2') 'Junction install could not run the actual checkout'
  $checks++; Write-Host 'PASS junction install resolves the real checkout'

  # Per-project copied skills belong to another repo even if tracked there.
  # Its local remote deliberately advances; a copied install must not pull it.
  $holder = Join-Path $root 'unrelated-project'; Init $holder
  New-Item -ItemType Directory "$holder/.claude/skills/sweatshop" -Force | Out-Null
  Copy-Item -LiteralPath $PSScriptRoot -Destination "$holder/.claude/skills/sweatshop/scripts" -Recurse
  G -C $holder add .; G -C $holder commit -qm copiedskill
  $holderRemote = Join-Path $root 'unrelated-origin.git'; G init -q --bare -b main $holderRemote
  G -C $holder remote add origin $holderRemote; G -C $holder push -qu origin main
  $holderPublisher = Join-Path $root 'unrelated-publisher'; G clone -q $holderRemote $holderPublisher
  G -C $holderPublisher config user.name Fixture; G -C $holderPublisher config user.email test@example.invalid; G -C $holderPublisher config core.excludesFile $ignore
  [IO.File]::WriteAllText("$holderPublisher/unrelated.txt", 'this remote must not be pulled')
  G -C $holderPublisher add .; G -C $holderPublisher commit -qm advance; G -C $holderPublisher push -q
  $beforeHolder = Snapshot $holder; $log = Join-Path $root 'copied-project.log'
  & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File "$holder/.claude/skills/sweatshop/scripts/sweatshop.ps1" -Repo $target2 -Lineup Codex *> $log
  Assert ($LASTEXITCODE -eq 0 -and (Snapshot $holder) -eq $beforeHolder) 'Copied project install updated its unrelated owner repository'
  $checks++; Write-Host 'PASS copied project install leaves its unrelated repository unchanged'

  # Fake agent deliberately commits done without integrating. It must be parked,
  # preserved, logged as incomplete, and never release T-2.
  $target3 = Join-Path $root 'invalidhandoff'; Target $target3 to-implement
  [IO.File]::WriteAllText("$target3/.scratch/feature/issues/T-2.md", "# T-2: dependent`nStage: to-implement`nBlocked by: T-1`n")
  G -C $target3 add .; G -C $target3 commit -qm dependent
  $remote3 = Join-Path $root 'invalid-origin.git'; G init -q --bare -b main $remote3
  G -C $target3 remote add origin $remote3; G -C $target3 push -qu origin main
  $fake = Join-Path $root 'fake-agent.ps1'
  # One fake Codex for every call: the proxy's read-only call, the driver's in-harness ping
  # (runs proxy.ps1 unless FAKE_SKIP_PING), and ticket stages by FAKE_SCENARIO.
  [IO.File]::WriteAllText($fake, @'
$ErrorActionPreference = 'Stop'
$i = [array]::IndexOf($args, '--output-last-message'); $final = if ($i -ge 0) { $args[$i + 1] }
$prompt = $args[-1]
if ($args -contains 'read-only') {
  $file = [regex]::Match($prompt, 'Read the file (.+?) in full').Groups[1].Value
  $answer = if ((Get-Content $file -Raw) -match 'Connectivity check') { 'Decision: pong' } else { 'Decision: seam A - fixture' }
  [IO.File]::WriteAllText($final, $answer); Write-Output '{"type":"turn.completed"}'; exit 0
}
$ping = [regex]::Match($prompt, '-File (\S+) -Repo (\S+) -Ping')
if ($ping.Success) {
  $shell = if ([Environment]::OSVersion.Platform -eq 'Win32NT') { 'powershell' } else { 'pwsh' }
  if (-not $env:FAKE_SKIP_PING) { & $shell -NoProfile -ExecutionPolicy Bypass -File $ping.Groups[1].Value -Repo $ping.Groups[2].Value -Ping | Out-Null }
  # What a call that hung in a sandbox leaves (measured 2026-10-29): run files, no receipt.
  else { $d = Join-Path ([IO.Path]::GetTempPath()) 'sweatshop-proxy'; New-Item -ItemType Directory -Force $d | Out-Null; [IO.File]::WriteAllText((Join-Path $d "$(Get-Date -Format yyyyMMdd-HHmmss)-ping-abc123.log.runtime.json"), '{"Result":"running"}') }
  Write-Output '{"type":"turn.completed"}'; exit 0
}
Add-Content (Join-Path ([IO.Path]::GetTempPath()) "fake-agent-env-$env:FAKE_SCENARIO.txt") "SWEATSHOP_PROXY=$env:SWEATSHOP_PROXY"
git checkout -qb t-1
$ticket = Join-Path (Get-Location) '.scratch/feature/issues/T-1.md'
if ($env:FAKE_SCENARIO -eq 'ask') {
  [IO.File]::WriteAllText($ticket, ((Get-Content $ticket -Raw) -replace 'Stage: \S+', 'Stage: blocked') + "`n- Which seam?`n")
} else {
  [IO.File]::WriteAllText($ticket, "# T-1: invalid done`nStage: done`nVerdict: Approve`n")
  [IO.File]::WriteAllText((Join-Path (Get-Location) 'unmerged.txt'), 'saved work')
}
git add .; git commit -qm stage
Write-Output '{"type":"turn.completed"}'
'@)
  FakeCli codex "if `"%1`"==`"login`" exit /b 0`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$fake`" %*`r`nexit /b %errorlevel%" "[ `"`$1`" = login ] && exit 0; exec pwsh -NoProfile -File '$fake' `"`$@`""
  $env:FAKE_SCENARIO = 'handoff'; Remove-Item (Join-Path ([IO.Path]::GetTempPath()) 'fake-agent-env-handoff.txt') -ErrorAction SilentlyContinue
  $log = Join-Path $root 'handoff.log'
  & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File "$source/sweatshop/scripts/sweatshop.ps1" -Repo $target3 -Lineup Codex *> $log
  Assert ($LASTEXITCODE -eq 0) "Recoverable handoff failure crashed: $(Get-Content $log -Raw)"
  $session = @(G -C $target3 for-each-ref '--format=%(refname:short)' refs/heads/sweatshop/)[0]
  Assert ((G -C $target3 show "${session}:.scratch/feature/issues/T-1.md") -match 'Stage: blocked') 'Invalid handoff not parked'
  Assert ((G -C $target3 show 't-1:unmerged.txt') -eq 'saved work') 'Invalid committed work lost'
  $rows = Get-Content "$target3/.scratch/run-log.md" -Raw
  Assert ($rows -match 'incomplete handoff' -and $rows -notmatch '\| T-2 \|' -and $rows -notmatch '\| merged \|') 'Invalid done unlocked dependent or logged merge'
  Assert ((Get-Content $log -Raw) -match 'proxy: gpt-6\.1-sol high answered the ping' -and (Get-Content $log -Raw) -match 'proxy from Codex sessions: reached directly') "Ping not run or not reached: $(Get-Content $log -Raw)"
  Assert ((Get-Content (Join-Path ([IO.Path]::GetTempPath()) 'fake-agent-env-handoff.txt')) -eq 'SWEATSHOP_PROXY=') 'A runtime that reached the proxy ran with the driver fallback'
  $checks++; Write-Host 'PASS fake runtime invalid clean done parks recoverably without releasing dependent'

  # A runtime whose sessions cannot reach the proxy: its stages get SWEATSHOP_PROXY=driver, and the
  # driver answers each ask itself, until a third ask in the run waits for a human.
  $target4 = Join-Path $root 'asking'; Target $target4 to-implement
  $remote4 = Join-Path $root 'asking-origin.git'; G init -q --bare -b main $remote4
  G -C $target4 remote add origin $remote4; G -C $target4 push -qu origin main
  $env:FAKE_SCENARIO = 'ask'; $env:FAKE_SKIP_PING = '1'; Remove-Item (Join-Path ([IO.Path]::GetTempPath()) 'fake-agent-env-ask.txt') -ErrorAction SilentlyContinue
  $log = Join-Path $root 'asking.log'
  & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File "$source/sweatshop/scripts/sweatshop.ps1" -Repo $target4 -Lineup Codex *> $log
  $out = Get-Content $log -Raw
  Assert ($LASTEXITCODE -eq 0) "Asking run crashed: $out"
  Assert ($out -match 'proxy from Codex sessions: unreachable' -and $out -match 'asked a third time this run') "Driver fallback or cap missing: $out"
  $session = @(G -C $target4 for-each-ref '--format=%(refname:short)' refs/heads/sweatshop/)[0]
  $text = (G -C $target4 show "${session}:.scratch/feature/issues/T-1.md") -join "`n"
  Assert ($text -match 'Stage: blocked' -and ([regex]::Matches($text, '(?m)^- \d{4}-\d\d-\d\d Proxy decided \(gpt-6\.1-sol high\): seam A - fixture \(receipt [^)]+\.json\)$')).Count -eq 2) "Driver answers not recorded: $text"
  Assert (@(Get-Content (Join-Path ([IO.Path]::GetTempPath()) 'fake-agent-env-ask.txt') | Where-Object { $_ -ne 'SWEATSHOP_PROXY=driver' }).Count -eq 0) 'Stage of an unreachable runtime did not get the driver fallback'
  $checks++; Write-Host 'PASS unreachable proxy: the driver answers asked stages, twice per ticket per run'
  Write-Host "$checks entry-point checks passed. Fixtures/logs: $root"
} finally { $env:PATH = $oldPath; $env:FAKE_SCENARIO = $null; $env:FAKE_SKIP_PING = $null }
