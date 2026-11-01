# PowerShell profile for Windows PowerShell 5.1 and PowerShell 7.
# Loaded by the stub install.ps1 writes into each $PROFILE. Edit this file, not the stubs.

[Console]::OutputEncoding = [Text.Encoding]::UTF8   # render prompt glyphs correctly
$env:EDITOR = 'nvim'
$env:STARSHIP_CONFIG = "$HOME\.dotfiles\home\starship\starship.toml"

# --- zsh-style ergonomics via PSReadLine -----------------------------------
# Syntax highlighting is built into PSReadLine. Inline history suggestions (ghost text)
# need PSReadLine 2.1+, which ships with PowerShell 7.
if (Get-Module -ListAvailable -Name PSReadLine) {
  Import-Module PSReadLine
  $psrl = (Get-Module PSReadLine).Version
  # Predictions need an interactive VT console; agents and scripts run with redirected
  # output, where enabling them throws. Skip there so non-interactive shells stay quiet.
  if ($psrl -ge [version]'2.1.0' -and -not [Console]::IsOutputRedirected) {
    try {
      Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
      Set-PSReadLineKeyHandler -Chord 'Ctrl+f' -Function AcceptSuggestion   # accept ghost text
      if ($psrl -ge [version]'2.2.0') { Set-PSReadLineOption -PredictionViewStyle InlineView }
    } catch { }
  }
  Set-PSReadLineOption -HistoryNoDuplicates
  Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}

# --- aliases (functions, so they can take arguments) ------------------------
function .. { Set-Location .. }
function add { git add . @args }
function push { git push @args }
function pull { git pull @args }
function m { git switch main @args }
# High-agency agent shortcuts: these skip permission prompts. Know what they do.
function cc { claude --dangerously-skip-permissions @args }
function co { codex --full-auto @args }
Set-Alias -Name vim -Value nvim
function rebuild { & "$HOME\.dotfiles\install.ps1" @args }

# --- prompt ------------------------------------------------------------------
if (Get-Command starship -ErrorAction SilentlyContinue) {
  Invoke-Expression (& starship init powershell --print-full-init | Out-String)
}
