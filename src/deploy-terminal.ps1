param([Parameter(Mandatory)][string]$Request, [Parameter(Mandatory)][string]$Log)
$ErrorActionPreference = 'Stop'
try {
    $data = Get-Content $Request -Raw | ConvertFrom-Json
    $arguments = @{Path=$data.bundle;ErrorAction='Stop'}
    if ($data.dependencies.Count) { $arguments.DependencyPath = [string[]]$data.dependencies }
    # Stage an update without forcibly terminating open tabs. The caller stops
    # if registration is deferred, so other setup does not run on an old version.
    $arguments.DeferRegistrationWhenPackagesAreInUse = $true
    Add-AppxPackage @arguments
    'Installed Windows Terminal from the local offline bundle.' | Set-Content $Log
    exit 0
} catch {
    $_ | Out-String | Set-Content $Log
    exit 1
}
