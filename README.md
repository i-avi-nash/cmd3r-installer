# cmd3r

A reproducible Windows Terminal and PowerShell setup: a framed prompt, readable light and dark themes, saved history, fuzzy search, and useful command-line tools. Installation starts with one command and needs no GitHub account.

## Install from any Windows PC

Run this in **PowerShell or Command Prompt** on 64-bit Windows 10 (build 19041 or newer) or Windows 11:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-RestMethod 'https://raw.githubusercontent.com/i-avi-nash/cmd3r-installer/main/bootstrap.ps1' | Invoke-Expression"
```

The command fetches the [public installer snapshot](https://github.com/i-avi-nash/cmd3r-installer). It does not need GitHub CLI or GitHub credentials. Review the bootstrap at that URL before running it if you prefer. Internet access is needed for this path; see [Offline installation](#offline-installation) for an air-gapped PC.

Setup first downloads and verifies the latest stable PowerShell MSI and Windows Terminal offline kit, then installs the prompt, tools, fonts, and profiles. PowerShell may request administrator approval. If Git for Windows is absent, setup uses `winget` to install it; App Installer must be available for that case. The setup asks separately whether to add NVM for Windows and npkill. Press **Enter** to skip either.

Open a new Windows Terminal tab after setup. The default entry is **PowerShell (cmd3r)**, using the installed PowerShell 7. The generated **PowerShell** entry also points to that executable and receives the theme. Your existing explicit font choices are preserved.

## What you get

| Area | Behavior |
| --- | --- |
| Prompt | Oh My Posh with a thin framed header, current folder link, Git branch and local change counts, clock, and a simple `>` input marker. |
| Themes | Warm light and near-black dark modes with burgundy accents: `cmd3r theme light` or `cmd3r theme dark`. |
| Font | Geist Mono Nerd Font is installed and used as the initial profile choice. Change the font in **Windows Terminal → Settings → PowerShell → Appearance**; updates preserve your choice. |
| History | Saved commands, suggestions while typing, list view, and fuzzy search. |
| Tools | `oh-my-posh`, `fzf`, `rg`, `fd`, `bat`, `zoxide`, `lazygit`, and `jq`. |
| Optional Node tools | A verified, cached NVM for Windows installer and an opt-in npkill installation. |

The folder path supports **Ctrl+click** to open Explorer. The Git section shows `+` added, `~` modified, `-` deleted, `?` untracked, and `!` conflicted counts; staged files and stashes have separate indicators. Cherry-pick, merge, rebase, and revert states appear when active. Git status is local; rendering the prompt does not fetch from the network.

The border uses terminal box-drawing characters and compact `+` junctions. Windows Terminal scales stroke thickness with font size; the artwork cannot use an independent font or fixed one-pixel stroke.

## Shortcuts and commands

| Key or command | Action |
| --- | --- |
| `Ctrl+Shift+B` | Copy the current Git branch name. Outside a repository or on detached HEAD, leave the clipboard unchanged. |
| `Ctrl+R` | Fuzzy search saved commands and insert the selection. |
| `Alt+F` | Pick a file and insert its quoted path. |
| `F2` | Switch between inline and list history suggestions. |
| `Tab` | Completion menu. |
| `cmd3r theme light` / `cmd3r theme dark` | Save and apply the selected theme. |
| `cmd3r doctor` | Check the installed tools, prompt, font, and Terminal settings. |
| `cmd3r update` | Download the current public installer snapshot and rerun setup. |
| `terminal-help` or `cmd3r help` | Show shortcuts and helper commands. |

The shell also provides `z`, `zi`, `ff`, `cdf`, `gs`, `gl`, `gd`, `lg`, `ll`, `..`, and `...`. Search tools run only when used; profile startup does not perform downloads or update checks.

## Optional Node tools

**NVM for Windows** manages multiple Node.js versions. If it is already installed, setup keeps the existing installation and versions. A new installation uses the official architecture-specific setup EXE, checked against the release SHA-256 digest. Its wizard lets you review what happens to an existing Node installation. Installing NVM alone does **not** install or activate Node.js.

**npkill** helps you review `node_modules` folders and choose which to remove. Setup installs the command in cmd3r's own tool directory and never runs a cleanup or deletes a project folder. It requires active Node.js and npm. If you install NVM on a new PC, activate Node first and select npkill on a later setup run.

For unattended or repeat runs, choose explicitly:

```cmd
Install.cmd -NonInteractive -NvmWindows No -Npkill Yes
```

`-NvmWindows` and `-Npkill` accept `Ask`, `Yes`, or `No`. Unanswered choices are skipped in noninteractive runs. A new NVM installation runs silently only if no existing Node is detected; a migration requires an interactive run.

## Install from a local checkout

In Command Prompt, from the folder containing the installer:

```cmd
Install.cmd
```

Or in PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

`Install.cmd` launches the built-in Windows PowerShell with its own modules, so PowerShell 7 need not exist yet. Run it from Command Prompt or Windows PowerShell opened outside Windows Terminal when updating Terminal; open Terminal windows can delay its registration.

## Offline installation

On a connected PC, stage downloads with the same CPU architecture as the target PC:

```cmd
Install.cmd -StageOnly -CacheRoot D:\cmd3r-cache -NvmWindows Yes -Npkill No
```

Copy the source checkout and the complete cache to the target PC, then run:

```cmd
Install.cmd -Offline -CacheRoot D:\cmd3r-cache -NvmWindows Yes -Npkill No
```

Staging verifies the installers and archives without installing applications or changing Windows Terminal settings. Offline mode uses the cached release versions and refuses missing or invalid files. Git must already be installed offline. Prepare a separate cache for x64 and ARM64. For offline npkill, stage with `-Npkill Yes` on a PC with active Node/npm and include npm's cache. NVM's installer cache does not include Node.js runtime archives.

## Troubleshooting and recovery

The installer reports each step and saves detailed logs in `%LOCALAPPDATA%\cmd3r\downloads\logs`. It returns **0** on success, **1** on failure, and **2** when a Windows Terminal update is pending. If Terminal is open and registration is delayed, close every Terminal window and rerun from Command Prompt or Windows PowerShell. Verified downloads are reused.

Before changing settings, setup saves backups under `%LOCALAPPDATA%\Programs\cmd3r\backups`. A failed run leaves completed changes in place; the log names the step to fix before rerunning. The doctor report is saved as `verification.log` in the download cache. Existing unrelated Terminal profiles and custom PowerShell profile content are preserved. Managed execution-policy restrictions may require an administrator.

Your installation is under `%LOCALAPPDATA%\Programs\cmd3r`. To apply theme source changes without reinstalling applications:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\apply-theme.ps1 -Mode dark
```

