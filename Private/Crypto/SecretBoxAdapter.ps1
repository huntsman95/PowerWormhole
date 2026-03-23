function Protect-WormholeSecretBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Key,

        [Parameter(Mandatory = $true)]
        [byte[]] $Plaintext,

        [Parameter()]
        [byte[]] $Nonce
    )

    if ($null -eq $Nonce) {
        $Nonce = New-WormholeSecretBoxNonce
    }

    Protect-WormholeSecretBoxInternal -Key $Key -Plaintext $Plaintext -Nonce $Nonce
}

function Unprotect-WormholeSecretBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Key,

        [Parameter(Mandatory = $true)]
        [byte[]] $Ciphertext
    )

    Unprotect-WormholeSecretBoxInternal -Key $Key -Ciphertext $Ciphertext
}
