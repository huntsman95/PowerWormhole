function ConvertTo-WormholeHex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Bytes
    )

    $builder = [System.Text.StringBuilder]::new($Bytes.Length * 2)
    foreach ($value in $Bytes) {
        [void] $builder.AppendFormat('{0:x2}', $value)
    }

    $builder.ToString()
}

function ConvertFrom-WormholeHex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Hex
    )

    $normalized = $Hex.Trim()
    if (($normalized.Length % 2) -ne 0) {
        throw 'Hex string must have an even number of characters.'
    }

    $buffer = [byte[]]::new($normalized.Length / 2)
    for ($index = 0; $index -lt $normalized.Length; $index += 2) {
        $buffer[$index / 2] = [System.Convert]::ToByte($normalized.Substring($index, 2), 16)
    }

    $buffer
}
