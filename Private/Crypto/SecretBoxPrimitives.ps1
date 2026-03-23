$script:Salsa20Sigma = [System.Text.Encoding]::ASCII.GetBytes('expand 32-byte k')

function ConvertFrom-UInt32LE {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Bytes,

        [Parameter(Mandatory = $true)]
        [int] $Offset
    )

    [uint32]$b0 = [uint32]$Bytes[$Offset]
    [uint32]$b1 = [uint32]$Bytes[$Offset + 1]
    [uint32]$b2 = [uint32]$Bytes[$Offset + 2]
    [uint32]$b3 = [uint32]$Bytes[$Offset + 3]
    [uint32]($b0 -bor ($b1 -shl 8) -bor ($b2 -shl 16) -bor ($b3 -shl 24))
}

function ConvertTo-UInt32LEBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uint32] $Value
    )

    [byte[]]@(
        [byte]($Value -band 0xff),
        [byte](($Value -shr 8) -band 0xff),
        [byte](($Value -shr 16) -band 0xff),
        [byte](($Value -shr 24) -band 0xff)
    )
}

function Invoke-RotateLeft32 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [UInt64] $Value,

        [Parameter(Mandatory = $true)]
        [int] $Bits
    )

    $mask = [UInt64]4294967295
    $value32 = $Value -band $mask
    $left = ($value32 -shl $Bits) -band $mask
    $right = ($value32 -shr (32 - $Bits)) -band $mask
    [uint32](($left -bor $right) -band $mask)
}

function Add-WormholeUInt32 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uint32] $Left,

        [Parameter(Mandatory = $true)]
        [uint32] $Right
    )

    [uint32]((([UInt64]$Left + [UInt64]$Right) -band [UInt64]4294967295)
)
}

function Invoke-SalsaQuarterRound {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ref] $Y0,

        [Parameter(Mandatory = $true)]
        [ref] $Y1,

        [Parameter(Mandatory = $true)]
        [ref] $Y2,

        [Parameter(Mandatory = $true)]
        [ref] $Y3
    )

    [uint32]$z1 = [uint32]($Y1.Value -bxor (Invoke-RotateLeft32 -Value ([uint32]($Y0.Value + $Y3.Value)) -Bits 7))
    [uint32]$z2 = [uint32]($Y2.Value -bxor (Invoke-RotateLeft32 -Value ([uint32]($z1 + $Y0.Value)) -Bits 9))
    [uint32]$z3 = [uint32]($Y3.Value -bxor (Invoke-RotateLeft32 -Value ([uint32]($z2 + $z1)) -Bits 13))
    [uint32]$z0 = [uint32]($Y0.Value -bxor (Invoke-RotateLeft32 -Value ([uint32]($z3 + $z2)) -Bits 18))

    $Y0.Value = $z0
    $Y1.Value = $z1
    $Y2.Value = $z2
    $Y3.Value = $z3
}

