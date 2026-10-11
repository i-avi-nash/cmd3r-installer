# cmd3r

My personal Windows Terminal and PowerShell setup, installed with one command.
The setup snapshot is public at `i-avi-nash/cmd3r-installer`; no GitHub sign-in
or GitHub CLI is needed. The development repository remains private.

## Install on a new PC

Run this one line in PowerShell or Command Prompt on 64-bit Windows 10/11:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-RestMethod 'https://raw.githubusercontent.com/i-avi-nash/cmd3r-installer/main/bootstrap.ps1' | Invoke-Expression"
```

Windows Package Manager (`winget`, from Microsoft's App Installer) is required
only when Git is missing. Windows 10 build 19041 or later is required.
PowerShell's MSI installs into Program Files and may show a Windows administrator
approval prompt. Terminal, fonts, and configuration are installed for your user.
Git installers may also request administrator approval.
PowerShell uses the native x64 or ARM64 MSI; Windows Terminal includes both
architectures. On Windows 11 ARM64, the smaller productivity tools use x64 emulation.

## Install from a clone

In a normal Command Prompt, run:

```cmd
cd /d D:\Avinash\cmder
Install.cmd
```

`Install.cmd` starts Windows PowerShell internally, so PowerShell 7 does not
need to be installed first. Arguments such as `-Offline`, `-CacheRoot`, and
`-NoAnimation` are forwarded, and the setup exit code is returned to CMD.
Use Command Prompt opened from Start when updating Terminal; a CMD tab inside
Windows Terminal still keeps Terminal running.

In PowerShell, run:

```powershell
.\Install.cmd
```

Or:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -SkipLaunch
```

## Optional Node tools

Setup asks separately whether to install **NVM for Windows** and **npkill**.
Press Enter to skip either. Existing NVM installations are preserved, including
their Node versions. NVM uses the official architecture-specific offline EXE,
verified against its GitHub release SHA256. Interactive installs open its wizard
so you can review migration choices for an existing Node installation.

npkill requires an active Node/npm runtime. It is installed in cmd3r's own npm
prefix and exposed as `npkill`; setup never launches its cleanup screen or deletes
project folders. Installing NVM alone does not install a Node runtime. If Node is
missing, activate a version with NVM before selecting npkill on a subsequent run.

Explicit choices also work from CMD and the downloaded bootstrap:

```cmd
Install.cmd -NvmWindows Yes -Npkill No
Install.cmd -NonInteractive -NvmWindows No -Npkill Yes
```

`-NonInteractive` skips unanswered optional choices. A new NVM installation runs
silently only when no existing Node is detected; migration requires an interactive
run. Cancellation/failure stops setup with a diagnostic log and a rerun instruction.

To prepare offline media, run online on a PC with Node/npm, then copy the source
folder and the entire cache to the offline PC of the same architecture:

```cmd
Install.cmd -StageOnly -CacheRoot D:\cmd3r-cache -NvmWindows Yes -Npkill Yes
Install.cmd -Offline -CacheRoot D:\cmd3r-cache -NvmWindows Yes -Npkill Yes
```

The cache includes the NVM release manifest/EXE and npkill's npm dependency cache.
Offline npkill uses npm's `--offline` mode and still needs an active Node runtime.
Node runtime archives are separate from the NVM installer and are not staged by
cmd3r. The web bootstrap itself needs internet; offline installation uses the clone.

