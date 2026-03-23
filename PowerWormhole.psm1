Set-StrictMode -Version Latest

$script:ModuleRoot = Split-Path -Parent $PSCommandPath
$script:LibRoot = Join-Path $script:ModuleRoot 'lib'
$script:SystemMemoryAssemblyPath = Join-Path $script:LibRoot 'System.Memory\System.Memory.dll'
$script:NaClAssemblyPath = Join-Path $script:ModuleRoot 'lib\NaCl.Net\NaCl.dll'

function Import-WormholeAssembly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Required dependency not found: $Path"
    }

    $loadedAssembly = [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object {
            $_.Location -and [string]::Equals($_.Location, $Path, [System.StringComparison]::OrdinalIgnoreCase)
        } |
        Select-Object -First 1

    if ($null -eq $loadedAssembly) {
        [System.Reflection.Assembly]::LoadFrom($Path) | Out-Null
    }
}

if (Test-Path -Path $script:LibRoot) {
    $dependencyAssemblies = Get-ChildItem -Path $script:LibRoot -Filter '*.dll' -Recurse |
        Where-Object { $_.FullName -ne $script:NaClAssemblyPath } |
        Sort-Object FullName

    foreach ($assemblyFile in $dependencyAssemblies) {
        Import-WormholeAssembly -Path $assemblyFile.FullName
    }
}

Import-WormholeAssembly -Path $script:NaClAssemblyPath

$script:PowerWormholeDefaults = @{
    RelayUrl = 'ws://relay.magic-wormhole.io:4000/v1'
    AppId = 'lothar.com/wormhole/text-or-file-xfer'
    TransitRelay = 'tcp:transit.magic-wormhole.io:4001'
}

$privateScripts = Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Private') -Filter '*.ps1' -Recurse | Sort-Object FullName
foreach ($scriptFile in $privateScripts) {
    . $scriptFile.FullName
}

$publicScripts = Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Public') -Filter '*.ps1' -Recurse | Sort-Object FullName
foreach ($scriptFile in $publicScripts) {
    . $scriptFile.FullName
}

Export-ModuleMember -Function @(
    'New-WormholeCode',
    'Send-WormholeText',
    'Receive-WormholeText',
    'Send-WormholeFile',
    'Receive-WormholeFile'
)
