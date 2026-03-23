function New-WormholeTransitContext {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $Relay = $script:PowerWormholeDefaults.TransitRelay
    )

    [pscustomobject]@{
        PSTypeName = 'PowerWormhole.TransitContext'
        Relay = $Relay
        Hints = New-WormholeConnectionHints -TransitRelay $Relay
    }
}
