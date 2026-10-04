# Complete entry-point tests with local repositories and fake command-line runtimes.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP ('sweatshop-entry-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $root | Out-Null
$ignore = Join-Path $root 'empty.ignore'; [IO.File]::WriteAllText($ignore, '')
$oldPath = $env:PATH; $checks = 0
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
  New-Item -ItemType Directory $path -Force | Out-Null
  Copy-Item -LiteralPath $PSScriptRoot -Destination "$path/scripts" -Recurse
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
  [IO.File]::WriteAllText("$bin/codex.cmd", "@echo off`r`necho unexpected>>`"$calls`"`r`nexit /b 99`r`n")
  $env:PATH = "$bin;$oldPath"
  $beforeTarget = Snapshot $target; $beforeSource = Snapshot $source
  $log = Join-Path $root 'dryrun.log'
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$source/scripts/sweatshop.ps1" -Repo $target -Lineup Codex -DryRun *> $log
  Assert ($LASTEXITCODE -eq 0) "DryRun failed: $(Get-Content $log -Raw)"
  Assert ((Snapshot $target) -eq $beforeTarget -and (Snapshot $source) -eq $beforeSource) 'DryRun changed source or dirty/offline target'
  Assert (-not (Test-Path $calls)) 'DryRun called/authenticated a runtime'
  Assert ((Get-Content $log -Raw) -match 'Would run T-2') 'Preview omitted session-only committed ticket'
  $checks++; Write-Host 'PASS dirty/offline DryRun is read-only and sees session-only tickets'
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$source/scripts/sweatshop.ps1" -Repo (Join-Path $root 'does-not-exist') -SelfCheck *> (Join-Path $root 'selfcheck.log')
  Assert ($LASTEXITCODE -eq 0 -and (Snapshot $source) -eq $beforeSource -and -not (Test-Path $calls)) 'SelfCheck touched source or depended on target/CLI'
  $checks++; Write-Host 'PASS SelfCheck is isolated from supplied target and CLI'

  # Pull V2, reparse entry point, then load only V2 runtime/helpers. Target has no
  # runnable stage here; fake CLIs permit startup/publication without credentials.
  $updating = Join-Path $root 'updating'; CopyScripts $updating; Init $updating
  foreach ($file in 'sweatshop.ps1', 'driver.ps1', 'stage-runtime.ps1') {
    $p = "$updating/scripts/$file"; $s = [IO.File]::ReadAllText($p)
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
    $p = "$publisher/scripts/$file"; [IO.File]::WriteAllText($p, ([IO.File]::ReadAllText($p)).Replace('_V1', '_V2'), [Text.UTF8Encoding]::new($true))
  }
  G -C $publisher add .; G -C $publisher commit -qm v2; G -C $publisher push -q
  $target2 = Join-Path $root 'updatetarget'; Target $target2 blocked
  $targetRemote = Join-Path $root 'target-origin.git'; G init -q --bare -b main $targetRemote
  G -C $target2 remote add origin $targetRemote; G -C $target2 push -qu origin main
  [IO.File]::WriteAllText("$bin/codex.cmd", "@echo off`r`nexit /b 0`r`n")
  [IO.File]::WriteAllText("$bin/gh.cmd", "@echo off`r`nif `"%2`"==`"create`" echo https://fixture.invalid/pull/1`r`nexit /b 0`r`n")
  $log = Join-Path $root 'update.log'
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$updating/scripts/sweatshop.ps1" -Repo $target2 -Lineup Codex -ImplementMinutes 2 -ReviewMinutes 3 *> $log
  Assert ($LASTEXITCODE -eq 0) "Updated driver failed: $(Get-Content $log -Raw)"
  $output = Get-Content $log -Raw
  Assert ($output -match 'BOOT_V2' -and $output -match 'RUNTIME_V2' -and $output -match 'HELPER_V2' -and $output -notmatch '_V1') 'Update mixed executing versions'
  $expectedHash = (Get-FileHash "$updating/scripts/driver.ps1").Hash
  Assert ($output -match $expectedHash -and $output -match "lineup 'Codex'") 'Executed hash or original lineup lost at restart'
  $checks++; Write-Host 'PASS update reparses V2 entry/runtime/helper and preserves arguments'

  # Fake agent deliberately commits done without integrating. It must be parked,
  # preserved, logged as incomplete, and never release T-2.
  $target3 = Join-Path $root 'invalidhandoff'; Target $target3 to-implement
  [IO.File]::WriteAllText("$target3/.scratch/feature/issues/T-2.md", "# T-2: dependent`nStage: to-implement`nBlocked by: T-1`n")
  G -C $target3 add .; G -C $target3 commit -qm dependent
  $remote3 = Join-Path $root 'invalid-origin.git'; G init -q --bare -b main $remote3
  G -C $target3 remote add origin $remote3; G -C $target3 push -qu origin main
  $fake = Join-Path $root 'fake-agent.ps1'
  [IO.File]::WriteAllText($fake, @'
$ErrorActionPreference = 'Stop'
git checkout -qb t-1
[IO.File]::WriteAllText((Join-Path (Get-Location) '.scratch/feature/issues/T-1.md'), "# T-1: invalid done`nStage: done`nVerdict: Approve`n")
[IO.File]::WriteAllText((Join-Path (Get-Location) 'unmerged.txt'), 'saved work')
git add .; git commit -qm invalid
Write-Output '{"type":"turn.completed"}'
'@)
  [IO.File]::WriteAllText("$bin/codex.cmd", "@echo off`r`nif `"%1`"==`"login`" exit /b 0`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$fake`"`r`nexit /b %errorlevel%`r`n")
  $log = Join-Path $root 'handoff.log'
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$source/scripts/sweatshop.ps1" -Repo $target3 -Lineup Codex *> $log
  Assert ($LASTEXITCODE -eq 0) "Recoverable handoff failure crashed: $(Get-Content $log -Raw)"
  $session = @(G -C $target3 for-each-ref '--format=%(refname:short)' refs/heads/sweatshop/)[0]
  Assert ((G -C $target3 show "${session}:.scratch/feature/issues/T-1.md") -match 'Stage: blocked') 'Invalid handoff not parked'
  Assert ((G -C $target3 show 't-1:unmerged.txt') -eq 'saved work') 'Invalid committed work lost'
  $rows = Get-Content "$target3/.scratch/run-log.md" -Raw
  Assert ($rows -match 'incomplete handoff' -and $rows -notmatch '\| T-2 \|' -and $rows -notmatch '\| merged \|') 'Invalid done unlocked dependent or logged merge'
  $checks++; Write-Host 'PASS fake runtime invalid clean done parks recoverably without releasing dependent'
  Write-Host "$checks entry-point checks passed. Fixtures/logs: $root"
} finally { $env:PATH = $oldPath }
