function Send-WormholeText {
    [CmdletBinding(DefaultParameterSetName = 'ByText')]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,

        [Parameter()]
        [string] $Code,

        [Parameter()]
        [string] $RelayUrl = $script:PowerWormholeDefaults.RelayUrl,

        [Parameter()]
        [string] $AppId = $script:PowerWormholeDefaults.AppId,

        [Parameter()]
        [ValidateRange(1, 3600)]
        [int] $TimeoutSeconds = 300,

        [Parameter()]
        [switch] $NoStatus,

        [Parameter()]
        [switch] $PassThru
    )

    $result = Send-Wormhole -Text $Text -Code $Code -RelayUrl $RelayUrl -AppId $AppId -TimeoutSeconds $TimeoutSeconds -NoStatus:$NoStatus
    if ($PassThru) {
        $result
    }
}
