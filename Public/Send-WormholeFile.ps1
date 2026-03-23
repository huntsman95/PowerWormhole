function Send-WormholeFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string] $Path,

        [Parameter()]
        [string] $Code,

        [Parameter()]
        [int] $TimeoutSeconds = 300,

        [Parameter()]
        [string] $RelayUrl = $script:PowerWormholeDefaults.RelayUrl,

        [Parameter()]
        [string] $AppId = $script:PowerWormholeDefaults.AppId
    )

    $null = Send-Wormhole -FilePath $Path -Code $Code -RelayUrl $RelayUrl -AppId $AppId -TimeoutSeconds $TimeoutSeconds
}
