<#
.SYNOPSIS
  Run the sweatshop ticket loop with a fresh Codex CLI context for each stage.
#>
param(
  [Parameter(Mandatory, Position=0)][string]$Repo,
  [string]$Tracker = '.scratch',
  [int]$ImplementMinutes = 45,
  [int]$ReviewMinutes = 20,
  [switch]$DryRun,
  [switch]$SelfCheck
)
& (Join-Path $PSScriptRoot 'sweatshop.ps1') @PSBoundParameters -Runtime Codex
