function New-WormholeCode {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(1, 8)]
        [int] $CodeLength = 2,

        [Parameter()]
        [string] $Nameplate
    )

    if ([string]::IsNullOrWhiteSpace($Nameplate)) {
        $bytes = [byte[]]::new(2)
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $rng.GetBytes($bytes)
            $value = [System.BitConverter]::ToUInt16($bytes, 0)
            $Nameplate = [string](($value % 16384) + 1)
        }
        finally {
            $rng.Dispose()
        }
    }

    $words = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $CodeLength; $index += 1) {
        $words.Add((Get-WormholeRandomWord))
    }

    "$Nameplate-$($words -join '-')"
}
