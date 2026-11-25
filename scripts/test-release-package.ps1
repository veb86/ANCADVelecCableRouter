<#
.SYNOPSIS
    Verifies the archives produced by scripts/package-release.ps1 (issue #3).

.DESCRIPTION
    Lists every problem and exits with an error if:
      * an archive, a required file or the SHA256 manifest is missing or wrong;
      * the manual-install archive would put files anywhere but %APPDATA%\Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle;
      * debug symbols or AutoCAD SDK assemblies are packaged;
      * PackageContents.xml does not match <Version>, the packaged DLLs, the AutoCAD series 2020-2024 (R23.1-R24.3)
        and 2025 (R25.0), or the [CommandMethod] names of the plugin;
      * a packaged plugin DLL has the wrong assembly version, target runtime or references an AutoCAD API newer than
        the oldest AutoCAD it is declared for (it would not load there).
    Runs on Windows and Linux (PowerShell 7+).
#>
param(
    [string]$Version,
    [string]$ReleaseRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'release-common.ps1')

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-ProjectVersion -Root $root
}
if ([string]::IsNullOrWhiteSpace($ReleaseRoot)) {
    $ReleaseRoot = [System.IO.Path]::Combine($root, 'release', "v$Version")
}
if (-not (Test-Path -LiteralPath $ReleaseRoot)) {
    throw "Release folder was not found: $ReleaseRoot (run scripts/package-release.ps1 first)"
}

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure([string]$Message) { $failures.Add($Message) }

$manualName = "$ProductName-manual-install-v$Version.zip"
$extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("velec-release-test-{0}" -f [guid]::NewGuid().ToString('N'))

function Expand-ReleaseArchive {
    param([Parameter(Mandatory = $true)][string]$ArchiveName)

    $path = Join-Path $ReleaseRoot $ArchiveName
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Failure "Archive is missing: $ArchiveName"
        return $null
    }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
    try {
        $entries = @($zip.Entries | ForEach-Object { $_.FullName })
    }
    finally {
        $zip.Dispose()
    }

    foreach ($entry in $entries) {
        if ($entry.Contains('\')) {
            Add-Failure "${ArchiveName}: entry uses '\' instead of '/': '$entry'"
        }
        if ($entry -match '\.pdb$') {
            Add-Failure "${ArchiveName}: debug symbols must not be packaged: '$entry'"
        }
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($entry)
        if ($entry -match '\.dll$' -and ($AutoCadSdkAssemblies -contains $baseName -or $baseName -like 'Autodesk.*')) {
            Add-Failure "${ArchiveName}: AutoCAD SDK assembly must not be packaged: '$entry'"
        }
    }

    $destination = Join-Path $extractRoot ([System.IO.Path]::GetFileNameWithoutExtension($ArchiveName))
    [System.IO.Compression.ZipFile]::ExtractToDirectory($path, $destination)
    Write-Host "${ArchiveName}: $($entries.Count) entries"
    return [pscustomobject]@{ Name = $ArchiveName; Entries = $entries; Folder = $destination }
}

function Assert-Entries {
    param($Archive, [string[]]$Required)

    foreach ($entry in $Required) {
        if ($Archive.Entries -notcontains $entry) {
            Add-Failure "$($Archive.Name): missing '$entry'"
        }
    }
}

