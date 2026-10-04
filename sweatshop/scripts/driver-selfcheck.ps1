# Execute the driver's own checks without update, target setup or CLI discovery.
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'driver.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors) { throw "Driver syntax: $errors" }
. (Join-Path $PSScriptRoot 'stage-runtime.ps1')
$functions = $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]}, $false)
. ([scriptblock]::Create(($functions | ForEach-Object { $_.Extent.Text }) -join "`n"))
$prices = $ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$CodexPrices'}, $false)
. ([scriptblock]::Create($prices.Extent.Text))
$self = $ast.FindAll({param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$SelfCheck'}, $false)
$SelfCheck = $true
. ([scriptblock]::Create($self.Extent.Text))
