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
    $caught = $false; try { $null = Ticket "$Repo/.scratch/feature/issues/PHY-7.md" } catch { $caught = $_ -match 'Ambiguous' }
    Assert $caught 'Ambiguous branches silently chose a candidate'
  } finally { Pop-Location }
}
Check 'committed session state wins over dirty working ticket' {
  Fixture dirtyticket; Push-Location $Repo
  try {
    WriteTicket T-1 to-implement; StartSession; WriteTicket T-1 done
    Assert ((Ticket "$Repo/.scratch/feature/issues/T-1.md").Stage -eq 'to-implement') 'Dirty done became committed delivery'
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
Write-Host "$checks checks; $($failures.Count) failures. Fixtures: $root"
if ($failures) { throw ($failures -join "`n") }
