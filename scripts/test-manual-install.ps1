<#
.SYNOPSIS
    Runs install.cmd and uninstall.cmd of the manual-install archive against a temporary %APPDATA% (Windows only, issue #3).

.DESCRIPTION
    Checks that install.cmd works without administrator rights, puts the bundle exactly into
    %APPDATA%\Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle and nowhere else, replaces an older installation
    (no stale files stay), and that uninstall.cmd removes the bundle. The temporary profile path contains spaces and
    parentheses, like "C:\Users\Иван (work)\AppData\Roaming".
#>
param(
    [string]$Version,
    [string]$ReleaseRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not $IsWindows) {
    Write-Host 'install.cmd and uninstall.cmd need cmd.exe; skipped on this OS.'
    return
}

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'release-common.ps1')

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-ProjectVersion -Root $root
}
if ([string]::IsNullOrWhiteSpace($ReleaseRoot)) {
    $ReleaseRoot = [System.IO.Path]::Combine($root, 'release', "v$Version")
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("velec install test {0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
$archiveFolder = Join-Path $work 'Загрузки (zip)'
$appData = [System.IO.Path]::Combine($work, 'Иван (work)', 'AppData', 'Roaming')
$bundle = Join-Path $appData 'Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle'
$originalAppData = $env:APPDATA

function Invoke-Cmd {
    param([Parameter(Mandatory = $true)][string]$Script)

    # cmd /c strips the outer quotes: ""C:\a b\install.cmd" /quiet".
    $process = Start-Process -FilePath $env:ComSpec -ArgumentList "/d /c `"`"$Script`" /quiet`"" -NoNewWindow -Wait -PassThru
    return $process.ExitCode
}

function Get-RelativeFiles([string]$Folder) {
    if (-not (Test-Path -LiteralPath $Folder)) {
        return @()
    }
    $prefix = (Resolve-Path -LiteralPath $Folder).Path.TrimEnd('\') + '\'
    return @(Get-ChildItem -LiteralPath $Folder -Recurse -File | ForEach-Object { $_.FullName.Substring($prefix.Length) } | Sort-Object)
}

try {
    New-Item -ItemType Directory -Force -Path $archiveFolder, $appData | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $ReleaseRoot "$ProductName-manual-install-v$Version.zip"), $archiveFolder)
    $expected = Get-RelativeFiles (Join-Path $archiveFolder ($BundleRelativePath -replace '/', '\'))
    $env:APPDATA = $appData

    # 1. Fresh installation.
    $exitCode = Invoke-Cmd (Join-Path $archiveFolder 'install.cmd')
    if ($exitCode -ne 0) { throw "install.cmd exited with $exitCode" }
    $installed = Get-RelativeFiles $bundle
    if (($installed -join '|') -ne ($expected -join '|')) {
        throw "Installed bundle differs from the archive.`nExpected: $($expected -join ', ')`nInstalled: $($installed -join ', ')"
    }
    $outside = @(Get-RelativeFiles $appData | Where-Object { -not $_.StartsWith('Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle\') })
    if ($outside.Count -gt 0) { throw "install.cmd wrote files outside the bundle: $($outside -join ', ')" }
    Write-Host "install.cmd: $($installed.Count) files installed into $bundle"

    # 2. Upgrade over an older installation: files of the old version must not stay.
    $stale = Join-Path $bundle 'Contents\AutoCAD2020-2024\Stale.Old.dll'
    Set-Content -LiteralPath $stale -Value 'old'
    $exitCode = Invoke-Cmd (Join-Path $archiveFolder 'install.cmd')
    if ($exitCode -ne 0) { throw "install.cmd (upgrade) exited with $exitCode" }
    if (Test-Path -LiteralPath $stale) { throw 'install.cmd kept a file of the previous installation' }
    if (((Get-RelativeFiles $bundle) -join '|') -ne ($expected -join '|')) { throw 'Bundle differs from the archive after the upgrade' }
    Write-Host 'install.cmd: upgrade replaced the previous installation'

    # 3. Uninstallation, twice (the second run finds nothing and still succeeds).
    foreach ($run in 1, 2) {
        $exitCode = Invoke-Cmd (Join-Path $archiveFolder 'uninstall.cmd')
        if ($exitCode -ne 0) { throw "uninstall.cmd (run $run) exited with $exitCode" }
        if (Test-Path -LiteralPath $bundle) { throw "uninstall.cmd (run $run) did not remove $bundle" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $appData 'Autodesk\ApplicationPlugins'))) {
        throw 'uninstall.cmd must remove only the bundle, not ApplicationPlugins shared with other plugins'
    }
    Write-Host 'uninstall.cmd: bundle removed'

    # 4. install.cmd started outside the unpacked archive fails with a non-zero exit code.
    $lonely = Join-Path $work 'lonely'
    New-Item -ItemType Directory -Path $lonely | Out-Null
    Copy-Item -LiteralPath (Join-Path $archiveFolder 'install.cmd') -Destination $lonely
    $exitCode = Invoke-Cmd (Join-Path $lonely 'install.cmd')
    if ($exitCode -eq 0) { throw 'install.cmd without the AppData folder must fail' }
    if (Test-Path -LiteralPath $bundle) { throw 'install.cmd without the AppData folder must not install anything' }
    Write-Host 'install.cmd: incomplete archive is rejected'
}
finally {
    $env:APPDATA = $originalAppData
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
}

Write-Host 'Manual installation scripts work.' -ForegroundColor Green
