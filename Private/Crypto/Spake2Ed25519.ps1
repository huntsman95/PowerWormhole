$script:Ed25519Q = [System.Numerics.BigInteger]::Pow([System.Numerics.BigInteger]2, 255) - 19
$script:Ed25519L = [System.Numerics.BigInteger]::Pow([System.Numerics.BigInteger]2, 252) + [System.Numerics.BigInteger]::Parse('27742317777372353535851937790883648493')
$script:Ed25519I = [System.Numerics.BigInteger]::ModPow(2, ($script:Ed25519Q - 1) / 4, $script:Ed25519Q)
$script:Spake2SymmetricSeed = [System.Text.Encoding]::ASCII.GetBytes('symmetric')
$script:Ed25519Initialized = $false

function New-Ed25519Element {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Numerics.BigInteger] $X,

        [Parameter(Mandatory = $true)]
        [System.Numerics.BigInteger] $Y,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Unknown', 'Element', 'Zero')]
        [string] $Kind
    )

    $z = 1
    $t = ($X * $Y) % $script:Ed25519Q
    if ($t -lt 0) { $t += $script:Ed25519Q }

    [pscustomobject]@{
        PSTypeName = 'PowerWormhole.Ed25519Element'
        X = ($X % $script:Ed25519Q + $script:Ed25519Q) % $script:Ed25519Q
        Y = ($Y % $script:Ed25519Q + $script:Ed25519Q) % $script:Ed25519Q
        Z = [System.Numerics.BigInteger]$z
        T = $t
        Kind = $Kind
    }
}

function Invoke-Ed25519Inverse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Numerics.BigInteger] $Value
    )

    $normalized = ($Value % $script:Ed25519Q + $script:Ed25519Q) % $script:Ed25519Q
    [System.Numerics.BigInteger]::ModPow($normalized, $script:Ed25519Q - 2, $script:Ed25519Q)
}

function Get-Ed25519XRecover {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Numerics.BigInteger] $Y
    )

    $yy = ($Y * $Y) % $script:Ed25519Q
    $numerator = ($yy - 1) % $script:Ed25519Q
    $denominator = ($script:Ed25519D * $yy + 1) % $script:Ed25519Q
    if ($numerator -lt 0) { $numerator += $script:Ed25519Q }
    if ($denominator -lt 0) { $denominator += $script:Ed25519Q }

    $xx = ($numerator * (Invoke-Ed25519Inverse $denominator)) % $script:Ed25519Q
    $x = [System.Numerics.BigInteger]::ModPow($xx, ($script:Ed25519Q + 3) / 8, $script:Ed25519Q)

    $check = (($x * $x) - $xx) % $script:Ed25519Q
    if ($check -lt 0) { $check += $script:Ed25519Q }
    if ($check -ne 0) {
        $x = ($x * $script:Ed25519I) % $script:Ed25519Q
    }

    if (($x % 2) -ne 0) {
        $x = $script:Ed25519Q - $x
    }

    ($x % $script:Ed25519Q + $script:Ed25519Q) % $script:Ed25519Q
}

function Test-Ed25519OnCurve {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Numerics.BigInteger] $X,

        [Parameter(Mandatory = $true)]
        [System.Numerics.BigInteger] $Y
    )

    $lhs = ((-$X * $X) + ($Y * $Y) - 1 - ($script:Ed25519D * $X * $X * $Y * $Y)) % $script:Ed25519Q
    if ($lhs -lt 0) { $lhs += $script:Ed25519Q }
    $lhs -eq 0
}

function Get-Ed25519AffineFromExtended {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Element
    )

    $zInv = Invoke-Ed25519Inverse $Element.Z
    $x = ($Element.X * $zInv) % $script:Ed25519Q
    $y = ($Element.Y * $zInv) % $script:Ed25519Q
    if ($x -lt 0) { $x += $script:Ed25519Q }
    if ($y -lt 0) { $y += $script:Ed25519Q }

    [pscustomobject]@{
        X = $x
        Y = $y
    }
}

