function Open-Wormhole {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $Code,

        [Parameter()]
        [string] $RelayUrl = $script:PowerWormholeDefaults.RelayUrl,

        [Parameter()]
        [string] $AppId = $script:PowerWormholeDefaults.AppId,

        [Parameter()]
        [switch] $AllocateCode
    )

    Assert-WormholeRelayUrl -RelayUrl $RelayUrl
    Write-WormholeDebug -Component 'open' -Message 'Open-Wormhole invoked.' -Data @{ hasCode = (-not [string]::IsNullOrWhiteSpace($Code)); allocateCode = [bool]$AllocateCode; relayUrl = $RelayUrl; appId = $AppId }

    $side = New-WormholeSideId
    $nameplate = $null

    if (-not [string]::IsNullOrWhiteSpace($Code)) {
        $parts = $Code.Split('-')
        if ($parts.Count -lt 2) {
            throw 'Code must be in nameplate-word-word format.'
        }

        $nameplate = $parts[0]
    }
    elseif (-not $AllocateCode) {
        throw 'Provide -Code or specify -AllocateCode.'
    }

    $session = New-PowerWormholeSession -Code $Code -Nameplate $nameplate -RelayUrl $RelayUrl -AppId $AppId -Side $side
    Write-WormholeDebug -Component 'open' -Message 'Session object created.' -Session $session

    Connect-WormholeMailbox -Session $session | Out-Null
    Open-WormholeMailbox -Session $session -AllocateNameplate:$AllocateCode | Out-Null

    if ($AllocateCode) {
        $generatedCode = New-WormholeCode -Nameplate $session.Nameplate
        $session.Code = $generatedCode
        Write-WormholeDebug -Component 'open' -Message 'Generated code after nameplate allocation.' -Session $session -Data @{ code = $session.Code }
    }

    Write-WormholeDebug -Component 'open' -Message 'Open-Wormhole completed.' -Session $session
    $session
}