function Invoke-Salsa20Core {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uint32[]] $InputState
    )

    if ($InputState.Length -ne 16) {
        throw 'Salsa20 core input must have 16 words.'
    }

    [uint32]$j0 = $InputState[0]
    [uint32]$j1 = $InputState[1]
    [uint32]$j2 = $InputState[2]
    [uint32]$j3 = $InputState[3]
    [uint32]$j4 = $InputState[4]
    [uint32]$j5 = $InputState[5]
    [uint32]$j6 = $InputState[6]
    [uint32]$j7 = $InputState[7]
    [uint32]$j8 = $InputState[8]
    [uint32]$j9 = $InputState[9]
    [uint32]$j10 = $InputState[10]
    [uint32]$j11 = $InputState[11]
    [uint32]$j12 = $InputState[12]
    [uint32]$j13 = $InputState[13]
    [uint32]$j14 = $InputState[14]
    [uint32]$j15 = $InputState[15]

    [uint32]$x0 = $j0
    [uint32]$x1 = $j1
    [uint32]$x2 = $j2
    [uint32]$x3 = $j3
    [uint32]$x4 = $j4
    [uint32]$x5 = $j5
    [uint32]$x6 = $j6
    [uint32]$x7 = $j7
    [uint32]$x8 = $j8
    [uint32]$x9 = $j9
    [uint32]$x10 = $j10
    [uint32]$x11 = $j11
    [uint32]$x12 = $j12
    [uint32]$x13 = $j13
    [uint32]$x14 = $j14
    [uint32]$x15 = $j15

    for ($round = 0; $round -lt 20; $round += 2) {
        $x4 = [uint32]($x4 -bxor (Invoke-RotateLeft32 -Value ($x0 + $x12) -Bits 7))
        $x8 = [uint32]($x8 -bxor (Invoke-RotateLeft32 -Value ($x4 + $x0) -Bits 9))
        $x12 = [uint32]($x12 -bxor (Invoke-RotateLeft32 -Value ($x8 + $x4) -Bits 13))
        $x0 = [uint32]($x0 -bxor (Invoke-RotateLeft32 -Value ($x12 + $x8) -Bits 18))

        $x9 = [uint32]($x9 -bxor (Invoke-RotateLeft32 -Value ($x5 + $x1) -Bits 7))
        $x13 = [uint32]($x13 -bxor (Invoke-RotateLeft32 -Value ($x9 + $x5) -Bits 9))
        $x1 = [uint32]($x1 -bxor (Invoke-RotateLeft32 -Value ($x13 + $x9) -Bits 13))
        $x5 = [uint32]($x5 -bxor (Invoke-RotateLeft32 -Value ($x1 + $x13) -Bits 18))

        $x14 = [uint32]($x14 -bxor (Invoke-RotateLeft32 -Value ($x10 + $x6) -Bits 7))
        $x2 = [uint32]($x2 -bxor (Invoke-RotateLeft32 -Value ($x14 + $x10) -Bits 9))
        $x6 = [uint32]($x6 -bxor (Invoke-RotateLeft32 -Value ($x2 + $x14) -Bits 13))
        $x10 = [uint32]($x10 -bxor (Invoke-RotateLeft32 -Value ($x6 + $x2) -Bits 18))

        $x3 = [uint32]($x3 -bxor (Invoke-RotateLeft32 -Value ($x15 + $x11) -Bits 7))
        $x7 = [uint32]($x7 -bxor (Invoke-RotateLeft32 -Value ($x3 + $x15) -Bits 9))
        $x11 = [uint32]($x11 -bxor (Invoke-RotateLeft32 -Value ($x7 + $x3) -Bits 13))
        $x15 = [uint32]($x15 -bxor (Invoke-RotateLeft32 -Value ($x11 + $x7) -Bits 18))

        $x1 = [uint32]($x1 -bxor (Invoke-RotateLeft32 -Value ($x0 + $x3) -Bits 7))
        $x2 = [uint32]($x2 -bxor (Invoke-RotateLeft32 -Value ($x1 + $x0) -Bits 9))
        $x3 = [uint32]($x3 -bxor (Invoke-RotateLeft32 -Value ($x2 + $x1) -Bits 13))
        $x0 = [uint32]($x0 -bxor (Invoke-RotateLeft32 -Value ($x3 + $x2) -Bits 18))

        $x6 = [uint32]($x6 -bxor (Invoke-RotateLeft32 -Value ($x5 + $x4) -Bits 7))
        $x7 = [uint32]($x7 -bxor (Invoke-RotateLeft32 -Value ($x6 + $x5) -Bits 9))
        $x4 = [uint32]($x4 -bxor (Invoke-RotateLeft32 -Value ($x7 + $x6) -Bits 13))
        $x5 = [uint32]($x5 -bxor (Invoke-RotateLeft32 -Value ($x4 + $x7) -Bits 18))

        $x11 = [uint32]($x11 -bxor (Invoke-RotateLeft32 -Value ($x10 + $x9) -Bits 7))
        $x8 = [uint32]($x8 -bxor (Invoke-RotateLeft32 -Value ($x11 + $x10) -Bits 9))
        $x9 = [uint32]($x9 -bxor (Invoke-RotateLeft32 -Value ($x8 + $x11) -Bits 13))
        $x10 = [uint32]($x10 -bxor (Invoke-RotateLeft32 -Value ($x9 + $x8) -Bits 18))

        $x12 = [uint32]($x12 -bxor (Invoke-RotateLeft32 -Value ($x15 + $x14) -Bits 7))
        $x13 = [uint32]($x13 -bxor (Invoke-RotateLeft32 -Value ($x12 + $x15) -Bits 9))
        $x14 = [uint32]($x14 -bxor (Invoke-RotateLeft32 -Value ($x13 + $x12) -Bits 13))
        $x15 = [uint32]($x15 -bxor (Invoke-RotateLeft32 -Value ($x14 + $x13) -Bits 18))
    }

    $out = [uint32[]]::new(16)
    $out[0] = Add-WormholeUInt32 -Left $x0 -Right $j0
    $out[1] = Add-WormholeUInt32 -Left $x1 -Right $j1
    $out[2] = Add-WormholeUInt32 -Left $x2 -Right $j2
    $out[3] = Add-WormholeUInt32 -Left $x3 -Right $j3
    $out[4] = Add-WormholeUInt32 -Left $x4 -Right $j4
    $out[5] = Add-WormholeUInt32 -Left $x5 -Right $j5
    $out[6] = Add-WormholeUInt32 -Left $x6 -Right $j6
    $out[7] = Add-WormholeUInt32 -Left $x7 -Right $j7
    $out[8] = Add-WormholeUInt32 -Left $x8 -Right $j8
    $out[9] = Add-WormholeUInt32 -Left $x9 -Right $j9
    $out[10] = Add-WormholeUInt32 -Left $x10 -Right $j10
    $out[11] = Add-WormholeUInt32 -Left $x11 -Right $j11
    $out[12] = Add-WormholeUInt32 -Left $x12 -Right $j12
    $out[13] = Add-WormholeUInt32 -Left $x13 -Right $j13
    $out[14] = Add-WormholeUInt32 -Left $x14 -Right $j14
    $out[15] = Add-WormholeUInt32 -Left $x15 -Right $j15

    $bytes = [byte[]]::new(64)
    for ($word = 0; $word -lt 16; $word += 1) {
        $wordBytes = ConvertTo-UInt32LEBytes -Value $out[$word]
        [Array]::Copy($wordBytes, 0, $bytes, $word * 4, 4)
    }

    $bytes
}