## Development and verification

The development repository is private; the [public installer repository](https://github.com/i-avi-nash/cmd3r-installer) contains a clean source snapshot without private commit history. **Publishing a new development commit does not update the public snapshot automatically.** Refresh the public snapshot before expecting `cmd3r update` or the one-line command to use a new change.

Customization lives in `src/preferences.json`, `src/scheme.json`, `src/scheme-light.json`, the two `src/workspace-*.omp.json` themes, and `src/profile.ps1`. Productivity tools and the font are pinned with SHA-256 hashes in `packages.lock.json`; stable PowerShell and Terminal release metadata is cached at install time. The PowerShell MSI's Microsoft signature and all downloaded archive hashes are checked.

Run checks from a source checkout after installing the test dependencies:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Setup.ps1
pwsh -NoProfile -File .\tests\Test-Themes.ps1
pwsh -NoProfile -File .\tests\Test-GitPrompt.ps1
pwsh -NoProfile -File .\tests\Test-CopyBranch.ps1
pwsh -NoProfile -File .\tests\Test-OptionalTools.ps1
pwsh -NoProfile -File .\tests\Test-InstallerHost.ps1
```

`-StageOnly` exercises the download and extraction path without applying system configuration. The example workflow in `tests/ci-workflow.yml.example` can be enabled in a repository with GitHub Actions.