function Invoke-Ed25519Double {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Element
    )

    $x1 = $Element.X
    $y1 = $Element.Y
    $z1 = $Element.Z

    $a = ($x1 * $x1) % $script:Ed25519Q
    $b = ($y1 * $y1) % $script:Ed25519Q
    $c = (2 * $z1 * $z1) % $script:Ed25519Q
    $d = (-$a) % $script:Ed25519Q
    $j = ($x1 + $y1) % $script:Ed25519Q
    $e = ($j * $j - $a - $b) % $script:Ed25519Q
    $g = ($d + $b) % $script:Ed25519Q
    $f = ($g - $c) % $script:Ed25519Q
    $h = ($d - $b) % $script:Ed25519Q
    $x3 = ($e * $f) % $script:Ed25519Q
    $y3 = ($g * $h) % $script:Ed25519Q
    $z3 = ($f * $g) % $script:Ed25519Q
    $t3 = ($e * $h) % $script:Ed25519Q

    if ($x3 -lt 0) { $x3 += $script:Ed25519Q }
    if ($y3 -lt 0) { $y3 += $script:Ed25519Q }
    if ($z3 -lt 0) { $z3 += $script:Ed25519Q }
    if ($t3 -lt 0) { $t3 += $script:Ed25519Q }

    [pscustomobject]@{
        PSTypeName = 'PowerWormhole.Ed25519Element'
        X = $x3
        Y = $y3
        Z = $z3
        T = $t3
        Kind = 'Unknown'
    }
}

function Invoke-Ed25519Add {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Left,

        [Parameter(Mandatory = $true)]
        [pscustomobject] $Right
    )

    if ($Left.Kind -eq 'Zero') { return $Right }
    if ($Right.Kind -eq 'Zero') { return $Left }

    $x1 = $Left.X
    $y1 = $Left.Y
    $z1 = $Left.Z
    $t1 = $Left.T

    $x2 = $Right.X
    $y2 = $Right.Y
    $z2 = $Right.Z
    $t2 = $Right.T

    $a = (($y1 - $x1) * ($y2 - $x2)) % $script:Ed25519Q
    $b = (($y1 + $x1) * ($y2 + $x2)) % $script:Ed25519Q
    $c = ($t1 * (2 * $script:Ed25519D) * $t2) % $script:Ed25519Q
    $d = ($z1 * 2 * $z2) % $script:Ed25519Q
    $e = ($b - $a) % $script:Ed25519Q
    $f = ($d - $c) % $script:Ed25519Q
    $g = ($d + $c) % $script:Ed25519Q
    $h = ($b + $a) % $script:Ed25519Q
    $x3 = ($e * $f) % $script:Ed25519Q
    $y3 = ($g * $h) % $script:Ed25519Q
    $z3 = ($f * $g) % $script:Ed25519Q
    $t3 = ($e * $h) % $script:Ed25519Q

    if ($x3 -lt 0) { $x3 += $script:Ed25519Q }
    if ($y3 -lt 0) { $y3 += $script:Ed25519Q }
    if ($z3 -lt 0) { $z3 += $script:Ed25519Q }
    if ($t3 -lt 0) { $t3 += $script:Ed25519Q }

    $candidate = [pscustomobject]@{
        PSTypeName = 'PowerWormhole.Ed25519Element'
        X = $x3
        Y = $y3
        Z = $z3
        T = $t3
        Kind = 'Unknown'
    }

    if (Test-Ed25519IsExtendedZero -Element $candidate) {
        return $script:Ed25519Zero
    }

    $candidate
}

function Invoke-Ed25519ScalarMultSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Element,

        [Parameter(Mandatory = $true)]
        [System.Numerics.BigInteger] $Scalar
    )

    if ($Scalar -lt 0) {
        throw 'Safe scalar multiplication requires non-negative scalar.'
    }

    if ($Scalar -eq 0) {
        return $script:Ed25519Zero
    }

    $half = Invoke-Ed25519ScalarMultSafe -Element $Element -Scalar ($Scalar / 2)
    $doubled = Invoke-Ed25519Double -Element $half
    if (($Scalar % 2) -ne 0) {
        return Invoke-Ed25519Add -Left $doubled -Right $Element
    }

    $doubled
}