function Invoke-HSalsa20 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Key,

        [Parameter(Mandatory = $true)]
        [byte[]] $Nonce16
    )

    if ($Key.Length -ne 32) { throw 'HSalsa20 key must be 32 bytes.' }
    if ($Nonce16.Length -ne 16) { throw 'HSalsa20 nonce must be 16 bytes.' }

    $state = [uint32[]]::new(16)
    $state[0] = ConvertFrom-UInt32LE -Bytes $script:Salsa20Sigma -Offset 0
    $state[5] = ConvertFrom-UInt32LE -Bytes $script:Salsa20Sigma -Offset 4
    $state[10] = ConvertFrom-UInt32LE -Bytes $script:Salsa20Sigma -Offset 8
    $state[15] = ConvertFrom-UInt32LE -Bytes $script:Salsa20Sigma -Offset 12

    $state[1] = ConvertFrom-UInt32LE -Bytes $Key -Offset 0
    $state[2] = ConvertFrom-UInt32LE -Bytes $Key -Offset 4
    $state[3] = ConvertFrom-UInt32LE -Bytes $Key -Offset 8
    $state[4] = ConvertFrom-UInt32LE -Bytes $Key -Offset 12
    $state[11] = ConvertFrom-UInt32LE -Bytes $Key -Offset 16
    $state[12] = ConvertFrom-UInt32LE -Bytes $Key -Offset 20
    $state[13] = ConvertFrom-UInt32LE -Bytes $Key -Offset 24
    $state[14] = ConvertFrom-UInt32LE -Bytes $Key -Offset 28

    $state[6] = ConvertFrom-UInt32LE -Bytes $Nonce16 -Offset 0
    $state[7] = ConvertFrom-UInt32LE -Bytes $Nonce16 -Offset 4
    $state[8] = ConvertFrom-UInt32LE -Bytes $Nonce16 -Offset 8
    $state[9] = ConvertFrom-UInt32LE -Bytes $Nonce16 -Offset 12

    [uint32]$x0 = $state[0]
    [uint32]$x1 = $state[1]
    [uint32]$x2 = $state[2]
    [uint32]$x3 = $state[3]
    [uint32]$x4 = $state[4]
    [uint32]$x5 = $state[5]
    [uint32]$x6 = $state[6]
    [uint32]$x7 = $state[7]
    [uint32]$x8 = $state[8]
    [uint32]$x9 = $state[9]
    [uint32]$x10 = $state[10]
    [uint32]$x11 = $state[11]
    [uint32]$x12 = $state[12]
    [uint32]$x13 = $state[13]
    [uint32]$x14 = $state[14]
    [uint32]$x15 = $state[15]

    for ($round = 20; $round -gt 0; $round -= 2) {
        $x4 = [uint32]($x4 -bxor (Invoke-RotateLeft32 -Value ($x0 + $x12) -Bits 7))
        $x8 = [uint32]($x8 -bxor (Invoke-RotateLeft32 -Value ($x4 + $x0) -Bits 9))
        $x12 = [uint32]($x12 -bxor (Invoke-RotateLeft32 -Value ($x8 + $x4) -Bits 13))
        $x0 = [uint32]($x0 -bxor (Invoke-RotateLeft32 -Value ($x12 + $x8) -Bits 18))

        $x9 = [uint32]($x9 -bxor (Invoke-RotateLeft32 -Value ($x5 + $x1) -Bits 7))
        $x13 = [uint32]($x13 -bxor (Invoke-RotateLeft32 -Value ($x9 + $x5) -Bits 9))
        $x1 = [uint32]($x1 -bxor (Invoke-RotateLeft32 -Value ($x13 + $x9) -Bits 13))
        $x5 = [uint32]($x5 -bxor (Invoke-RotateLeft32 -Value ($x1 + $x13) -Bits 18))

        $x14 = [uint32]($x14 -bxor (Invoke-RotateLeft32 -Value ($x10 + $x6) -Bits 7))
        $x2 = [uint32]($x2 -bxor (Invoke-RotateLeft32 -Value ($x14 + $x10) -Bits 9))
        $x6 = [uint32]($x6 -bxor (Invoke-RotateLeft32 -Value ($x2 + $x14) -Bits 13))
        $x10 = [uint32]($x10 -bxor (Invoke-RotateLeft32 -Value ($x6 + $x2) -Bits 18))

        $x3 = [uint32]($x3 -bxor (Invoke-RotateLeft32 -Value ($x15 + $x11) -Bits 7))
        $x7 = [uint32]($x7 -bxor (Invoke-RotateLeft32 -Value ($x3 + $x15) -Bits 9))
        $x11 = [uint32]($x11 -bxor (Invoke-RotateLeft32 -Value ($x7 + $x3) -Bits 13))
        $x15 = [uint32]($x15 -bxor (Invoke-RotateLeft32 -Value ($x11 + $x7) -Bits 18))

        $x1 = [uint32]($x1 -bxor (Invoke-RotateLeft32 -Value ($x0 + $x3) -Bits 7))
        $x2 = [uint32]($x2 -bxor (Invoke-RotateLeft32 -Value ($x1 + $x0) -Bits 9))
        $x3 = [uint32]($x3 -bxor (Invoke-RotateLeft32 -Value ($x2 + $x1) -Bits 13))
        $x0 = [uint32]($x0 -bxor (Invoke-RotateLeft32 -Value ($x3 + $x2) -Bits 18))

        $x6 = [uint32]($x6 -bxor (Invoke-RotateLeft32 -Value ($x5 + $x4) -Bits 7))
        $x7 = [uint32]($x7 -bxor (Invoke-RotateLeft32 -Value ($x6 + $x5) -Bits 9))
        $x4 = [uint32]($x4 -bxor (Invoke-RotateLeft32 -Value ($x7 + $x6) -Bits 13))
        $x5 = [uint32]($x5 -bxor (Invoke-RotateLeft32 -Value ($x4 + $x7) -Bits 18))

        $x11 = [uint32]($x11 -bxor (Invoke-RotateLeft32 -Value ($x10 + $x9) -Bits 7))
        $x8 = [uint32]($x8 -bxor (Invoke-RotateLeft32 -Value ($x11 + $x10) -Bits 9))
        $x9 = [uint32]($x9 -bxor (Invoke-RotateLeft32 -Value ($x8 + $x11) -Bits 13))
        $x10 = [uint32]($x10 -bxor (Invoke-RotateLeft32 -Value ($x9 + $x8) -Bits 18))

        $x12 = [uint32]($x12 -bxor (Invoke-RotateLeft32 -Value ($x15 + $x14) -Bits 7))
        $x13 = [uint32]($x13 -bxor (Invoke-RotateLeft32 -Value ($x12 + $x15) -Bits 9))
        $x14 = [uint32]($x14 -bxor (Invoke-RotateLeft32 -Value ($x13 + $x12) -Bits 13))
        $x15 = [uint32]($x15 -bxor (Invoke-RotateLeft32 -Value ($x14 + $x13) -Bits 18))
    }

    $outWords = @($x0, $x5, $x10, $x15, $x6, $x7, $x8, $x9)
    $out = [byte[]]::new(32)
    for ($word = 0; $word -lt 8; $word += 1) {
        $w = ConvertTo-UInt32LEBytes -Value $outWords[$word]
        [Array]::Copy($w, 0, $out, $word * 4, 4)
    }

    $out
}

