function Start-WormholeSpake2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Code,

        [Parameter()]
        [string] $AppId = $script:PowerWormholeDefaults.AppId,

        [Parameter()]
        [byte[]] $RandomBytes
    )

    if ([string]::IsNullOrWhiteSpace($Code)) {
        throw 'Code is required for SPAKE2.'
    }

    $password = [System.Text.Encoding]::UTF8.GetBytes($Code)
    $idSymmetric = [System.Text.Encoding]::UTF8.GetBytes($AppId)

    if ($null -eq $RandomBytes) {
        $RandomBytes = [byte[]]::new(64)
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $rng.GetBytes($RandomBytes)
        }
        finally {
            $rng.Dispose()
        }
    }

    New-Spake2SymmetricContext -Password $password -IdSymmetric $idSymmetric -RandomBytes $RandomBytes
}

function Complete-WormholeSpake2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Context,

        [Parameter(Mandatory = $true)]
        [byte[]] $PeerMessage
    )

    Complete-Spake2Symmetric -Context $Context -InboundSideAndMessage $PeerMessage
}
