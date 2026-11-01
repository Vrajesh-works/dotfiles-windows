# dotfiles-windows

My Windows 11 agentic-engineering setup. One repo, one command, and a fresh
machine ends up configured the same way every time.

## Credit

This repo follows the method from Kun Chen's
[dotfiles](https://github.com/kunchenguid/dotfiles) and his
[walkthrough video](https://youtu.be/5N-okeDdIuI): a declarative, reproducible dotfiles
repo where every config lives in git and is linked into place, so a new machine (or one an
agent broke) can be rebuilt with a single command. His setup targets macOS with Nix,
nix-darwin, home-manager and Homebrew, none of which exist natively on Windows.

This is my attempt to keep the same tools (WezTerm, Neovim, herdr, Starship, Claude Code,
one shared AGENTS.md) and the same workflow, optimized for Windows:

- **No admin required.** Directory junctions instead of symlinks; per-user font install;
  per-user registry settings. Symlinks are used for files when Developer Mode allows it.
- **Safe by default.** `-DryRun` previews every change; anything in the way is renamed to a
  timestamped backup, never deleted.
- **Idempotent.** Re-running only changes what drifted, like `darwin-rebuild switch`.
- **Coexists with app-owned files.** Claude Code rewrites its own `settings.json`, so only the
  managed keys are merged in instead of replacing the file.
- **Works in Windows PowerShell 5.1 and PowerShell 7**, and stays quiet in the
  non-interactive shells agents run.

## macOS to Windows mapping

| macOS (original)             | Windows (this repo)                                   |
|------------------------------|-------------------------------------------------------|
| Nix + Homebrew               | winget (`packages.txt`) + official installers         |
| nix-darwin `system.defaults` | `windows-settings.ps1` (per-user registry, no admin)  |
| home-manager symlinks        | `install.ps1`: junctions (dirs), symlinks/hardlinks (files) |
| zsh + autosuggestions        | PowerShell 7 + PSReadLine inline history suggestions  |
| `rebuild.sh`                 | `install.ps1` (idempotent) or the `rebuild` function  |

## Setup

```powershell
git clone https://github.com/Vrajesh-works/dotfiles-windows.git $HOME\dotfiles
cd $HOME\dotfiles
powershell -ExecutionPolicy Bypass -File .\install.ps1 -DryRun   # preview
powershell -ExecutionPolicy Bypass -File .\install.ps1           # apply
```

Afterwards, run `rebuild` (or `.\install.ps1`) after any change. Flags:
`-DryRun`, `-SkipPackages` (fast relink), `-SkipWindowsSettings`.

Nothing is deleted: anything in the way of a link is renamed to `<name>.bak-<timestamp>`.

## What goes where

| Repo file                     | Live location                                    | How |
|-------------------------------|--------------------------------------------------|-----|
| `home/wezterm/`               | `~/.config/wezterm`                              | junction |
| `home/nvim/`                  | `%LOCALAPPDATA%\nvim`                            | junction |
| `home/herdr/`                 | `%APPDATA%\herdr`                                | junction (runtime files git-ignored) |
| `home/agents/AGENTS.md`       | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md` | symlink, or hardlink without Developer Mode |
| `home/powershell/profile.ps1` | both `$PROFILE`s (5.1 and 7)                     | one-line stub that dot-sources it |
| `home/starship/starship.toml` | via `$env:STARSHIP_CONFIG`                       | env var |
| `home/claude/settings.json`   | `~/.claude/settings.json`                        | merged: only these keys are managed |

Claude Code rewrites `~/.claude/settings.json` itself (plugins, model, permissions),
so the repo owns only the keys in `home/claude/settings.json` (the status line) and
merges them in instead of replacing the file.

## Notes

- Enable **Developer Mode** (Settings > System > For developers) to get real file
  symlinks. Without it, AGENTS.md is hardlinked; a `git checkout` that rewrites it
  breaks the link, so re-run `install.ps1` afterwards.
- `windows-settings.ps1` hides desktop icons, auto-hides the taskbar, turns on dark
  mode, shows file extensions and sets fast key repeat. Edit its table to opt out.
- The `cc` and `co` functions skip agent permission prompts. Know what they do.
- First `nvim` launch clones lazy.nvim and plugins from GitHub (needs network once).
- herdr keys mirror tmux: prefix `Ctrl+b`, `"`/`%` to split, `h/j/k/l` to move.