function Invoke-Salsa20StreamXor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Key,

        [Parameter(Mandatory = $true)]
        [byte[]] $Nonce8,

        [Parameter(Mandatory = $true)]
        [byte[]] $Data,

        [Parameter()]
        [UInt64] $InitialCounter = 0
    )

    if ($Key.Length -ne 32) { throw 'Salsa20 key must be 32 bytes.' }
    if ($Nonce8.Length -ne 8) { throw 'Salsa20 nonce must be 8 bytes.' }

    $out = [byte[]]::new($Data.Length)
    $offset = 0
    $counter = $InitialCounter

    while ($offset -lt $Data.Length) {
        $state = [uint32[]]::new(16)
        $state[0] = ConvertFrom-UInt32LE -Bytes $script:Salsa20Sigma -Offset 0
        $state[5] = ConvertFrom-UInt32LE -Bytes $script:Salsa20Sigma -Offset 4
        $state[10] = ConvertFrom-UInt32LE -Bytes $script:Salsa20Sigma -Offset 8
        $state[15] = ConvertFrom-UInt32LE -Bytes $script:Salsa20Sigma -Offset 12

        $state[1] = ConvertFrom-UInt32LE -Bytes $Key -Offset 0
        $state[2] = ConvertFrom-UInt32LE -Bytes $Key -Offset 4
        $state[3] = ConvertFrom-UInt32LE -Bytes $Key -Offset 8
        $state[4] = ConvertFrom-UInt32LE -Bytes $Key -Offset 12
        $state[11] = ConvertFrom-UInt32LE -Bytes $Key -Offset 16
        $state[12] = ConvertFrom-UInt32LE -Bytes $Key -Offset 20
        $state[13] = ConvertFrom-UInt32LE -Bytes $Key -Offset 24
        $state[14] = ConvertFrom-UInt32LE -Bytes $Key -Offset 28

        $state[6] = ConvertFrom-UInt32LE -Bytes $Nonce8 -Offset 0
        $state[7] = ConvertFrom-UInt32LE -Bytes $Nonce8 -Offset 4
        $state[8] = [uint32]($counter -band 0xffffffff)
        $state[9] = [uint32](($counter -shr 32) -band 0xffffffff)

        $block = Invoke-Salsa20Core -InputState $state
        $take = [Math]::Min(64, $Data.Length - $offset)

        for ($index = 0; $index -lt $take; $index += 1) {
            $out[$offset + $index] = $Data[$offset + $index] -bxor $block[$index]
        }

        $offset += $take
        $counter += 1
    }

    $out
}

