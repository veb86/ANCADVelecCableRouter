<#
.SYNOPSIS
    Builds the AutoCAD plugin and packs the release archives (issue #3).

.DESCRIPTION
    Creates release/v<Version>/ with:
      ANCADVelecCableRouter-manual-install-v<Version>.zip  per-user installation without an installer:
          AppData/Roaming/Autodesk/ApplicationPlugins/ANCADVelecCableRouter.bundle (autoloaded by AutoCAD 2020-2025),
          install.cmd, uninstall.cmd, INSTALL.md;
      ANCADVelecCableRouter-AutoCAD2020-2024-v<Version>.zip  DLLs for NETLOAD in AutoCAD 2020-2024 (net48);
      ANCADVelecCableRouter-AutoCAD2025-v<Version>.zip       DLLs for NETLOAD in AutoCAD 2025 (net8.0-windows);
      release-manifest.txt                                   SHA256 of the archives.
    Runs on Windows and Linux (PowerShell 7+).

.EXAMPLE
    ./scripts/package-release.ps1
    ./scripts/package-release.ps1 -NoBuild -Force
#>
param(
    # Defaults to <Version> from Directory.Build.props.
    [string]$Version,
    # Use the existing src/VelecCableRouter.AutoCAD/bin/<Configuration> output instead of building it.
    [switch]$NoBuild,
    # Replace release/v<Version> if it already exists.
    [switch]$Force,
    [string]$Configuration = 'Release',
    [string]$ReleaseBase
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'release-common.ps1')

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-ProjectVersion -Root $root
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Version must look like 1.2.3, got '$Version'."
}
if ([string]::IsNullOrWhiteSpace($ReleaseBase)) {
    $ReleaseBase = Join-Path $root 'release'
}

$releaseRoot = Join-Path $ReleaseBase "v$Version"
$stagingRoot = Join-Path $ReleaseBase ("._v{0}-{1}" -f $Version, $PID)
$project = [System.IO.Path]::Combine($root, 'src', 'VelecCableRouter.AutoCAD', 'VelecCableRouter.AutoCAD.csproj')
$buildOutput = [System.IO.Path]::Combine($root, 'src', 'VelecCableRouter.AutoCAD', 'bin', $Configuration)

if (Test-Path -LiteralPath $releaseRoot) {
    if (-not $Force) {
        throw "Release already exists: $releaseRoot (use -Force to replace it)"
    }
    Remove-Item -LiteralPath $releaseRoot -Recurse -Force
}

if (-not $NoBuild) {
    # The default AutoCadNet48ApiVersion (23.1.0 = AutoCAD 2020) keeps the net48 build loadable in AutoCAD 2020-2024.
    & dotnet build $project -c $Configuration "-p:Version=$Version"
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed with exit code $LASTEXITCODE"
    }
}

function Copy-PluginFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    foreach ($file in $PluginFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $Source $file))) {
            throw "Build output is incomplete, '$file' was not found in $Source"
        }
    }

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    # Debug symbols and XML documentation are not needed by AutoCAD; AutoCAD SDK assemblies are never copied
    # to the build output (ExcludeAssets="runtime"), test-release-package.ps1 double-checks that.
    Get-ChildItem -LiteralPath $Source -File |
        Where-Object { @('.pdb', '.xml') -notcontains $_.Extension } |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $Destination }
}

function New-ZipFromDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )

    # ZipFile (unlike Compress-Archive in Windows PowerShell) always writes '/' separators.
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $Directory, $ArchivePath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
}

New-Item -ItemType Directory -Force -Path $ReleaseBase | Out-Null
New-Item -ItemType Directory -Path $stagingRoot | Out-Null

try {
    $packages = Join-Path $stagingRoot '.packages'

    # Archives with plain DLLs for NETLOAD.
    foreach ($target in $Targets) {
        $folder = Join-Path $packages $target.Folder
        Copy-PluginFiles -Source (Join-Path $buildOutput $target.Framework) -Destination $folder
        New-ZipFromDirectory -Directory $folder -ArchivePath (Join-Path $stagingRoot "$ProductName-$($target.Folder)-v$Version.zip")
    }

    # Manual installation: the archive mirrors %USERPROFILE%, everything goes to %APPDATA% of the current user.
    $manual = Join-Path $packages 'manual-install'
    $bundle = Join-Path $manual ($BundleRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    foreach ($target in $Targets) {
        Copy-PluginFiles -Source (Join-Path $buildOutput $target.Framework) -Destination ([System.IO.Path]::Combine($bundle, 'Contents', $target.Folder))
    }
    Copy-Item -LiteralPath ([System.IO.Path]::Combine($root, 'installer_acad', 'PackageContents.xml')) -Destination $bundle
    foreach ($file in @('INSTALL.md', 'install.cmd', 'uninstall.cmd')) {
        Copy-Item -LiteralPath ([System.IO.Path]::Combine($root, 'installer_manual', $file)) -Destination $manual
    }
    New-ZipFromDirectory -Directory $manual -ArchivePath (Join-Path $stagingRoot "$ProductName-manual-install-v$Version.zip")

    Remove-Item -LiteralPath $packages -Recurse -Force

    $manifest = @(
        "$ProductName release v$Version",
        "Commit=$(if ($env:GITHUB_SHA) { $env:GITHUB_SHA } else { 'local' })",
        '',
        'Archives (SHA256):'
    )
    Get-ChildItem -LiteralPath $stagingRoot -File -Filter '*.zip' | Sort-Object Name | ForEach-Object {
        $manifest += "$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)  $($_.Name)"
    }
    [System.IO.File]::WriteAllLines((Join-Path $stagingRoot 'release-manifest.txt'), $manifest, [System.Text.UTF8Encoding]::new($false))

    Move-Item -LiteralPath $stagingRoot -Destination $releaseRoot
    Write-Host "Release archives created: $releaseRoot"
    Get-ChildItem -LiteralPath $releaseRoot -File | ForEach-Object { Write-Host "  $($_.Name)" }
}
catch {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
    throw
}