function Invoke-Ed25519ScalarMult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Element,

        [Parameter(Mandatory = $true)]
        [System.Numerics.BigInteger] $Scalar
    )

    if ($Element.Kind -eq 'Zero') {
        return $script:Ed25519Zero
    }

    if ($Element.Kind -eq 'Element') {
        $s = (($Scalar % $script:Ed25519L) + $script:Ed25519L) % $script:Ed25519L
        if ($s -eq 0) {
            return $script:Ed25519Zero
        }
        return ConvertTo-Ed25519Element -Element (Invoke-Ed25519ScalarMultSafe -Element $Element -Scalar $s)
    }

    if ($Scalar -lt 0) {
        throw 'Unknown-group scalar multiplication requires non-negative scalar.'
    }

    Invoke-Ed25519ScalarMultSafe -Element $Element -Scalar $Scalar
}

function ConvertTo-Ed25519PointBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Element
    )

    $affine = Get-Ed25519AffineFromExtended -Element $Element
    $x = $affine.X
    $y = $affine.Y

    if (($x % 2) -ne 0) {
        $y = $y + [System.Numerics.BigInteger]::Pow([System.Numerics.BigInteger]2, 255)
    }

    ConvertTo-BigIntegerLittleEndianBytes -Value $y -Length 32
}

function ConvertFrom-Ed25519PointBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Bytes
    )

    if ($Bytes.Length -ne 32) {
        throw 'Ed25519 point encoding must be 32 bytes.'
    }

    if ((Compare-ByteArrays -Left $Bytes -Right $script:Ed25519ZeroBytes)) {
        return $script:Ed25519Zero
    }

    $unclamped = ConvertFrom-BigIntegerLittleEndianBytes -Bytes $Bytes
    $clamp = [System.Numerics.BigInteger]::Pow([System.Numerics.BigInteger]2, 255) - 1
    $y = $unclamped -band $clamp
    $x = Get-Ed25519XRecover -Y $y
    $signBit = ($unclamped -band ([System.Numerics.BigInteger]::Pow([System.Numerics.BigInteger]2, 255))) -ne 0
    if ((($x -band 1) -ne 0) -ne $signBit) {
        $x = $script:Ed25519Q - $x
    }

    if (-not (Test-Ed25519OnCurve -X $x -Y $y)) {
        throw 'Decoded point is not on Ed25519 curve.'
    }

    New-Ed25519Element -X $x -Y $y -Kind 'Unknown'
}

function ConvertTo-Ed25519Element {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Element
    )

    if ($Element.Kind -eq 'Zero') {
        throw 'Element was Zero.'
    }

    $scaled = Invoke-Ed25519ScalarMultSafe -Element $Element -Scalar $script:Ed25519L
    if (-not (Test-Ed25519IsExtendedZero -Element $scaled)) {
        throw 'Element is not in the right subgroup.'
    }

    [pscustomobject]@{
        PSTypeName = 'PowerWormhole.Ed25519Element'
        X = $Element.X
        Y = $Element.Y
        Z = $Element.Z
        T = $Element.T
        Kind = 'Element'
    }
}

function Test-Ed25519IsExtendedZero {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Element
    )

    $x = (($Element.X % $script:Ed25519Q) + $script:Ed25519Q) % $script:Ed25519Q
    $y = (($Element.Y % $script:Ed25519Q) + $script:Ed25519Q) % $script:Ed25519Q
    $z = (($Element.Z % $script:Ed25519Q) + $script:Ed25519Q) % $script:Ed25519Q

    ($x -eq 0) -and ($y -eq $z) -and ($y -ne 0)
}

function ConvertTo-BigIntegerLittleEndianBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Numerics.BigInteger] $Value,

        [Parameter(Mandatory = $true)]
        [int] $Length
    )

    $normalized = ($Value % [System.Numerics.BigInteger]::Pow([System.Numerics.BigInteger]2, 8 * $Length) + [System.Numerics.BigInteger]::Pow([System.Numerics.BigInteger]2, 8 * $Length)) % [System.Numerics.BigInteger]::Pow([System.Numerics.BigInteger]2, 8 * $Length)
    $buffer = [byte[]]::new($Length)
    $working = $normalized

    for ($index = 0; $index -lt $Length; $index += 1) {
        $buffer[$index] = [byte]($working -band 0xff)
        $working = $working / 256
    }

    $buffer
}