function Get-AssemblyInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $pe = [System.Reflection.PortableExecutable.PEReader]::new($stream)
        $reader = [System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($pe)
        $definition = $reader.GetAssemblyDefinition()
        $references = @{}
        foreach ($handle in $reader.AssemblyReferences) {
            $reference = $reader.GetAssemblyReference($handle)
            $references[$reader.GetString($reference.Name)] = $reference.Version
        }
        return [pscustomobject]@{
            Name       = $reader.GetString($definition.Name)
            Version    = $definition.Version
            References = $references
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-FileSha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

try {
    $expectedVersion = [version]"$Version.0"

    # 1. Manual installation archive: only the bundle under %APPDATA% plus the instructions and scripts.
    $manual = Expand-ReleaseArchive -ArchiveName $manualName
    if ($manual) {
        $required = @('INSTALL.md', 'install.cmd', 'uninstall.cmd', "$BundleRelativePath/PackageContents.xml")
        foreach ($target in $Targets) {
            $required += $PluginFiles | ForEach-Object { "$BundleRelativePath/Contents/$($target.Folder)/$_" }
        }
        Assert-Entries -Archive $manual -Required $required

        foreach ($entry in $manual.Entries) {
            if (@('INSTALL.md', 'install.cmd', 'uninstall.cmd') -notcontains $entry -and
                -not $entry.StartsWith("$BundleRelativePath/", [System.StringComparison]::Ordinal) -and
                -not "$BundleRelativePath/".StartsWith($entry, [System.StringComparison]::Ordinal)) {
                Add-Failure "${manualName}: '$entry' would be installed outside ANCADVelecCableRouter.bundle"
            }
        }

        foreach ($script in @('install.cmd', 'uninstall.cmd')) {
            $path = Join-Path $manual.Folder $script
            if ((Test-Path -LiteralPath $path) -and ([System.IO.File]::ReadAllText($path) -match '(?<!\r)\n')) {
                Add-Failure "${manualName}: $script must use CRLF line endings (see .gitattributes)"
            }
        }
    }

    # 2. PackageContents.xml: version, packaged modules, AutoCAD series and commands.
    $bundleFolder = if ($manual) { Join-Path $manual.Folder ($BundleRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar) } else { $null }
    $packageContentsPath = if ($bundleFolder) { Join-Path $bundleFolder 'PackageContents.xml' } else { $null }
    if ($packageContentsPath -and (Test-Path -LiteralPath $packageContentsPath)) {
        [xml]$packageContents = Get-Content -LiteralPath $packageContentsPath -Raw -Encoding UTF8
        $package = $packageContents.ApplicationPackage
        if ($package.AppVersion -ne $Version) {
            Add-Failure "PackageContents.xml: AppVersion '$($package.AppVersion)' differs from <Version> $Version in Directory.Build.props"
        }
        if ($package.Name -ne $ProductName -or $package.AutodeskProduct -ne 'AutoCAD') {
            Add-Failure "PackageContents.xml: expected Name='$ProductName' AutodeskProduct='AutoCAD'"
        }

        $source = Get-Content -LiteralPath ([System.IO.Path]::Combine($root, 'src', 'VelecCableRouter.AutoCAD', 'CableCommands.cs')) -Raw
        $sourceCommands = @([regex]::Matches($source, '\[CommandMethod\("([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
        if ($sourceCommands.Count -eq 0) {
            Add-Failure 'No [CommandMethod] was found in CableCommands.cs'
        }

        $components = @($packageContents.SelectNodes('/ApplicationPackage/Components/ComponentEntry'))
        if ($components.Count -ne $Targets.Count) {
            Add-Failure "PackageContents.xml: expected $($Targets.Count) ComponentEntry elements, found $($components.Count)"
        }
        foreach ($component in $components) {
            $module = "$BundleRelativePath/" + $component.ModuleName.TrimStart('.', '/')
            if ($manual.Entries -notcontains $module) {
                Add-Failure "PackageContents.xml references '$($component.ModuleName)', but '$module' is not packaged"
            }
        }

        foreach ($target in $Targets) {
            $moduleName = "./Contents/$($target.Folder)/VelecCableRouter.AutoCAD.dll"
            $component = @($components | Where-Object { $_.ModuleName -eq $moduleName })
            if ($component.Count -ne 1) {
                Add-Failure "PackageContents.xml: exactly one ComponentEntry must load '$moduleName'"
                continue
            }
            $component = $component[0]
            $runtime = $component.RuntimeRequirements
            if ($component.AppType -ne '.Net' -or $component.LoadOnAutoCADStartup -ne 'True') {
                Add-Failure "PackageContents.xml: '$moduleName' must have AppType='.Net' and LoadOnAutoCADStartup='True'"
            }
            if ($runtime.OS -ne 'Win64' -or $runtime.SeriesMin -ne $target.SeriesMin -or $runtime.SeriesMax -ne $target.SeriesMax) {
                Add-Failure "PackageContents.xml: '$moduleName' must declare OS=Win64 SeriesMin=$($target.SeriesMin) SeriesMax=$($target.SeriesMax), found OS=$($runtime.OS) SeriesMin=$($runtime.SeriesMin) SeriesMax=$($runtime.SeriesMax)"
            }
            $commands = @($component.SelectNodes('Commands/Command') | ForEach-Object { $_.Global } | Sort-Object)
            if (($commands -join ',') -ne ($sourceCommands -join ',')) {
                Add-Failure "PackageContents.xml: commands of '$moduleName' ($($commands -join ', ')) differ from [CommandMethod] in CableCommands.cs ($($sourceCommands -join ', '))"
            }
        }
    }

    # 3. NETLOAD archives and the plugin assemblies themselves.
    foreach ($target in $Targets) {
        $archive = Expand-ReleaseArchive -ArchiveName "$ProductName-$($target.Folder)-v$Version.zip"
        if (-not $archive) {
            continue
        }
        Assert-Entries -Archive $archive -Required $PluginFiles

        foreach ($file in $PluginFiles) {
            $plain = Join-Path $archive.Folder $file
            $bundled = if ($bundleFolder) { [System.IO.Path]::Combine($bundleFolder, 'Contents', $target.Folder, $file) } else { $null }
            if (-not (Test-Path -LiteralPath $plain)) {
                continue
            }
            if ($bundled -and (Test-Path -LiteralPath $bundled) -and (Get-FileSha256 $plain) -ne (Get-FileSha256 $bundled)) {
                Add-Failure "$($target.Folder)/${file}: the bundle and the NETLOAD archive contain different builds"
            }

            $info = Get-AssemblyInfo -Path $plain
            if ($info.Version -ne $expectedVersion) {
                Add-Failure "$($target.Folder)/${file}: assembly version $($info.Version), expected $expectedVersion"
            }
            if ($file -eq 'VelecCableRouter.AutoCAD.dll') {
                if (-not $info.References.ContainsKey($target.CoreLibrary)) {
                    Add-Failure "$($target.Folder)/${file}: must target $($target.Framework) (reference to $($target.CoreLibrary) not found)"
                }
                $acadReferences = @($info.References.Keys | Where-Object { @('acdbmgd', 'acmgd', 'accoremgd') -contains $_.ToLowerInvariant() })
                if ($acadReferences.Count -eq 0) {
                    Add-Failure "$($target.Folder)/${file}: no reference to the AutoCAD API was found"
                }
                foreach ($name in $acadReferences) {
                    $apiVersion = $info.References[$name]
                    if ([version]"$($apiVersion.Major).$($apiVersion.Minor)" -gt $target.MaxAcadApi) {
                        Add-Failure "$($target.Folder)/${file}: references $name $apiVersion, newer than $($target.MaxAcadApi) ($($target.SeriesMin)); it would not load in the oldest supported AutoCAD"
                    }
                }
                Write-Host "$($target.Folder)/${file}: $($info.Version), $($target.CoreLibrary), AutoCAD API $(@($acadReferences | ForEach-Object { "$_ $($info.References[$_])" }) -join ', ')"
            }
            elseif (-not $info.References.ContainsKey('netstandard')) {
                Add-Failure "$($target.Folder)/${file}: VelecCableRouter.Core must target netstandard2.0"
            }
        }
    }

    # 4. SHA256 manifest.
    $manifestPath = Join-Path $ReleaseRoot 'release-manifest.txt'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Add-Failure 'release-manifest.txt is missing'
    }
    else {
        $lines = @(Get-Content -LiteralPath $manifestPath | Where-Object { $_ -match '^[0-9A-F]{64}  ' })
        $zips = @(Get-ChildItem -LiteralPath $ReleaseRoot -File -Filter '*.zip')
        if ($lines.Count -ne $zips.Count -or $zips.Count -ne (1 + $Targets.Count)) {
            Add-Failure "release-manifest.txt lists $($lines.Count) archives, the release folder has $($zips.Count), expected $(1 + $Targets.Count)"
        }
        foreach ($zip in $zips) {
            if ($lines -notcontains "$(Get-FileSha256 $zip.FullName)  $($zip.Name)") {
                Add-Failure "release-manifest.txt: wrong or missing SHA256 of $($zip.Name)"
            }
        }
    }
}
finally {
    if (Test-Path -LiteralPath $extractRoot) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
    throw "$($failures.Count) release package check(s) failed."
}

Write-Host "Release package v$Version is valid." -ForegroundColor Green
