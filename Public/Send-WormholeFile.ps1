function Send-WormholeFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string] $Path,

        [Parameter()]
        [string] $Code,

        [Parameter()]
        [string] $RelayUrl = $script:PowerWormholeDefaults.RelayUrl,

        [Parameter()]
        [string] $AppId = $script:PowerWormholeDefaults.AppId
    )

    $session = $null
    try {
        if ([string]::IsNullOrWhiteSpace($Code)) {
            $session = Open-Wormhole -AllocateCode -RelayUrl $RelayUrl -AppId $AppId
            Write-Host "Wormhole code is: $($session.Code)"
        }
        else {
            $session = Open-Wormhole -Code $Code -RelayUrl $RelayUrl -AppId $AppId
        }

        Invoke-WormholeFileSendProtocol -Session $session -Path $Path
    }
    finally {
        if ($null -ne $session) {
            Close-WormholeMailbox -Session $session -Mood 'happy'
        }
    }
}
