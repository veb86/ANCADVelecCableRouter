# Shared by package-release.ps1, test-release-package.ps1 and test-manual-install.ps1 (dot-sourced).

$ProductName = 'ANCADVelecCableRouter'
$BundleRelativePath = 'AppData/Roaming/Autodesk/ApplicationPlugins/ANCADVelecCableRouter.bundle'
$PluginFiles = @('VelecCableRouter.AutoCAD.dll', 'VelecCableRouter.Core.dll')

# Folder = Contents/<Folder> in the bundle and the suffix of the NETLOAD archive.
# MaxAcadApi = the newest AutoCAD API the build may reference, so that it still loads in the oldest version (SeriesMin).
$Targets = @(
    @{ Folder = 'AutoCAD2020-2024'; Framework = 'net48'; SeriesMin = 'R23.1'; SeriesMax = 'R24.3'; MaxAcadApi = [version]'23.1'; CoreLibrary = 'mscorlib' },
    @{ Folder = 'AutoCAD2025'; Framework = 'net8.0-windows'; SeriesMin = 'R25.0'; SeriesMax = 'R25.0'; MaxAcadApi = [version]'25.0'; CoreLibrary = 'System.Runtime' }
)

# Assemblies that AutoCAD itself provides; they must never be shipped with the plugin.
$AutoCadSdkAssemblies = @('AcCoreMgd', 'AcCui', 'AcDbMgd', 'acdbmgdbrep', 'AcDx', 'AcMgd', 'AcMr', 'AcSeamless', 'AcTcMgd', 'AcWindows', 'AdUIMgd', 'AdUiPalettes', 'AdWindows')

function Get-ProjectVersion {
    param([Parameter(Mandatory = $true)][string]$Root)

    [xml]$props = Get-Content -LiteralPath (Join-Path $Root 'Directory.Build.props') -Raw
    $node = $props.SelectSingleNode('/Project/PropertyGroup/Version')
    if ($null -eq $node -or [string]::IsNullOrWhiteSpace($node.InnerText)) {
        throw '<Version> was not found in Directory.Build.props'
    }
    return $node.InnerText.Trim()
}