function Invoke-Poly1305Mac {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Key,

        [Parameter()]
        [byte[]] $Message
    )

    if ($Key.Length -ne 32) {
        throw 'Poly1305 key must be 32 bytes.'
    }

    if ($null -eq $Message) {
        $Message = [byte[]]::new(0)
    }

    $rBytes = [byte[]]::new(16)
    $sBytes = [byte[]]::new(16)
    [Array]::Copy($Key, 0, $rBytes, 0, 16)
    [Array]::Copy($Key, 16, $sBytes, 0, 16)

    $rBytes[3] = $rBytes[3] -band 15
    $rBytes[7] = $rBytes[7] -band 15
    $rBytes[11] = $rBytes[11] -band 15
    $rBytes[15] = $rBytes[15] -band 15
    $rBytes[4] = $rBytes[4] -band 252
    $rBytes[8] = $rBytes[8] -band 252
    $rBytes[12] = $rBytes[12] -band 252

    $r = ConvertFrom-BigIntegerLittleEndianBytes -Bytes $rBytes
    $s = ConvertFrom-BigIntegerLittleEndianBytes -Bytes $sBytes

    $p = [System.Numerics.BigInteger]::Pow([System.Numerics.BigInteger]2, 130) - 5
    $acc = [System.Numerics.BigInteger]::Zero

    $offset = 0
    while ($offset -lt $Message.Length) {
        $take = [Math]::Min(16, $Message.Length - $offset)
        $block = [byte[]]::new($take + 1)
        [Array]::Copy($Message, $offset, $block, 0, $take)
        $block[$take] = 1

        $n = ConvertFrom-BigIntegerLittleEndianBytes -Bytes $block
        $acc = ($acc + $n) % $p
        $acc = ($acc * $r) % $p
        $offset += $take
    }

    $mod128 = [System.Numerics.BigInteger]::Pow([System.Numerics.BigInteger]2, 128)
    $tagValue = ($acc + $s) % $mod128
    ConvertTo-BigIntegerLittleEndianBytes -Value $tagValue -Length 16
}

