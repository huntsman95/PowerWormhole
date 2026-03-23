function Get-WormholePhaseKeyContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Side,

        [Parameter(Mandatory = $true)]
        [string] $Phase
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $sideHash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Side))
        $phaseHash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Phase))
    }
    finally {
        $sha.Dispose()
    }

    $prefix = [System.Text.Encoding]::UTF8.GetBytes('wormhole:phase:')
    $context = [byte[]]::new($prefix.Length + $sideHash.Length + $phaseHash.Length)
    [Array]::Copy($prefix, 0, $context, 0, $prefix.Length)
    [Array]::Copy($sideHash, 0, $context, $prefix.Length, $sideHash.Length)
    [Array]::Copy($phaseHash, 0, $context, $prefix.Length + $sideHash.Length, $phaseHash.Length)
    $context
}

function Get-WormholeDerivedPhaseKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $SharedKey,

        [Parameter(Mandatory = $true)]
        [string] $Side,

        [Parameter(Mandatory = $true)]
        [string] $Phase,

        [Parameter()]
        [int] $Length = 32
    )

    $info = Get-WormholePhaseKeyContext -Side $Side -Phase $Phase
    Invoke-WormholeHkdfSha256 -InputKeyMaterial $SharedKey -Info $info -Length $Length
}
