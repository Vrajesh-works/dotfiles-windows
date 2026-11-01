<#
.SYNOPSIS
  Bootstrap AND rebuild this Windows dev environment. Idempotent: re-run any time.

.DESCRIPTION
  1. Installs packages from packages.txt via winget, plus Hack Nerd Font, herdr,
     Claude Code and Node if missing.
  2. Junctions this repo to ~/.dotfiles (stable path every config points through).
  3. Links app config dirs/files to the files in home/ (edit in place, git-tracked).
  4. Writes PowerShell profile stubs that dot-source home/powershell/profile.ps1.
  5. Merges home/claude/settings.json into ~/.claude/settings.json (managed keys only).
  6. Applies Windows settings from windows-settings.ps1.

  Nothing is ever deleted: anything in the way is renamed to <name>.bak-<timestamp>.

.EXAMPLE
  .\install.ps1 -DryRun              # show what would change
  .\install.ps1                      # full bootstrap / rebuild
  .\install.ps1 -SkipPackages        # relink + settings only (fast)
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$SkipPackages,
  [switch]$SkipWindowsSettings
)

$ErrorActionPreference = 'Stop'
$Repo  = (Resolve-Path $PSScriptRoot).Path
$Dot   = Join-Path $HOME '.dotfiles'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Info($m) { Write-Host "    $m" }
function Warn($m) { Write-Host "    WARN: $m" -ForegroundColor Yellow }
function Has($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Backup-Item($path) {
  $bak = "$path.bak-$Stamp"
  if ($DryRun) { Info "[dry-run] would move $path -> $bak"; return }
  # Move (never delete). Moving a junction/symlink moves the link, not its target.
  Move-Item -LiteralPath $path -Destination $bak -Force
  Info "backed up $path -> $bak"
}

function Ensure-Parent($path) {
  $parent = Split-Path $path -Parent
  if (-not (Test-Path -LiteralPath $parent)) {
    if ($DryRun) { Info "[dry-run] would create $parent" }
    else { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  }
}

function Same-Path($a, $b) {
  $fa = [IO.Path]::GetFullPath($a).TrimEnd('\')
  $fb = [IO.Path]::GetFullPath($b).TrimEnd('\')
  return $fa -ieq $fb
}

# True if $path is already a link that resolves to $target (or its real path).
function Test-LinkTo($path, $target, $realTarget) {
  $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  if (-not $item -or -not $item.LinkType) { return $false }
  if ($item.LinkType -eq 'HardLink') {
    # fsutil prints every name of the file without the drive letter.
    $want = $realTarget.Substring(2)
    $names = & fsutil hardlink list $path 2>$null
    return [bool]($names | Where-Object { $_ -ieq $want })
  }
  foreach ($t in @($item.Target)) {
    if ($t -and ((Same-Path $t $target) -or (Same-Path $t $realTarget))) { return $true }
  }
  return $false
}

$script:CanSymlink = $null
function Test-CanSymlink {
  if ($null -ne $script:CanSymlink) { return $script:CanSymlink }
  $probeDir = Join-Path ([IO.Path]::GetTempPath()) "dotfiles-probe-$Stamp"
  New-Item -ItemType Directory -Path $probeDir -Force | Out-Null
  $src = Join-Path $probeDir 'src.txt'; Set-Content -Path $src -Value 'x'
  try {
    New-Item -ItemType SymbolicLink -Path (Join-Path $probeDir 'lnk.txt') -Target $src -ErrorAction Stop | Out-Null
    $script:CanSymlink = $true
  } catch { $script:CanSymlink = $false }
  Remove-Item -LiteralPath $probeDir -Recurse -Force
  return $script:CanSymlink
}

# Directory: junction (no admin needed). File: symlink, or hardlink if symlinks are not allowed.
function Ensure-Link($path, $target, [switch]$Directory) {
  $realTarget = $target.Replace($Dot, $Repo)
  if (-not (Test-Path -LiteralPath $realTarget)) { throw "Link target missing: $realTarget" }
  if (Test-LinkTo $path $target $realTarget) { Info "ok      $path"; return }

  if (Test-Path -LiteralPath $path) { Backup-Item $path }
  Ensure-Parent $path
  if ($DryRun) { Info "[dry-run] would link $path -> $target"; return }

  if ($Directory) {
    New-Item -ItemType Junction -Path $path -Target $realTarget | Out-Null
    Info "linked  $path -> $realTarget (junction)"
  } elseif (Test-CanSymlink) {
    New-Item -ItemType SymbolicLink -Path $path -Target $target | Out-Null
    Info "linked  $path -> $target (symlink)"
  } else {
    New-Item -ItemType HardLink -Path $path -Target $realTarget | Out-Null
    Info "linked  $path -> $realTarget (hardlink; re-run install.ps1 after git checkouts of this file)"
  }
}

function Ensure-FileContent($path, $content) {
  if ((Test-Path -LiteralPath $path) -and ((Get-Content -LiteralPath $path -Raw) -eq $content)) {
    Info "ok      $path"; return
  }
  if (Test-Path -LiteralPath $path) { Backup-Item $path }
  Ensure-Parent $path
  if ($DryRun) { Info "[dry-run] would write $path"; return }
  [IO.File]::WriteAllText($path, $content)  # UTF-8, no BOM
  Info "wrote   $path"
}

if ($DryRun) { Write-Host '*** DRY RUN: nothing will be changed ***' -ForegroundColor Magenta }

# ---------------------------------------------------------------------------
Step 'Packages'
if ($SkipPackages) {
  Info 'skipped (-SkipPackages)'
} else {
  if (-not (Has 'winget')) { throw 'winget is required (install "App Installer" from the Microsoft Store).' }
  $ids = Get-Content (Join-Path $Repo 'packages.txt') |
         ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ }
  foreach ($id in $ids) {
    & winget list --id $id -e --accept-source-agreements --disable-interactivity *> $null
    if ($LASTEXITCODE -eq 0) { Info "ok      $id"; continue }
    if ($DryRun) { Info "[dry-run] would install $id"; continue }
    Info "install $id"
    & winget install --id $id -e --source winget --silent `
        --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) { Warn "winget install $id exited $LASTEXITCODE" }
  }
  Refresh-Path

  # Node runs the Claude status line + settings merge. Skip if any node exists (e.g. nvm-windows).
  if (Has 'node') { Info 'ok      node' }
  elseif ($DryRun) { Info '[dry-run] would install OpenJS.NodeJS.LTS' }
  else { & winget install --id OpenJS.NodeJS.LTS -e --source winget --silent --accept-package-agreements --accept-source-agreements; Refresh-Path }

  # Official installers (same ones their docs give) when the tool is missing.
  if (Has 'herdr') { Info 'ok      herdr' }
  elseif ($DryRun) { Info '[dry-run] would run herdr installer (https://herdr.dev/install.ps1)' }
  else { Invoke-RestMethod 'https://herdr.dev/install.ps1' | Invoke-Expression; Refresh-Path }

  if (Has 'claude') { Info 'ok      claude' }
  elseif ($DryRun) { Info '[dry-run] would run Claude Code installer (https://claude.ai/install.ps1)' }
  else { Invoke-RestMethod 'https://claude.ai/install.ps1' | Invoke-Expression; Refresh-Path }

  # Hack Nerd Font, installed per-user (no admin) from the official Nerd Fonts release.
  $fontKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
  $userFonts = @((Get-ItemProperty $fontKey -ErrorAction SilentlyContinue).PSObject.Properties.Name)
  $sysFonts  = @((Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts').PSObject.Properties.Name)
  $haveFont = ($userFonts -like 'HackNerdFont*').Count -gt 0 -or ($sysFonts -like 'Hack Nerd Font*').Count -gt 0
  if ($haveFont) { Info 'ok      Hack Nerd Font' }
  elseif ($DryRun) { Info '[dry-run] would install Hack Nerd Font (per-user)' }
  else {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "hack-nerd-font-$Stamp"
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $zip = Join-Path $tmp 'Hack.zip'
    Invoke-WebRequest 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip' -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'x')
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
    if (-not (Test-Path $fontKey)) { New-Item -Path $fontKey | Out-Null }
    Get-ChildItem (Join-Path $tmp 'x') -Filter '*.ttf' | ForEach-Object {
      $dest = Join-Path $fontDir $_.Name
      Copy-Item $_.FullName $dest -Force
      New-ItemProperty -Path $fontKey -Name "$($_.BaseName) (TrueType)" -Value $dest -PropertyType String -Force | Out-Null
    }
    Remove-Item $tmp -Recurse -Force
    Info 'installed Hack Nerd Font (restart apps to see it)'
  }
}

# ---------------------------------------------------------------------------
Step "Stable path: $Dot"
if (Same-Path $Repo $Dot) {
  Info 'repo already lives at ~/.dotfiles'
} else {
  $item = Get-Item -LiteralPath $Dot -Force -ErrorAction SilentlyContinue
  if ($item -and $item.LinkType -and (Same-Path @($item.Target)[0] $Repo)) { Info "ok      $Dot" }
  else {
    if ($item) { Backup-Item $Dot }
    if ($DryRun) { Info "[dry-run] would junction $Dot -> $Repo" }
    else { New-Item -ItemType Junction -Path $Dot -Target $Repo | Out-Null; Info "linked  $Dot -> $Repo" }
  }
}

# ---------------------------------------------------------------------------
Step 'Config links'
Ensure-Link (Join-Path $HOME '.config\wezterm') "$Dot\home\wezterm" -Directory
Ensure-Link (Join-Path $env:LOCALAPPDATA 'nvim') "$Dot\home\nvim" -Directory
Ensure-Link (Join-Path $env:APPDATA 'herdr') "$Dot\home\herdr" -Directory
# One shared rules file for every agent.
Ensure-Link (Join-Path $HOME '.claude\CLAUDE.md') "$Dot\home\agents\AGENTS.md"
Ensure-Link (Join-Path $HOME '.codex\AGENTS.md') "$Dot\home\agents\AGENTS.md"
Ensure-Link (Join-Path $HOME '.config\opencode\AGENTS.md') "$Dot\home\agents\AGENTS.md"

# ---------------------------------------------------------------------------
Step 'PowerShell profiles'
$docs = [Environment]::GetFolderPath('MyDocuments')
$stub = "# Managed by ~/.dotfiles/install.ps1. Edit ~/.dotfiles/home/powershell/profile.ps1 instead.`r`n" +
        '. "$HOME\.dotfiles\home\powershell\profile.ps1"' + "`r`n"
Ensure-FileContent (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1') $stub
Ensure-FileContent (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1') $stub

# Profiles are scripts; the Windows default policy (Restricted) would refuse to load them.
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -eq 'Undefined' -or $policy -eq 'Restricted') {
  if ($DryRun) { Info '[dry-run] would set CurrentUser execution policy to RemoteSigned' }
  else { Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force; Info 'execution policy (CurrentUser) -> RemoteSigned' }
} else { Info "ok      execution policy (CurrentUser) = $policy" }

if ([Environment]::GetEnvironmentVariable('EDITOR', 'User') -ne 'nvim') {
  if ($DryRun) { Info '[dry-run] would set user env EDITOR=nvim' }
  else { [Environment]::SetEnvironmentVariable('EDITOR', 'nvim', 'User'); Info 'user env EDITOR=nvim' }
} else { Info 'ok      EDITOR=nvim' }

# ---------------------------------------------------------------------------
Step 'Claude Code settings (merge managed keys)'
if (-not (Has 'node')) {
  Warn 'node not found; skipped. Install Node and re-run.'
} else {
  $mergeArgs = @(
    (Join-Path $Repo 'home\claude\merge-settings.js'),
    (Join-Path $HOME '.claude\settings.json'),
    (Join-Path $Repo 'home\claude\settings.json'),
    $Dot,
    $Stamp
  )
  if ($DryRun) { $mergeArgs += '--dry-run' }
  & node @mergeArgs
  if ($LASTEXITCODE -ne 0) { throw 'Claude settings merge failed' }
}

# ---------------------------------------------------------------------------
Step 'Windows settings'
if ($SkipWindowsSettings) { Info 'skipped (-SkipWindowsSettings)' }
else { & (Join-Path $Repo 'windows-settings.ps1') -DryRun:$DryRun }

# ---------------------------------------------------------------------------
if (-not $DryRun -and (Has 'herdr')) {
  Step 'herdr'
  & herdr config check
  # Errors when no server is running; PS 5.1 turns that stderr into a terminating error.
  try { & herdr server reload-config 2>$null | Out-Null } catch { }
  $global:LASTEXITCODE = 0
}

Write-Host ''
Write-Host 'Done. Open a new WezTerm window to pick everything up. Re-run install.ps1 after any change.' -ForegroundColor Green
