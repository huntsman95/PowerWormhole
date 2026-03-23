function Invoke-WormholeFileSendProtocol {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session,

        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    throw 'File transfer protocol is scaffolded but not yet active until SPAKE2 and SecretBox compatibility primitives are implemented.'
}

function Invoke-WormholeFileReceiveProtocol {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session,

        [Parameter(Mandatory = $true)]
        [string] $OutputDirectory
    )

    throw 'File transfer protocol is scaffolded but not yet active until SPAKE2 and SecretBox compatibility primitives are implemented.'
}
