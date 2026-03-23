function New-WormholeConnectionHints {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $TransitRelay = $script:PowerWormholeDefaults.TransitRelay
    )

    [pscustomobject]@{
        'abilities-v1' = @('direct-tcp-v1', 'relay-v1')
        'hints-v1' = @(
            @{
                type = 'relay-v1'
                hints = @(
                    @{
                        hostname = ($TransitRelay -replace '^tcp:', '').Split(':')[0]
                        port = [int](($TransitRelay -replace '^tcp:', '').Split(':')[1])
                        priority = 0.0
                    }
                )
            }
        )
    }
}