function New-WormholeSecretBoxNonce {
    [CmdletBinding()]
    param()

    $nonce = [byte[]]::new(24)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($nonce)
    }
    finally {
        $rng.Dispose()
    }

    $nonce
}

function Protect-WormholeSecretBoxInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Key,

        [Parameter()]
        [byte[]] $Plaintext,

        [Parameter(Mandatory = $true)]
        [byte[]] $Nonce
    )

    if ($Key.Length -ne 32) { throw 'SecretBox key must be 32 bytes.' }
    if ($Nonce.Length -ne 24) { throw 'SecretBox nonce must be 24 bytes.' }

    if ($null -eq $Plaintext) {
        $Plaintext = [byte[]]::new(0)
    }

    $nonce16 = [byte[]]::new(16)
    $nonce8 = [byte[]]::new(8)
    [Array]::Copy($Nonce, 0, $nonce16, 0, 16)
    [Array]::Copy($Nonce, 16, $nonce8, 0, 8)

    $subKey = Invoke-HSalsa20 -Key $Key -Nonce16 $nonce16
    $firstChunk = [Math]::Min($Plaintext.Length, 32)
    $block0Input = [byte[]]::new($firstChunk + 32)
    if ($firstChunk -gt 0) {
        [Array]::Copy($Plaintext, 0, $block0Input, 32, $firstChunk)
    }
    $block0Output = Invoke-Salsa20StreamXor -Key $subKey -Nonce8 $nonce8 -Data $block0Input -InitialCounter 0

    $polyKey = [byte[]]::new(32)
    [Array]::Copy($block0Output, 0, $polyKey, 0, 32)

    $ciphertext = [byte[]]::new($Plaintext.Length)
    if ($firstChunk -gt 0) {
        [Array]::Copy($block0Output, 32, $ciphertext, 0, $firstChunk)
    }
    if ($Plaintext.Length -gt $firstChunk) {
        $remainingLength = $Plaintext.Length - $firstChunk
        $remainingPlain = [byte[]]::new($remainingLength)
        [Array]::Copy($Plaintext, $firstChunk, $remainingPlain, 0, $remainingLength)
        $remainingCipher = Invoke-Salsa20StreamXor -Key $subKey -Nonce8 $nonce8 -Data $remainingPlain -InitialCounter 1
        [Array]::Copy($remainingCipher, 0, $ciphertext, $firstChunk, $remainingLength)
    }
    $mac = Invoke-Poly1305Mac -Key $polyKey -Message $ciphertext

    $result = [byte[]]::new(24 + 16 + $ciphertext.Length)
    [Array]::Copy($Nonce, 0, $result, 0, 24)
    [Array]::Copy($mac, 0, $result, 24, 16)
    [Array]::Copy($ciphertext, 0, $result, 40, $ciphertext.Length)
    $result
}

