<#
.SYNOPSIS
  The proxy: one card (`../proxy.md`), one model, the same way in from every harness.
  Prints the answer and the line to record under `## Comments`, and writes the receipt
  the driver checks before it accepts that line. The model is the card's `model:`.

.EXAMPLE
  powershell -NoProfile -File proxy.ps1 -Repo <worktree> -Ticket APP-020 -Question '<question + evidence>'
  powershell -NoProfile -File proxy.ps1 -Repo <worktree> -Ticket APP-020 -QuestionFile <file>
  powershell -NoProfile -File proxy.ps1 -Repo <repo> -Ping
#>
[CmdletBinding()]
param([string]$Repo = '.', [string]$Ticket, [string]$Question, [string]$QuestionFile, [switch]$Ping, [int]$TimeoutMinutes = 30)
. (Join-Path $PSScriptRoot 'stage-runtime.ps1')
$ProxyCard = Join-Path (Split-Path $PSScriptRoot) 'proxy.md'
$ProxyScript = Join-Path $PSScriptRoot 'proxy.ps1'
# Outside every repo, like gate receipts: the record is the ticket line, this is its proof.
$ProxyDir = Join-Path ([IO.Path]::GetTempPath()) 'sweatshop-proxy'
# A record line: `- [date ]Proxy decided|escalated[ (<who>)]: ...`. Prose that only quotes
# one (a review block, a Disclosure) does not start with it.
$ProxyLine = '(?m)^[ \t]*(?:-[ \t]+)?(?:\d{4}-\d\d-\d\d[ \t]+)?Proxy (decided|escalated)(?: \(([^)]*)\))?:.*$'
$PingQuestion = 'Connectivity check from the sweatshop driver, not a real question. Read nothing and run nothing. Reply with exactly one line: Decision: pong'

function Read-ProxyCard($path = $ProxyCard) {
  $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
  $m = [regex]::Match($text, '(?s)^---\r?\n(.*?)\r?\n---\r?\n(.*)$')
  if (-not $m.Success) { throw "Proxy card $path has no frontmatter." }
  $model = [regex]::Match($m.Groups[1].Value, '(?m)^model:\s*(\S+)\s*$').Groups[1].Value
  $effort = [regex]::Match($m.Groups[1].Value, '(?m)^effort:\s*(\S+)\s*$').Groups[1].Value
  if (-not $model) { throw "Proxy card $path names no model." }
  # Same rule as the lineups: an alias moves under a run when the next model ships.
  if ((RuntimeOf $model) -eq 'Claude' -and $model -notmatch '\d') { throw "Proxy model '$model' has no version. Pin it: opus-5.5, fable-5.1." }
  [pscustomobject]@{ Model = $model; Effort = $(if ($effort) { $effort } else { 'high' }); Body = $m.Groups[2].Value.Trim() }
}

# Read-only in every runtime: the proxy inspects, the caller edits and commits.
# The card and question travel in a file: a command line mangles quotes and caps length.
function ProxyArgs($runtime, $card, $prompt, $final) {
  $ask = 'Answer the question at the end of your instructions. Your final message is the answer, in the format they give.'
  if ($runtime -eq 'Claude') {
    "-p `"$ask`" --model $(CliModel $card.Model) --effort $($card.Effort) --output-format json --permission-mode dontAsk --allowedTools Read Grep Glob `"Bash(git log:*)`" `"Bash(git show:*)`" `"Bash(git diff:*)`" `"Bash(git grep:*)`" --append-system-prompt-file `"$prompt`""
  } elseif ($runtime -eq 'OpenCode') {
    # The built-in plan agent cannot edit; effort rides in the model id (`provider/model#variant`).
    "run --standalone --agent plan --format json --model $($card.Model) --file `"$prompt`" `"$ask`""
  } else {
    "exec --model $($card.Model) --config model_reasoning_effort=$($card.Effort) --config approval_policy=never --sandbox read-only --json --output-last-message `"$final`" `"Read the file $prompt in full and follow it. $ask`""
  }
}