Upstream: [NVM installers](https://docs.nvm-windows.com/install/installers/),
[npkill](https://github.com/voidcosmos/npkill).

## Included

- First, resolve the **latest stable** PowerShell and Windows Terminal releases.
- Download and verify Microsoft's signed **PowerShell MSI** and **Windows Terminal
  offline preinstall kit**, including Terminal's required runtime dependencies.
- Install/update and verify both platform versions **before** other tools,
  fonts, profiles, or Terminal settings are changed. Preview releases are excluded.
- PowerShell 7 becomes the Windows Terminal default as **PowerShell (cmd3r)**.
  Terminal's generated stable **PowerShell** entry also gets the theme and initial
  font settings, with its explicit size/font choices preserved. Both point to the
  installed stable executable. Preview and unrelated profiles remain separate.
- Geist Mono Nerd Font Mono, size **10**, **light**, line height **1.4** as the
  initial profile defaults. Existing and inherited font choices are preserved.
  Change your font in Windows Terminal Settings > PowerShell > Appearance.
  Built-in box-drawing strokes remain enabled; compact `+` markers use your text font.
- Workspace light/dark colors and a framed Oh My Posh prompt with fine rules,
  compact burgundy `+` intersections with small border gaps, an AM/PM clock, a simple `>` input marker, and a muted
  red error badge.
- UTF-8 console/native command encoding so the icons render correctly.
- History suggestions appear as a list as you type; **F2** toggles inline/list.
- Persistent history saves incrementally with up to **10,000** entries.
- **Ctrl+R** fuzzy-searches history; **Alt+F** picks a file with a preview.
- **Ctrl+Shift+B** copies the current Git branch name without changing your input.
  Outside a repository or on detached HEAD, the clipboard is left unchanged.
- `fzf`, `rg`, `fd`, `bat`, `zoxide`, `lazygit`, `jq`; existing Git is reused
  or Git for Windows is installed when absent.
- `z`, `zi`, `ff`, `cdf`, `gs`, `gl`, `gd`, `lg`, `ll`, `..`, and `...`.

Type `terminal-help` or `cmd3r help` in the installed terminal for shortcuts.

Switch modes with `cmd3r theme light` or `cmd3r theme dark`. The choice is saved
and reused on the next startup and on installer updates. This switches the prompt,
Windows Terminal background and UI, PSReadLine colors, fzf, and bat previews.
Other updated shell sessions follow the saved mode on their next prompt, keeping
text colors in sync with the shared Terminal background. After upgrading cmd3r,
open a new tab once to load the updated profile functions.
Geist Mono Nerd Font Mono remains at size 10, light weight, and 1.4 line height.
The divider adapts to window width and hides the right clock when space is
tight. The directory path is an OSC 8 folder hyperlink (Ctrl+click in Windows
Terminal). Labels such as WORKSPACE and GIT are omitted. Git shows the branch,
compact working-tree counts (`+` added, `~` modified, `-` deleted, `?` untracked,
`!` conflicted), a check-mark group for staged changes, an archive icon for stashes,
ahead/behind counts, stashes, and active cherry-pick, merge, rebase, or revert.
Counts are local status checks; no fetch or network request runs in the prompt.
Large repositories can take longer to scan than the earlier branch-only prompt.

Apply just the theme to an existing cmd3r installation from this clone:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\apply-theme.ps1 -Mode dark
```

## Animated setup

The installer shows eleven numbered steps with live spinner animation,
completed-step markers, elapsed times, and clear failures. Animation runs while
downloads, extraction, and installers are busy. It works before the Nerd Font is
installed. Redirected output uses readable plain logs instead of terminal redraws.
Use `-NoAnimation` to request the same plain output explicitly.

PowerShell is installed via `msiexec` with no automatic reboot. Terminal is
installed via `Add-AppxPackage` using the downloaded local bundle and dependencies,
without a Store or winget download during deployment. Open Terminal tabs are never
forcibly terminated: if Windows defers an update, setup stops before other tools
or configuration. Close Terminal and rerun `Install.cmd` from Windows PowerShell.

Expected pending updates display a yellow pause and recovery instructions, without
a PowerShell stack trace. Setup returns exit code **2** when Terminal registration
is pending, **1** for a failure, and **0** on success. Unexpected failures display
the reason once; technical exception details are saved under the cache's `logs`
directory. MSI and Terminal deployment also have their own logs in the cache.
The final doctor check saves stdout, stderr, and its exit code to
`verification.log` in the cache and includes the actual failed check in the error.
Rerunning reuses verified downloads and completed installations. Setup is not a
transaction: completed changes remain on a later failure, and configuration
backups are retained rather than automatically rolled back. Cached offline mode
fails clearly if a required download is missing or invalid.

## Cached offline installation

Run an online staging pass to download platform installers and all tool archives:

```powershell
.\install.ps1 -StageOnly -CacheRoot C:\cmd3r-cache
```

Copy the repository and cache directory to the target PC, then run:

```powershell
.\install.ps1 -Offline -CacheRoot C:\cmd3r-cache
```

Offline mode uses the last resolved stable platform versions in that cache,
validates the cached downloads, and makes no release/download requests. It cannot
discover a newer release without an online staging pass. Git must already be
installed in offline mode. A cache targets one CPU architecture; prepare separate
x64/ARM64 platform caches when necessary.

## Fast startup

No downloads, package-manager commands, update checks, or executable init
generators run in the PowerShell profile. Zoxide uses a generated local script.
The small prompt function calls Oh My Posh only to render the prompt. Git
shows its branch without scanning changed files. Search tools run on demand.
PSReadLine handles its own history loading; the fuzzy-search file read happens
only when you press Ctrl+R. Startup time depends on the PC and installed profiles.

## Repeat runs and updates

```powershell
cmd3r doctor
cmd3r update
```

`update` fetches the current `main` branch of the public installer snapshot, checks the
latest stable PowerShell/Terminal releases, and reapplies the setup. The nine
productivity/font packages still use pinned versions in `packages.lock.json`.
Existing verified downloads are reused. Change the lock file's URL/version/SHA256
to upgrade a productivity tool. Installed stable versions newer than an offline
cache are retained; preview installations do not satisfy the stable requirement.
Close programs using a tool if Windows reports a locked file.

The installation lives in `%LOCALAPPDATA%\Programs\cmd3r`. Downloads are cached
in `%LOCALAPPDATA%\cmd3r\downloads`. Backups are made under the installation's
`backups` directory before editing existing files. The setup preserves other
Windows Terminal profiles, actions, color schemes, and custom PowerShell profile
content. It replaces only its managed profile block and its own Terminal profile,
and applies the same appearance to the standard Windows PowerShell 5.1 profile.
JSON comments are normalized when saving Terminal settings; the original file
is retained in the backup. It adds its tool directories to the user PATH and
sets CurrentUser execution policy to RemoteSigned only when required for local
profiles. Managed execution-policy restrictions must be resolved by your admin.

To customize, edit `src/preferences.json`, `src/scheme.json`,
`src/scheme-light.json`, `src/workspace-dark.omp.json`,
`src/workspace-light.omp.json`, or `src/profile.ps1`, commit/push, then run `cmd3r update`.
The old Cmder installation in the original workspace is ignored by Git and is
not needed by this setup.

## Checks

```powershell
powershell.exe -NoProfile -File .\tests\Test-Setup.ps1
.\install.ps1 -StageOnly -InstallRoot "$env:TEMP\cmd3r-test"
```

`StageOnly` downloads/verifies the offline platform installers, extracts the
Terminal dependency kit and productivity archives, and prepares the local
profile without installing platform applications or changing Windows Terminal
settings, user profiles, fonts, execution policy, or user PATH. An optional GitHub Actions workflow is included
as `tests/ci-workflow.yml.example`. Copy it to `.github/workflows/test.yml` to
enable automatic compatibility checks and a fresh staging installation on a
Windows runner (publishing workflows requires GitHub's `workflow` permission).

Official productivity package sources are listed with SHA256 checksums in
`packages.lock.json`. Platform release metadata and published SHA256 digests are
resolved from Microsoft's GitHub repositories and saved in the cache as
`platform-releases.json`. The PowerShell MSI's Microsoft signature is checked;
Windows validates MSIX/AppX package signatures during Terminal deployment.
Downloaded tools retain their upstream licenses in the extracted package folders.
