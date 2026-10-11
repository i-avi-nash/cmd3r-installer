. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\progress.ps1')
Initialize-Cmd3rProgress -Steps 3
foreach ($label in 'Resolve stable releases','Download offline installers','Verify your terminal') {
    Start-Cmd3rStep $label
    Start-Sleep -Milliseconds 700
    Stop-Cmd3rStep
}