function Invoke-Proxy($repo, $ticket, $question, [switch]$Ping, [int]$minutes = 30) {
  $card = Read-ProxyCard
  $id = if ($Ping) { 'ping' } else { $ticket }
  if ($Ping) { $question = $PingQuestion }
  if (-not $id -or -not $question) { throw 'Pass -Ticket and the question (-Question or -QuestionFile).' }
  $rt = RuntimeOf $card.Model; $exe = FindCli $rt
  New-Item -ItemType Directory -Force $ProxyDir | Out-Null
  $base = Join-Path $ProxyDir ('{0}-{1}-{2}' -f (Get-Date -Format yyyyMMdd-HHmmss), $id, [guid]::NewGuid().ToString('N').Substring(0, 6))
  $repoPath = (Resolve-Path -LiteralPath $repo).Path
  [IO.File]::WriteAllText("$base.prompt.md", "$($card.Body)`n`n---`n`n# The question`n`nRepository: $repoPath`nTicket: $id`n`n$question`n", [Text.UTF8Encoding]::new($false))
  # OpenCode takes its project from an inherited PWD over its real cwd (driver, measured 2026-10-27).
  if ($rt -eq 'OpenCode') { $env:PWD = $repoPath }
  $run = Invoke-StageProcess $exe (ProxyArgs $rt $card "$base.prompt.md" "$base.final") $repoPath "$base.log" $rt ($minutes * 60)
  if ($run.InfrastructureError) { throw "proxy run failed: $($run.InfrastructureError); log $base.log" }
  $answer = if ($rt -eq 'Claude') { try { ((Read-StageLog "$base.log") | ConvertFrom-Json).result } catch { '' } }
            elseif ($rt -eq 'OpenCode') { OpenCodeFinal (Read-StageLog "$base.log") }
            elseif (Test-Path "$base.final") { Read-StageLog "$base.final" }
  $answer = "$answer".Trim()
  # Markdown emphasis around the label is still the label.
  $m = [regex]::Match(($answer -split '\r?\n')[0], '^[\W_]*(Decision|Escalate)[*_]*:[*_]*\s*(.+?)\s*$')
  if (-not $m.Success) { throw "the proxy ($($card.Model), $($run.Result)) gave no Decision or Escalate line; log $base.log" }
  $who = "$($card.Model) $($card.Effort)"
  $kind = if ($m.Groups[1].Value -eq 'Decision') { 'decided' } else { 'escalated' }
  [pscustomobject]@{ Ticket = $id; Who = $who; Kind = $kind; Question = $question; Answer = $answer; Log = "$base.log"; When = (Get-Date).ToString('o') } |
    ConvertTo-Json | Set-Content -LiteralPath "$base.json" -Encoding UTF8
  [pscustomobject]@{ Ticket = $id; Who = $who; Kind = $kind; Decision = $m.Groups[2].Value; Answer = $answer; Receipt = "$base.json"
                     Line = "Proxy $kind ($who): $($m.Groups[2].Value) (receipt $base.json)" }
}

# Every proxy line a stage added must name a receipt this script wrote, for that ticket and
# by that model. Lines already in $before are history and pass as they are.
function New-ProxyLines($before, $after) {
  $old = @([regex]::Matches("$before", $ProxyLine) | ForEach-Object { $_.Value.Trim() })
  [regex]::Matches("$after", $ProxyLine) | Where-Object { $old -notcontains $_.Value.Trim() }
}
function Assert-ProxyReceipts($id, $before, $after) {
  foreach ($l in @(New-ProxyLines $before $after)) {
    $line = $l.Value.Trim()
    $r = [regex]::Match($line, '\(receipt ([^)]+)\)\s*$')
    if (-not $r.Success) { throw "${id}: '$line' names no proxy receipt; only an answer from proxy.ps1 earns a proxy line." }
    $path = $r.Groups[1].Value.Trim()
    if (-not (Test-Path -LiteralPath $path)) { throw "${id}: proxy receipt $path is missing." }
    $p = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($p.Ticket -ne $id -or $p.Who -ne $l.Groups[2].Value -or $p.Kind -ne $l.Groups[1].Value) {
      throw "${id}: '$line' does not match its receipt (ticket $($p.Ticket), $($p.Who), $($p.Kind))."
    }
  }
}

if ($Ping -or $Question -or $QuestionFile) {
  $stop = 'Stop now: commit Stage: blocked with your question under ## Comments. The driver asks the proxy and relaunches the stage.'
  # The driver's in-harness ping found this runtime cannot reach the proxy: fail at once,
  # not after minutes on a blocked network.
  if ($env:SWEATSHOP_PROXY -eq 'driver') { Write-Output "The proxy is unreachable from this session. $stop"; exit 3 }
  if ($QuestionFile) { $Question = [IO.File]::ReadAllText($QuestionFile, [Text.Encoding]::UTF8) }
  try { $p = Invoke-Proxy $Repo $Ticket $Question -Ping:$Ping -minutes $TimeoutMinutes }
  catch { Write-Output "Proxy failed: $($_.Exception.Message)"; if (-not $Ping) { Write-Output $stop }; exit 2 }
  Write-Output $p.Answer
  Write-Output "`nRecord under ## Comments, as is:`n- $($p.Line)"
  exit 0
}
