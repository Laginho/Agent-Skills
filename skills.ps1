# skills.ps1 — instala uma skill nas três ferramentas, de uma vez, para todos os projetos.
#
# Fonte da verdade: D:\Desktop\Projects\Agent-Skills\<nome>\SKILL.md
# As ferramentas leem junctions apontando pra lá, então editar a skill na lib
# reflete nas três na hora, sem reinstalar.
#
# Uso:
#   .\skills.ps1 list                    # o que está na lib, com a description
#   .\skills.ps1 add grill-me            # cria as junctions (uma vez por skill, pra sempre)
#   .\skills.ps1 add mattpocock	dd      # namespace: instala como 'mattpocock-tdd'
#   .\skills.ps1 sync                    # recria tudo — máquina nova, após o git clone
#   .\skills.ps1 prune                   # remove links de skills que não existem mais na lib
#
# Junction não exige admin nem Developer Mode. Se alguma ferramenta não
# enxergar a skill, rode com -Copy que ele copia a pasta em vez de linkar.
#
# Outro caminho de lib: $env:SKILLS_LIB = 'D:\outro\caminho'

param(
  [Parameter(Position=0)][ValidateSet('list','add','sync','prune','paths')][string]$Command = 'list',
  [Parameter(Position=1)][string]$Name,
  [switch]$Copy
)

$Lib = if ($env:SKILLS_LIB) { $env:SKILLS_LIB } else { 'D:\Desktop\Projects\Agent-Skills' }
$Targets = @(
  (Join-Path $env:USERPROFILE '.claude\skills')                    # Claude Code
  (Join-Path $env:USERPROFILE '.agents\skills')                    # Codex
  (Join-Path $env:USERPROFILE '.gemini\antigravity\skills')        # Antigravity IDE
  (Join-Path $env:USERPROFILE '.gemini\config\skills')             # Antigravity 2.0
)
# A doc do Antigravity lista caminhos globais diferentes por secao: IDE usa
# .gemini\antigravity\skills, "2.0" usa .gemini\config\skills, e a CLI usa
# .gemini\antigravity-cli\skills (removida aqui, nao uso CLI). Mantive os dois
# primeiros porque a doc conflita. Rode 'paths' para ver quais o Antigravity
# realmente criou na sua maquina, e apague desta lista o que sobrar.

# Remove um destino com segurança. CRÍTICO: em junction/symlink, apaga só o
# link — nunca o conteúdo apontado. Remove-Item -Recurse num reparse point
# tem histórico de apagar o alvo, o que destruiria a skill na sua lib.
function Remove-Target($path) {
  if (-not (Test-Path $path)) { return }
  $item = Get-Item $path -Force
  if ($item.LinkType) { $item.Delete() }
  else { Remove-Item $path -Recurse -Force }
}

# Uma skill e qualquer pasta com SKILL.md, ate um nivel de namespace:
#   <lib>\tdd\SKILL.md              -> instala como 'tdd'
#   <lib>\mattpocock\tdd\SKILL.md   -> instala como 'mattpocock-tdd'
# Get-SkillDirs devolve o caminho relativo; Get-LinkName vira o nome do link.
function Get-SkillDirs {
  Get-ChildItem $Lib -Directory | ForEach-Object {
    if (Test-Path (Join-Path $_.FullName 'SKILL.md')) { $_.Name }
    else {
      Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } |
        ForEach-Object { Join-Path $_.Parent.Name $_.Name }
    }
  }
}

function Get-LinkName($rel) { $rel.Replace('\', '-').Replace('/', '-') }

function Get-Description($skillDir) {
  $f = Join-Path $skillDir 'SKILL.md'
  if (-not (Test-Path $f)) { return '(sem SKILL.md)' }
  $line = Select-String -Path $f -Pattern '^description:' | Select-Object -First 1
  if (-not $line) { return '(sem description)' }
  ($line.Line -replace '^description:\s*', '').Trim('"', "'")
}

function Install-One($skillName) {
  $src = Join-Path $Lib $skillName
  $link = Get-LinkName $skillName
  if (-not (Test-Path (Join-Path $src 'SKILL.md'))) {
    Write-Host "  FALTA   $skillName (nao achei $src\SKILL.md)" -ForegroundColor Yellow
    return
  }
  foreach ($t in $Targets) {
    New-Item -ItemType Directory -Force -Path $t | Out-Null
    $dst = Join-Path $t $link
    Remove-Target $dst
    if ($Copy) { Copy-Item $src $dst -Recurse -Force }
    else       { New-Item -ItemType Junction -Path $dst -Target $src | Out-Null }
    Write-Host "  ok      $dst"
  }
}

if ($Command -eq 'paths') {
  Write-Host "Destinos configurados:`n"
  foreach ($t in $Targets) {
    $state = if (Test-Path $t) { 'existe' } else { 'nao existe' }
    Write-Host ("  [{0,-10}] {1}" -f $state, $t)
  }
  Write-Host "`nTudo que o Antigravity criou em .gemini:`n"
  Get-ChildItem (Join-Path $env:USERPROFILE '.gemini') -Recurse -Directory -Filter 'skills' -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host "  $($_.FullName)" }
  exit 0
}

if (-not (Test-Path $Lib)) { Write-Host "Lib nao encontrada: $Lib" -ForegroundColor Yellow; exit 1 }

switch ($Command) {
  'list' {
    $installed = @{}
    Get-ChildItem $Targets[0] -Directory -ErrorAction SilentlyContinue | ForEach-Object { $installed[$_.Name] = $true }
    Get-SkillDirs | ForEach-Object {
      $mark = if ($installed[(Get-LinkName $_)]) { '*' } else { ' ' }
      $d = Get-Description (Join-Path $Lib $_)
      if ($d.Length -gt 100) { $d = $d.Substring(0,100) + '...' }
      Write-Host ("{0} {1,-34} {2}" -f $mark, $_, $d)
    }
    Write-Host "`n* instalada   (lib: $Lib)"
  }
  'add'   { if (-not $Name) { Write-Host 'uso: .\skills.ps1 add <nome>'; exit 1 }; Install-One $Name }
  'sync'  { Get-SkillDirs | ForEach-Object { Install-One $_ } }
  'prune' {
    $known = @{}; Get-SkillDirs | ForEach-Object { $known[(Get-LinkName $_)] = $true }
    foreach ($t in $Targets) {
      Get-ChildItem $t -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        # só toca no que é link: pasta real ali pode ser skill instalada por fora
        if ($_.LinkType -and -not $known[$_.Name]) {
          Remove-Target $_.FullName
          Write-Host "  removido $($_.FullName)"
        }
      }
    }
    Write-Host "`nPronto. Pastas reais (nao-link) foram preservadas."
  }
}