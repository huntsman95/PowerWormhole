Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'

$script:ProjectRoot = Split-Path -Parent $BuildFile
$script:ArtifactsRoot = Join-Path $script:ProjectRoot '.artifacts'
$script:NuGetCacheRoot = Join-Path $script:ArtifactsRoot 'nuget'
$script:LibRoot = Join-Path $script:ProjectRoot 'lib'

$script:DependencyMap = @(
    @{
        PackageId = 'System.Memory'
        Version = '4.5.4'
        TargetFramework = 'netstandard2.0'
        DestinationFolder = 'System.Memory'
    },
    @{
        PackageId = 'System.Runtime.CompilerServices.Unsafe'
        Version = '4.5.3'
        TargetFramework = 'netstandard2.0'
        DestinationFolder = 'System.Runtime.CompilerServices.Unsafe'
    },
    @{
        PackageId = 'NaCl.Net'
        Version = '0.1.13'
        TargetFramework = 'netstandard2.0'
        DestinationFolder = 'NaCl.Net'
    }
)

function Get-NuGetFlatContainerUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string] $PackageId,

        [Parameter(Mandatory = $true)]
        [string] $Version
    )

    $lowerPackageId = $PackageId.ToLowerInvariant()
    $lowerVersion = $Version.ToLowerInvariant()
    return "https://api.nuget.org/v3-flatcontainer/$lowerPackageId/$lowerVersion/$lowerPackageId.$lowerVersion.nupkg"
}

function Copy-FilteredBuildItem {
    param(
        [Parameter(Mandatory = $true)]
        [string] $SourcePath,

        [Parameter(Mandatory = $true)]
        [string] $DestinationPath
    )

    $sourceItem = Get-Item -LiteralPath $SourcePath -Force
    if ($sourceItem.Name -like '.*') {
        return
    }

    if ($sourceItem.PSIsContainer) {
        New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        $children = Get-ChildItem -LiteralPath $sourceItem.FullName -Force
        foreach ($child in $children) {
            if ($child.Name -like '.*') {
                continue
            }

            $childDestination = Join-Path $DestinationPath $child.Name
            Copy-FilteredBuildItem -SourcePath $child.FullName -DestinationPath $childDestination
        }

        return
    }

    $destinationDirectory = Split-Path -Path $DestinationPath -Parent
    if (-not (Test-Path -LiteralPath $destinationDirectory)) {
        New-Item -Path $destinationDirectory -ItemType Directory -Force | Out-Null
    }

    Copy-Item -LiteralPath $sourceItem.FullName -Destination $DestinationPath -Force
}

task Restore-LibPackages {
    New-Item -Path $script:NuGetCacheRoot -ItemType Directory -Force | Out-Null

    foreach ($dependency in $script:DependencyMap) {
        $packageId = [string] $dependency.PackageId
        $version = [string] $dependency.Version
        $targetFramework = [string] $dependency.TargetFramework
        $destinationFolderName = [string] $dependency.DestinationFolder

        $packageCacheFolder = Join-Path $script:NuGetCacheRoot ("{0}.{1}" -f $packageId, $version)
        $nupkgPath = Join-Path $script:NuGetCacheRoot ("{0}.{1}.nupkg" -f $packageId, $version)
        $targetLibPath = Join-Path $packageCacheFolder (Join-Path 'lib' $targetFramework)

        if (-not (Test-Path -Path $packageCacheFolder)) {
            $downloadUrl = Get-NuGetFlatContainerUrl -PackageId $packageId -Version $version
            Write-Host "Downloading $packageId $version from $downloadUrl"
            Invoke-WebRequest -Uri $downloadUrl -OutFile $nupkgPath
            Expand-Archive -Path $nupkgPath -DestinationPath $packageCacheFolder -Force
        }

        if (-not (Test-Path -Path $targetLibPath)) {
            throw "Package asset path not found for $packageId ($targetFramework): $targetLibPath"
        }

        $destinationFolder = Join-Path $script:LibRoot $destinationFolderName
        New-Item -Path $destinationFolder -ItemType Directory -Force | Out-Null

        $assets = Get-ChildItem -Path $targetLibPath -File | Where-Object { $_.Extension -in '.dll', '.xml' }
        foreach ($asset in $assets) {
            $destinationPath = Join-Path $destinationFolder $asset.Name

            if (Test-Path -Path $destinationPath) {
                $sourceHash = (Get-FileHash -Path $asset.FullName -Algorithm SHA256).Hash
                $destinationHash = (Get-FileHash -Path $destinationPath -Algorithm SHA256).Hash

                if ($sourceHash -eq $destinationHash) {
                    continue
                }
            }

            try {
                Copy-Item -Path $asset.FullName -Destination $destinationPath -Force
            }
            catch {
                throw "Failed to update '$destinationPath'. The file may be locked by an active PowerShell session that imported this module. Close those sessions and re-run the build. Original error: $($_.Exception.Message)"
            }
        }

        Write-Host "Restored $packageId $version assets to $destinationFolder"
    }
}

task Package-Module {
    $manifestPath = Join-Path $script:ProjectRoot 'PowerWormhole.psd1'
    $manifestData = Import-PowerShellDataFile -Path $manifestPath
    #$moduleVersion = [string] $manifestData.ModuleVersion
    $moduleVersion = 'PowerWormhole-' + $manifestData.ModuleVersion

    if ([string]::IsNullOrWhiteSpace($moduleVersion)) {
        throw "ModuleVersion is missing in '$manifestPath'."
    }

    $buildRoot = Join-Path $script:ProjectRoot 'Build'
    $versionBuildRoot = Join-Path $buildRoot $moduleVersion

    if (Test-Path -LiteralPath $versionBuildRoot) {
          Remove-Item -LiteralPath $versionBuildRoot -Recurse -Force
    }

    New-Item -Path $versionBuildRoot -ItemType Directory -Force | Out-Null

     $excludedTopLevelDirectories = @('Build', 'docs', 'tests')
    $excludedTopLevelFiles = @('README.md', 'testResults.xml')
    $rootItems = Get-ChildItem -LiteralPath $script:ProjectRoot -Force

    foreach ($item in $rootItems) {
        if ($item.Name -like '.*') {
            continue
        }

        if ($item.PSIsContainer -and ($excludedTopLevelDirectories -contains $item.Name)) {
            continue
        }

        if ((-not $item.PSIsContainer) -and ($excludedTopLevelFiles -contains $item.Name)) {
            continue
        }

        $destinationPath = Join-Path $versionBuildRoot $item.Name
        Copy-FilteredBuildItem -SourcePath $item.FullName -DestinationPath $destinationPath
    }

    Write-Host "Packaged module to $versionBuildRoot"
}

task . Restore-LibPackages