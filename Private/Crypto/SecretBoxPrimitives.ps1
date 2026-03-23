function Initialize-WormholeNaCl {
    [CmdletBinding()]
    param()

    $moduleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $assemblyPath = Join-Path $moduleRoot 'lib\NaCl.Net\NaCl.dll'
    if (-not (Test-Path -Path $assemblyPath)) {
        throw "Required dependency not found: $assemblyPath"
    }

    $loadedAssembly = [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object {
            $_.Location -and [string]::Equals($_.Location, $assemblyPath, [System.StringComparison]::OrdinalIgnoreCase)
        } |
        Select-Object -First 1

    if ($null -eq $loadedAssembly) {
        $script:WormholeNaClAssembly = [System.Reflection.Assembly]::LoadFrom($assemblyPath)
    }
    else {
        $script:WormholeNaClAssembly = $loadedAssembly
    }
}

function Get-WormholeNaClType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $TypeName
    )

    Initialize-WormholeNaCl

    if ($script:WormholeNaClAssembly) {
        $resolved = $script:WormholeNaClAssembly.GetType($TypeName, $false, $false)
        if ($resolved) {
            return $resolved
        }
    }

    foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
        $resolved = $assembly.GetType($TypeName, $false, $false)
        if ($resolved) {
            return $resolved
        }
    }

    throw "Unable to resolve $TypeName type."
}

function New-WormholeNaClSecretBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Key
    )

    $xsalsaType = Get-WormholeNaClType -TypeName 'NaCl.XSalsa20Poly1305'
    $constructor = $xsalsaType.GetConstructor([type[]]@([byte[]]))
    if ($null -eq $constructor) {
        throw 'NaCl.XSalsa20Poly1305(byte[]) constructor was not found.'
    }

    $arguments = [object[]]@(, $Key)
    $constructor.Invoke($arguments)
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

    $polyType = Get-WormholeNaClType -TypeName 'NaCl.Poly1305'

    $poly = [System.Activator]::CreateInstance($polyType)
    try {
        $poly.SetKey($Key, 0)
        if ($Message.Length -gt 0) {
            $poly.Update($Message, 0, $Message.Length)
        }

        $tag = [byte[]]::new(16)
        $poly.Final($tag)
        return $tag
    }
    finally {
        if ($poly -is [System.IDisposable]) {
            $poly.Dispose()
        }
    }
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

    if ($Key.Length -ne 32) {
        throw 'SecretBox key must be 32 bytes.'
    }

    if ($Nonce.Length -ne 24) {
        throw 'SecretBox nonce must be 24 bytes.'
    }

    if ($null -eq $Plaintext) {
        $Plaintext = [byte[]]::new(0)
    }

    $secretBox = New-WormholeNaClSecretBox -Key $Key
    try {
        $boxed = [byte[]]::new($Plaintext.Length + 16)
        $secretBox.Encrypt($boxed, 0, $Plaintext, 0, $Plaintext.Length, $Nonce, 0)

        $result = [byte[]]::new(24 + $boxed.Length)
        [Array]::Copy($Nonce, 0, $result, 0, 24)
        [Array]::Copy($boxed, 0, $result, 24, $boxed.Length)
        return $result
    }
    finally {
        if ($secretBox -is [System.IDisposable]) {
            $secretBox.Dispose()
        }
    }
}

function Unprotect-WormholeSecretBoxInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Key,

        [Parameter(Mandatory = $true)]
        [byte[]] $Ciphertext
    )

    if ($Key.Length -ne 32) {
        throw 'SecretBox key must be 32 bytes.'
    }

    if ($Ciphertext.Length -lt 40) {
        throw 'SecretBox ciphertext must be at least 40 bytes (24 nonce + 16 mac).'
    }

    $nonce = [byte[]]::new(24)
    [Array]::Copy($Ciphertext, 0, $nonce, 0, 24)

    $boxedLength = $Ciphertext.Length - 24
    $boxed = [byte[]]::new($boxedLength)
    [Array]::Copy($Ciphertext, 24, $boxed, 0, $boxedLength)

    $plaintext = [byte[]]::new($boxedLength - 16)

    $secretBox = New-WormholeNaClSecretBox -Key $Key
    try {
        $ok = $secretBox.TryDecrypt($plaintext, 0, $boxed, 0, $boxed.Length, $nonce, 0)
        if (-not $ok) {
            throw 'SecretBox authentication failed.'
        }

        return $plaintext
    }
    finally {
        if ($secretBox -is [System.IDisposable]) {
            $secretBox.Dispose()
        }
    }
}
