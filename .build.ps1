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

task . Restore-LibPackages