function Unprotect-WormholeSecretBoxInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Key,

        [Parameter(Mandatory = $true)]
        [byte[]] $Ciphertext
    )

    if ($Key.Length -ne 32) { throw 'SecretBox key must be 32 bytes.' }
    if ($Ciphertext.Length -lt 40) { throw 'SecretBox ciphertext too short.' }

    $nonce = [byte[]]::new(24)
    $mac = [byte[]]::new(16)
    $payload = [byte[]]::new($Ciphertext.Length - 40)
    [Array]::Copy($Ciphertext, 0, $nonce, 0, 24)
    [Array]::Copy($Ciphertext, 24, $mac, 0, 16)
    [Array]::Copy($Ciphertext, 40, $payload, 0, $payload.Length)

    $nonce16 = [byte[]]::new(16)
    $nonce8 = [byte[]]::new(8)
    [Array]::Copy($nonce, 0, $nonce16, 0, 16)
    [Array]::Copy($nonce, 16, $nonce8, 0, 8)

    $subKey = Invoke-HSalsa20 -Key $Key -Nonce16 $nonce16
    $firstBlock = Invoke-Salsa20StreamXor -Key $subKey -Nonce8 $nonce8 -Data ([byte[]]::new(64)) -InitialCounter 0
    $polyKey = [byte[]]::new(32)
    [Array]::Copy($firstBlock, 0, $polyKey, 0, 32)

    $calcMac = Invoke-Poly1305Mac -Key $polyKey -Message $payload
    if (-not (Compare-ByteArrays -Left $mac -Right $calcMac)) {
        throw 'SecretBox authentication failed.'
    }

    $plaintext = [byte[]]::new($payload.Length)
    $firstChunk = [Math]::Min($payload.Length, 32)
    for ($index = 0; $index -lt $firstChunk; $index += 1) {
        $plaintext[$index] = $payload[$index] -bxor $firstBlock[32 + $index]
    }
    if ($payload.Length -gt $firstChunk) {
        $remainingLength = $payload.Length - $firstChunk
        $remainingCipher = [byte[]]::new($remainingLength)
        [Array]::Copy($payload, $firstChunk, $remainingCipher, 0, $remainingLength)
        $remainingPlain = Invoke-Salsa20StreamXor -Key $subKey -Nonce8 $nonce8 -Data $remainingCipher -InitialCounter 1
        [Array]::Copy($remainingPlain, 0, $plaintext, $firstChunk, $remainingLength)
    }

    $plaintext
}
