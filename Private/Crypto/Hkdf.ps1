function Invoke-WormholeHkdfSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $InputKeyMaterial,

        [Parameter()]
        [byte[]] $Salt = ([byte[]]::new(32)),

        [Parameter()]
        [byte[]] $Info = ([byte[]]::new(0)),

        [Parameter()]
        [ValidateRange(1, 8160)]
        [int] $Length = 32
    )

    $hmac = [System.Security.Cryptography.HMACSHA256]::new($Salt)
    try {
        $prk = $hmac.ComputeHash($InputKeyMaterial)
    }
    finally {
        $hmac.Dispose()
    }

    $output = [System.Collections.Generic.List[byte]]::new()
    $previous = [byte[]]::new(0)
    $counter = 1

    while ($output.Count -lt $Length) {
        $blockMaterial = [System.Collections.Generic.List[byte]]::new()
        $blockMaterial.AddRange($previous)
        $blockMaterial.AddRange($Info)
        $blockMaterial.Add([byte]$counter)

        $expandHmac = [System.Security.Cryptography.HMACSHA256]::new($prk)
        try {
            $previous = $expandHmac.ComputeHash($blockMaterial.ToArray())
        }
        finally {
            $expandHmac.Dispose()
        }

        $output.AddRange($previous)
        $counter += 1
    }

    $result = [byte[]]::new($Length)
    [Array]::Copy($output.ToArray(), 0, $result, 0, $Length)
    $result
}
