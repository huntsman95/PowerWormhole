Set-StrictMode -Version Latest

$script:ModuleRoot = Split-Path -Parent $PSCommandPath
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
    'Open-Wormhole',
    'Send-WormholeText',
    'Receive-WormholeText',
    'Send-WormholeFile',
    'Receive-WormholeFile'
)
