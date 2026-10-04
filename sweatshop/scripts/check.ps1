# Canonical offline gate. No model runtimes or external services are launched.
$ErrorActionPreference = 'Stop'
foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
  $tokens = $null; $errors = $null
  $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
  if ($errors) { throw "Syntax in $($file.Name): $errors" }
}
foreach ($test in 'runtime-tests.ps1', 'pipeline-tests.ps1', 'entrypoint-tests.ps1', 'scoreboard.ps1', 'sweatshop.ps1') {
  Write-Host "Checking $test"
  $testArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $test))
  if ($test -eq 'scoreboard.ps1') { $testArgs += '-SelfCheck' }
  if ($test -eq 'sweatshop.ps1') { $testArgs += @('-Repo', '.', '-SelfCheck') }
  & powershell @testArgs
  if ($LASTEXITCODE) { throw "$test exited $LASTEXITCODE" }
}
Write-Host 'Offline gate passed.'
