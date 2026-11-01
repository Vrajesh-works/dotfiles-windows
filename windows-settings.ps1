<#
.SYNOPSIS
  Declarative Windows preferences (the nix-darwin "system.defaults" equivalent).
  Per-user (HKCU) only, no admin needed. Only touches values that differ.
  Edit the table below to change what gets applied.
#>
[CmdletBinding()]
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
$adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$theme = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'

# Path, Name, Value, Explorer restart needed?, Description
$settings = @(
  @($theme, 'AppsUseLightTheme',    0, $false, 'dark mode (apps)'),
  @($theme, 'SystemUsesLightTheme', 0, $false, 'dark mode (system)'),
  @($adv,   'HideFileExt',          0, $true,  'always show file extensions'),
  @($adv,   'HideIcons',            1, $true,  'clean desktop (hide desktop icons)')
)

$restartExplorer = $false
function Info($m) { Write-Host "    $m" }

foreach ($s in $settings) {
  $path, $name, $value, $needsRestart, $desc = $s
  $cur = (Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue).$name
  if ($null -ne $cur -and [int]$cur -eq $value) { Info "ok      $desc"; continue }
  if ($DryRun) { Info "[dry-run] would set $desc ($name=$value)"; continue }
  if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path | Out-Null }
  New-ItemProperty -LiteralPath $path -Name $name -Value $value -PropertyType DWord -Force | Out-Null
  Info "set     $desc"
  if ($needsRestart) { $restartExplorer = $true }
}

# Auto-hide taskbar: byte 8 of StuckRects3\Settings is 3 (auto-hide) or 2 (always shown).
$sr = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
$bytes = (Get-ItemProperty -LiteralPath $sr -ErrorAction SilentlyContinue).Settings
if ($bytes) {
  if ($bytes[8] -eq 3) { Info 'ok      auto-hide taskbar' }
  elseif ($DryRun) { Info '[dry-run] would auto-hide taskbar' }
  else {
    $bytes[8] = 3
    Set-ItemProperty -LiteralPath $sr -Name Settings -Value $bytes
    Info 'set     auto-hide taskbar'
    $restartExplorer = $true
  }
}

# Fast key repeat + short delay. SystemParametersInfo applies live AND persists to the registry.
$kb = Get-ItemProperty 'HKCU:\Control Panel\Keyboard'
if ([int]$kb.KeyboardDelay -eq 0 -and [int]$kb.KeyboardSpeed -eq 31) {
  Info 'ok      fast key repeat, short delay'
} elseif ($DryRun) {
  Info '[dry-run] would set fast key repeat (speed 31) and short delay (0)'
} else {
  if (-not ('Dotfiles.Spi' -as [type])) {
    Add-Type -Namespace Dotfiles -Name Spi -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(uint action, uint param, System.IntPtr vparam, uint winIni);
'@
  }
  $SPIF = 0x1 -bor 0x2  # UPDATEINIFILE | SENDCHANGE
  [void][Dotfiles.Spi]::SystemParametersInfo(0x0017, 0, [IntPtr]::Zero, $SPIF)   # SPI_SETKEYBOARDDELAY
  [void][Dotfiles.Spi]::SystemParametersInfo(0x000B, 31, [IntPtr]::Zero, $SPIF)  # SPI_SETKEYBOARDSPEED
  Info 'set     fast key repeat, short delay'
}

if ($restartExplorer) {
  Info 'restarting Explorer to apply (open File Explorer windows will close)'
  Stop-Process -Name explorer -Force
}
