function ConvertTo-WormholeJsonBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object] $InputObject
    )

    $json = ConvertTo-Json -InputObject $InputObject -Depth 20 -Compress
    [System.Text.Encoding]::UTF8.GetBytes($json)
}

function ConvertFrom-WormholeJsonBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Bytes
    )

    $json = [System.Text.Encoding]::UTF8.GetString($Bytes)
    ConvertFrom-Json -InputObject $json
}