function ConvertFrom-BigIntegerLittleEndianBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Bytes
    )

    $value = [System.Numerics.BigInteger]::Zero
    for ($index = $Bytes.Length - 1; $index -ge 0; $index -= 1) {
        $value = ($value * 256) + $Bytes[$index]
    }

    $value
}

function ConvertFrom-BigIntegerBigEndianBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Bytes
    )

    $value = [System.Numerics.BigInteger]::Zero
    for ($index = 0; $index -lt $Bytes.Length; $index += 1) {
        $value = ($value * 256) + $Bytes[$index]
    }

    $value
}

function Compare-ByteArrays {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Left,

        [Parameter(Mandatory = $true)]
        [byte[]] $Right
    )

    if ($Left.Length -ne $Right.Length) {
        return $false
    }

    $diff = 0
    for ($index = 0; $index -lt $Left.Length; $index += 1) {
        $diff = $diff -bor ($Left[$index] -bxor $Right[$index])
    }

    $diff -eq 0
}

function Get-Spake2PasswordScalar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Password
    )

    $expanded = Invoke-WormholeHkdfSha256 -InputKeyMaterial $Password -Length 48 -Salt ([byte[]]::new(0)) -Info ([System.Text.Encoding]::ASCII.GetBytes('SPAKE2 pw'))
    $i = ConvertFrom-BigIntegerBigEndianBytes -Bytes $expanded
    $i % $script:Ed25519L
}

function Get-Spake2ArbitraryElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Seed
    )

    $expanded = Invoke-WormholeHkdfSha256 -InputKeyMaterial $Seed -Length 48 -Salt ([byte[]]::new(0)) -Info ([System.Text.Encoding]::ASCII.GetBytes('SPAKE2 arbitrary element'))
    $y = (ConvertFrom-BigIntegerBigEndianBytes -Bytes $expanded) % $script:Ed25519Q
    $plus = [System.Numerics.BigInteger]::Zero

    while ($true) {
        $yPlus = ($y + $plus) % $script:Ed25519Q
        $x = Get-Ed25519XRecover -Y $yPlus
        if (-not (Test-Ed25519OnCurve -X $x -Y $yPlus)) {
            $plus += 1
            continue
        }

        $candidate = New-Ed25519Element -X $x -Y $yPlus -Kind 'Unknown'
        $p8 = Invoke-Ed25519ScalarMultSafe -Element $candidate -Scalar 8
        if (Test-Ed25519IsExtendedZero -Element $p8) {
            $plus += 1
            continue
        }

        $check = Invoke-Ed25519ScalarMultSafe -Element $p8 -Scalar $script:Ed25519L
        if (-not (Test-Ed25519IsExtendedZero -Element $check)) {
            $plus += 1
            continue
        }

        return ConvertTo-Ed25519Element -Element $p8
    }
}

function New-Spake2SymmetricContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Password,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]] $IdSymmetric,

        [Parameter(Mandatory = $true)]
        [byte[]] $RandomBytes
    )

    if ($RandomBytes.Length -lt 64) {
        throw 'SPAKE2 requires at least 64 random bytes for scalar generation.'
    }

    $oversized = [byte[]]::new(64)
    [Array]::Copy($RandomBytes, 0, $oversized, 0, 64)
    $xyScalar = (ConvertFrom-BigIntegerBigEndianBytes -Bytes $oversized) % $script:Ed25519L
    $pwScalar = Get-Spake2PasswordScalar -Password $Password
    $sElement = Get-Spake2ArbitraryElement -Seed $script:Spake2SymmetricSeed

    $xyElem = Invoke-Ed25519ScalarMult -Element $script:Ed25519Base -Scalar $xyScalar
    $pwBlinding = Invoke-Ed25519ScalarMult -Element $sElement -Scalar $pwScalar
    $messageElem = Invoke-Ed25519Add -Left $xyElem -Right $pwBlinding
    $outboundMessage = ConvertTo-Ed25519PointBytes -Element $messageElem

    $wireMessage = [byte[]]::new(33)
    $wireMessage[0] = 0x53
    [Array]::Copy($outboundMessage, 0, $wireMessage, 1, 32)

    [pscustomobject]@{
        PSTypeName = 'PowerWormhole.Spake2SymmetricContext'
        Password = $Password
        IdSymmetric = $IdSymmetric
        PasswordScalar = $pwScalar
        XYScalar = $xyScalar
        SElement = $sElement
        OutboundMessage = $outboundMessage
        Message = $wireMessage
    }
}

