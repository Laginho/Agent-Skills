<#
.SYNOPSIS
  Smoke test for the dashboard Worker, outside the gate (it needs the network): a write
  without the token and a read without the password are refused, a sample snapshot lands
  and reads back. Takes the driver's two env vars and the page's password. The `smoke`
  project stays on the page for 7 days.

.EXAMPLE
  powershell -NoProfile -File smoke.ps1 -ReadPassword <password>
  powershell -NoProfile -File smoke.ps1 -Url http://127.0.0.1:8787 -Token local -ReadPassword local   # wrangler dev
#>
param([string]$Url = $env:SWEATSHOP_DASH_URL, [string]$Token = $env:SWEATSHOP_DASH_TOKEN,
      [Parameter(Mandatory)][string]$ReadPassword)
$ErrorActionPreference = 'Stop'
if (-not ($Url -and $Token)) { throw 'Set SWEATSHOP_DASH_URL and SWEATSHOP_DASH_TOKEN, or pass -Url and -Token.' }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$Url = $Url.TrimEnd('/')
$basic = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("smoke:$ReadPassword")) }
function StatusOf($call) { try { & $call | Out-Null; 200 } catch { [int]$_.Exception.Response.StatusCode } }

$mark = "smoke $([guid]::NewGuid().ToString('N').Substring(0, 8))"
$at = (Get-Date).ToUniversalTime().ToString('o')
$snap = @{ project = 'smoke'; lane = 'main'; pc = [Environment]::MachineName; foreman = 'smoke'; session = 'smoke'
           driver = 'finished'; current = $null; tickets = @(); needsHuman = @(); events = @(@{ at = $at; text = $mark })
           pr = $null; costToday = '$0.000'; updatedAt = $at } | ConvertTo-Json -Depth 5
# Bytes, not a string: PS 5.1 would send a string body as ISO-8859-1.
$post = @{ Method = 'Post'; Uri = "$Url/api/lane"; Body = [Text.Encoding]::UTF8.GetBytes($snap)
           ContentType = 'application/json; charset=utf-8'; TimeoutSec = 10 }

$code = StatusOf { Invoke-RestMethod @post }
if ($code -ne 401) { throw "A write without the token got $code, expected 401." }
$code = StatusOf { Invoke-RestMethod -Uri "$Url/api/lanes" -TimeoutSec 10 }
if ($code -ne 401) { throw "A read without the password got $code, expected 401." }

Invoke-RestMethod @post -Headers @{ Authorization = "Bearer $Token" } | Out-Null
$got = Invoke-RestMethod -Uri "$Url/api/lanes" -Headers $basic -TimeoutSec 10
$lane = @($got.lanes | Where-Object { $_.project -eq 'smoke' -and $_.lane -eq 'main' })
if ($lane.Count -ne 1 -or $lane[0].events[0].text -ne $mark) { throw "The snapshot did not read back: $($got | ConvertTo-Json -Depth 6 -Compress)" }
if ([math]::Abs($got.now - $lane[0].receivedAt) -gt 60000) { throw "receivedAt $($lane[0].receivedAt) is not the server's now $($got.now)." }
Write-Host "Smoke passed: $Url"
