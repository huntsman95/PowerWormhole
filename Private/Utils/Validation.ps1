function Test-WormholeRelayUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $RelayUrl
    )

    if ([string]::IsNullOrWhiteSpace($RelayUrl)) {
        return $false
    }

    [System.Uri] $parsed = $null
    if (-not [System.Uri]::TryCreate($RelayUrl, [System.UriKind]::Absolute, [ref] $parsed)) {
        return $false
    }

    ($parsed.Scheme -eq 'ws' -or $parsed.Scheme -eq 'wss')
}

function Assert-WormholeRelayUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $RelayUrl
    )

    if (-not (Test-WormholeRelayUrl -RelayUrl $RelayUrl)) {
        throw "RelayUrl must be a valid ws:// or wss:// URL. Value: $RelayUrl"
    }
}
