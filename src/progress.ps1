# Installer-only UI. Nothing in this file is loaded by the terminal profile.
function Initialize-Cmd3rProgress {
    param([int]$Steps = 11, [switch]$NoAnimation)
    $script:Cmd3rStepNumber = 0
    $script:Cmd3rStepTotal = $Steps
    $script:Cmd3rStepTimer = $null
    $script:Cmd3rAnimated = !$NoAnimation -and ![Console]::IsOutputRedirected
    if ($script:Cmd3rAnimated -and !('Cmd3r.CliSpinner' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Threading;
namespace Cmd3r {
 public static class CliSpinner {
  static readonly object Gate = new object();
  static Timer Clock; static bool Running; static int Frame; static int Width; static string Label;
  public static void Start(string label) {
   Stop(); lock(Gate) { Label=label; Frame=0; Width=0; Running=true; Clock=new Timer(Draw,null,0,90); }
  }
  static void Draw(object state) {
   lock(Gate) {
    if(!Running) return;
    string line="  "+"|/-\\"[Frame++ % 4]+" "+Label;
    try { int max=Console.WindowWidth-2; if(max>8 && line.Length>max) line=line.Substring(0,max); } catch {}
    Width=Math.Max(Width,line.Length); Console.Write("\r"+line.PadRight(Width));
   }
  }
  public static void Stop() {
   lock(Gate) { Running=false; if(Clock!=null) { Clock.Dispose(); Clock=null; } if(Width>0) Console.Write("\r"+new string(' ',Width)+"\r"); Width=0; }
  }
 }
}
'@
    }
    Write-Host ''
    Write-Host '  cmd3r' -ForegroundColor Cyan -NoNewline
    Write-Host '  /  your personal terminal' -ForegroundColor DarkGray
    Write-Host '  -----------------------------------------------' -ForegroundColor DarkGray
    Write-Host ''
}

function Start-Cmd3rStep {
    param([string]$Label)
    $script:Cmd3rStepNumber++
    $script:Cmd3rStepLabel = $Label
    $script:Cmd3rStepTimer = [Diagnostics.Stopwatch]::StartNew()
    $prefix = '[{0:00}/{1:00}]' -f $script:Cmd3rStepNumber,$script:Cmd3rStepTotal
    if ($script:Cmd3rAnimated) { [Cmd3r.CliSpinner]::Start("$prefix $Label") }
    else { Write-Host "  > $prefix $Label" -ForegroundColor Cyan }
}

function Stop-Cmd3rStep {
    param([switch]$Failed, [switch]$Pending, [string]$Message)
    if ($script:Cmd3rAnimated -and ('Cmd3r.CliSpinner' -as [type])) { [Cmd3r.CliSpinner]::Stop() }
    if (!$script:Cmd3rStepTimer) { return }
    $script:Cmd3rStepTimer.Stop()
    $elapsed = '{0:0.0}s' -f $script:Cmd3rStepTimer.Elapsed.TotalSeconds
    $prefix = '[{0:00}/{1:00}]' -f $script:Cmd3rStepNumber,$script:Cmd3rStepTotal
    if ($Pending) { Write-Host "  ! $prefix $script:Cmd3rStepLabel  ($elapsed)" -ForegroundColor Yellow }
    elseif ($Failed) { Write-Host "  x $prefix $script:Cmd3rStepLabel  ($elapsed)" -ForegroundColor Red }
    else { Write-Host "  + $prefix $script:Cmd3rStepLabel  ($elapsed)" -ForegroundColor Green }
    if ($Message) { Write-Host "      $Message" -ForegroundColor $(if ($Failed) {'Red'} else {'DarkGray'}) }
    $script:Cmd3rStepTimer = $null
}

function Show-Cmd3rFailure {
    param([Management.Automation.ErrorRecord]$Failure, [string]$CacheRoot)
    $pending = $Failure.Exception.Data['Cmd3rStatus'] -eq 'TerminalUpdatePending'
    Stop-Cmd3rStep -Failed:(!$pending) -Pending:$pending
    $log = $null
    try {
        $directory = Join-Path $CacheRoot 'logs'
        [IO.Directory]::CreateDirectory($directory) | Out-Null
        $log = Join-Path $directory ('setup-{0}-{1}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),[guid]::NewGuid().ToString('N').Substring(0,8))
        $detail = "Time: $(Get-Date -Format o)`r`nStep: $script:Cmd3rStepNumber / $script:Cmd3rStepTotal - $script:Cmd3rStepLabel`r`n"
        $detail += ($Failure | Format-List * -Force | Out-String)
        $detail += "`r`nException: $($Failure.Exception.ToString())`r`nStack: $($Failure.ScriptStackTrace)"
        [IO.File]::WriteAllText($log,$detail,[Text.UTF8Encoding]::new($false))
    } catch { $log = $null }
    if ($pending) {
        Write-Host '  Setup paused: Windows Terminal update is pending.' -ForegroundColor Yellow
        Write-Host '  Close all Windows Terminal windows.'
        Write-Host '  Open Command Prompt or Windows PowerShell from Start.'
        Write-Host '  Rerun Install.cmd with the same setup options.'
        Write-Host '  Other tools and configuration have not been changed.' -ForegroundColor DarkGray
        Write-Host '  Completed platform installation and verified downloads are reused.' -ForegroundColor DarkGray
    } else {
        Write-Host '  Setup stopped:' -ForegroundColor Red
        Write-Host "  $($Failure.Exception.Message)" -ForegroundColor Red
        Write-Host '  Fix the reported problem and rerun the same setup command.'
        Write-Host '  Completed changes remain; existing backups are kept. No automatic rollback.' -ForegroundColor DarkGray
    }
    if ($log) { Write-Host "  Details: $log" -ForegroundColor DarkGray }
    else { Write-Host '  Diagnostic log could not be saved.' -ForegroundColor Yellow }
    if ($pending) { return 2 }
    return 1
}

function Write-Cmd3rNote {
    param([string]$Message)
    # Stop redraw briefly to avoid mixing download/tool output with the spinner.
    if ($script:Cmd3rAnimated) { [Cmd3r.CliSpinner]::Stop() }
    Write-Host "      $Message" -ForegroundColor DarkGray
    if ($script:Cmd3rAnimated -and $script:Cmd3rStepTimer) {
        [Cmd3r.CliSpinner]::Start(('[{0:00}/{1:00}] {2}' -f $script:Cmd3rStepNumber,$script:Cmd3rStepTotal,$script:Cmd3rStepLabel))
    }
}
