# Shared reads tolerate inherited writers; an exclusive lock gets bounded retries.
# Callers retain read failures as infrastructure evidence, not empty successful output.
function Read-StageLog($Path, [int]$TailBytes = 0) {
  for ($readAttempt = 0; $readAttempt -lt 5; $readAttempt++) {
    $stream = $null; $reader = $null
    try {
      $stream = [IO.File]::Open($Path, 'Open', 'Read', [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
      if ($TailBytes -and $stream.Length -gt $TailBytes) { $null = $stream.Seek(-$TailBytes, 'End') }
      $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
      if ($TailBytes -and $stream.Position -gt 0) { $null = $reader.ReadLine() }
      return $reader.ReadToEnd()
    } catch [IO.IOException] {
      if ($readAttempt -eq 4) { throw }
      Start-Sleep -Milliseconds 100
    } finally {
      if ($reader) { $reader.Dispose() } elseif ($stream) { $stream.Dispose() }
    }
  }
}

function Test-StageCompleted($Text, $Runtime) {
  if ($Runtime -eq 'Claude') {
    try { return ($Text | ConvertFrom-Json).type -eq 'result' } catch { return $false }
  }
  foreach ($line in $Text -split "`n") {
    try { if (($line | ConvertFrom-Json).type -eq 'turn.completed') { return $true } } catch { }
  }
  return $false
}

function Invoke-StageProcess($Exe, $Arguments, $WorkingDirectory, $Log, $Runtime,
                             [double]$TimeoutSeconds, [double]$GraceSeconds = 10) {
  $started = [datetime]::UtcNow; $completed = $null; $exited = $null; $owner = $null
  $fault = $null; $result = 'infrastructure'; $code = $null; $forced = $false
  [IO.File]::WriteAllText("$Log.runtime.json", (@{ StartedUtc = $started.ToString('o'); Result = 'running' } | ConvertTo-Json))
  try {
    if (-not ('SweatshopStageProcess' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'StageProcess.cs') }
    $owner = [SweatshopStageProcess]::Start($Exe, $Arguments, $WorkingDirectory, $Log)
    do {
      # OpenCode has no terminal event: its exit is the completion, so skip reading its large log.
      if (-not $completed -and $Runtime -ne 'OpenCode') {
        # Claude emits one JSON object, Codex JSONL. Read the whole Claude result.
        $tail = if ($Runtime -eq 'Codex') { 65536 } else { 0 }
        if (Test-StageCompleted (Read-StageLog $Log $tail) $Runtime) { $completed = [datetime]::UtcNow }
      }
      if ($owner.HasExited) { $exited = [datetime]::UtcNow; $code = $owner.ExitCode; $result = "exit $code"; break }
      $now = [datetime]::UtcNow
      if ($completed -and ($now - $completed).TotalSeconds -ge $GraceSeconds) {
        $owner.Stop(); $forced = $true; $exited = [datetime]::UtcNow; $result = 'runtime completed'; break
      }
      if (-not $completed -and ($now - $started).TotalSeconds -ge $TimeoutSeconds) {
        $owner.Stop(); $forced = $true; $exited = [datetime]::UtcNow; $result = 'timeout'; break
      }
      Start-Sleep -Milliseconds 250
    } while ($true)
  } catch {
    $fault = $_.Exception.Message
    if ($owner) { try { $owner.Stop(); $forced = $true; $exited = [datetime]::UtcNow } catch { $fault += "; cleanup: $($_.Exception.Message)" } }
  } finally {
    if ($owner) {
      try { $owner.Stop() } catch { $fault = "$fault; cleanup: $($_.Exception.Message)" }
      $owner.Dispose()
    }
  }
  $record = [pscustomobject]@{
    StartedUtc = $started.ToString('o'); CompletedUtc = $(if ($completed) { $completed.ToString('o') })
    ExitedUtc = $(if ($exited) { $exited.ToString('o') }); Result = $result; ExitCode = $code
    ShutdownSeconds = $(if ($completed -and $exited) { [math]::Round(($exited - $completed).TotalSeconds, 3) })
    Forced = $forced; InfrastructureError = $fault
  }
  # Written independently of redirected stdout, including when stdout is locked.
  [IO.File]::WriteAllText("$Log.runtime.json", ($record | ConvertTo-Json))
  $record
}

# --- runtimes: shared by the driver and proxy.ps1 -----------------------------------
# The runtime follows the model, so one lineup can pair a Codex implementer with a Claude reviewer.
# ponytail: a name prefix; give the binding a runtime column if a family ever runs on both.
# OpenCode ids are `provider/model`; no Claude or Codex name has a slash.
function RuntimeOf($model) { if ($model -match '/') { 'OpenCode' } elseif ($model -match '^gpt-') { 'Codex' } else { 'Claude' } }
# What `claude --model` takes: `opus-5.5` is `claude-opus-5-5`. Codex names pass as written.
function CliModel($model) { if ($model -match '^(gpt-|claude-)') { $model } else { 'claude-' + ($model -replace '\.', '-') } }
function FindCli($runtime) {
  $probe = if ($runtime -eq 'Claude') {
    # `claude` may not be on PATH: probe the installs the app and the CLI use.
    "$env:APPDATA\Claude\claude-code\*\claude.exe"
    "$env:USERPROFILE\AppData\Roaming\Claude\claude-code\*\claude.exe"
    "$env:USERPROFILE\.local\bin\claude.exe"
    "$env:APPDATA\npm\claude.cmd"
  } elseif ($runtime -eq 'OpenCode') {
    "$env:APPDATA\npm\opencode.cmd"
    "$env:USERPROFILE\.opencode\bin\opencode.exe"
  } else {
    "$env:LOCALAPPDATA\Programs\OpenAI\Codex\bin\codex.exe"
    "$env:LOCALAPPDATA\OpenAI\Codex\bin\*\codex.exe"
    "$env:APPDATA\npm\codex.cmd"
  }
  $exe = (Get-Command $runtime.ToLower() -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
  if (-not $exe) {
    $exe = $probe | ForEach-Object { Get-ChildItem $_ -ErrorAction SilentlyContinue } |
      Sort-Object { try { [version]$_.Directory.Name } catch { [version]"0.0.0" } } |
      Select-Object -Last 1 -ExpandProperty FullName
  }
  if (-not $exe) { throw "No $runtime CLI found. Tried PATH and:`n  $($probe -join "`n  ")" }
  $exe
}
# OpenCode's last `text` event is the session's last message; it has no `result` line.
function OpenCodeFinal($text) {
  $last = ''
  foreach ($l in $text -split "`n") {
    if ($l -like '{"type":"text"*') { try { $last = ($l | ConvertFrom-Json).part.text } catch { } }
  }
  $last
}
