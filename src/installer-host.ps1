# Load inbox modules for the running host, not another PowerShell edition found
# through inherited PSModulePath. Run before prompts, downloads or setup changes.
foreach ($moduleName in @('Microsoft.PowerShell.Utility','Microsoft.PowerShell.Management','Microsoft.PowerShell.Security','Microsoft.PowerShell.Archive')) {
    $manifest = [IO.Path]::Combine($PSHOME, "Modules\$moduleName\$moduleName.psd1")
    if (![IO.File]::Exists($manifest)) { throw "Required installer module is missing: $manifest. Repair this PowerShell installation." }
    Import-Module -Name $manifest -Global -Force -ErrorAction Stop
}