function Complete-Spake2Symmetric {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Context,

        [Parameter(Mandatory = $true)]
        [byte[]] $InboundSideAndMessage
    )

    if ($InboundSideAndMessage.Length -ne 33) {
        throw 'Inbound SPAKE2 message must be 33 bytes.'
    }

    $otherSide = $InboundSideAndMessage[0]
    if ($otherSide -ne 0x53) {
        throw 'Inbound SPAKE2 message has invalid side marker.'
    }

    $inboundMessage = [byte[]]::new(32)
    [Array]::Copy($InboundSideAndMessage, 1, $inboundMessage, 0, 32)

    $inboundElem = ConvertTo-Ed25519Element -Element (ConvertFrom-Ed25519PointBytes -Bytes $inboundMessage)
    if (Compare-ByteArrays -Left (ConvertTo-Ed25519PointBytes -Element $inboundElem) -Right $Context.OutboundMessage) {
        throw 'SPAKE2 reflection detected.'
    }

    $pwUnblinding = Invoke-Ed25519ScalarMult -Element $Context.SElement -Scalar (-$Context.PasswordScalar)
    $kElem = Invoke-Ed25519ScalarMult -Element (Invoke-Ed25519Add -Left $inboundElem -Right $pwUnblinding) -Scalar $Context.XYScalar
    $kBytes = ConvertTo-Ed25519PointBytes -Element $kElem

    $first = $inboundMessage
    $second = $Context.OutboundMessage
    $firstHex = ConvertTo-WormholeHex -Bytes $first
    $secondHex = ConvertTo-WormholeHex -Bytes $second
    if ([string]::CompareOrdinal($firstHex, $secondHex) -gt 0) {
        $tmp = $first
        $first = $second
        $second = $tmp
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $transcript = [System.Collections.Generic.List[byte]]::new()
        [byte[]]$hPw = $sha.ComputeHash([byte[]]$Context.Password)
        [byte[]]$hId = $sha.ComputeHash([byte[]]$Context.IdSymmetric)
        [byte[]]$firstBytes = $first
        [byte[]]$secondBytes = $second
        [byte[]]$kMaterial = $kBytes
        $transcript.AddRange($hPw)
        $transcript.AddRange($hId)
        $transcript.AddRange($firstBytes)
        $transcript.AddRange($secondBytes)
        $transcript.AddRange($kMaterial)
        $sharedKey = $sha.ComputeHash($transcript.ToArray())
    }
    finally {
        $sha.Dispose()
    }

    [pscustomobject]@{
        PSTypeName = 'PowerWormhole.Spake2Result'
        SharedKey = $sharedKey
        InboundMessage = $inboundMessage
        OutboundMessage = $Context.OutboundMessage
    }
}

function Initialize-Ed25519Statics {
    [CmdletBinding()]
    param()

    if ($script:Ed25519Initialized) {
        return
    }

    $script:Ed25519D = ((-121665) * (Invoke-Ed25519Inverse 121666)) % $script:Ed25519Q
    if ($script:Ed25519D -lt 0) { $script:Ed25519D += $script:Ed25519Q }
    $script:Ed25519By = (4 * (Invoke-Ed25519Inverse 5)) % $script:Ed25519Q
    $script:Ed25519Bx = Get-Ed25519XRecover -Y $script:Ed25519By
    $script:Ed25519Base = New-Ed25519Element -X $script:Ed25519Bx -Y $script:Ed25519By -Kind 'Element'
    $script:Ed25519Zero = New-Ed25519Element -X 0 -Y 1 -Kind 'Zero'
    $script:Ed25519ZeroBytes = ConvertTo-Ed25519PointBytes -Element $script:Ed25519Zero
    $script:Ed25519Initialized = $true
}

Initialize-Ed25519Statics
