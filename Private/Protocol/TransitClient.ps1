function New-WormholeTransitContext {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $Relay = $script:PowerWormholeDefaults.TransitRelay
    )

    [pscustomobject]@{
        PSTypeName = 'PowerWormhole.TransitContext'
        Relay = $Relay
        Hints = New-WormholeConnectionHints -TransitRelay $Relay
    }
}

function Get-WormholeTransitKey {
    <#
    .SYNOPSIS
        Derives the transit key from the SPAKE2 shared key and application ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $SharedKey,

        [Parameter(Mandatory = $true)]
        [string] $AppId
    )

    $info = [System.Text.Encoding]::ASCII.GetBytes($AppId + '/transit-key')
    Invoke-WormholeHkdfSha256 -InputKeyMaterial $SharedKey -Info $info -Length 32
}

function Get-WormholeTransitRecordKey {
    <#
    .SYNOPSIS
        Derives a per-direction record encryption key from the transit key.
        Direction is either 'sender' or 'receiver'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $TransitKey,

        [Parameter(Mandatory = $true)]
        [ValidateSet('sender', 'receiver')]
        [string] $Direction
    )

    $info = [System.Text.Encoding]::ASCII.GetBytes("transit_record_${Direction}_key")
    Invoke-WormholeHkdfSha256 -InputKeyMaterial $TransitKey -Info $info -Length 32
}

function Get-WormholeTransitHandshakeToken {
    <#
    .SYNOPSIS
        Derives the relay token from the transit key.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $TransitKey
    )

    $info = [System.Text.Encoding]::ASCII.GetBytes('transit_relay_token')
    Invoke-WormholeHkdfSha256 -InputKeyMaterial $TransitKey -Info $info -Length 32
}

function Get-WormholeTransitSideForRelay {
    <#
    .SYNOPSIS
        Produces the relay side identifier required by transit relay handshake
        (16 lowercase hex characters).
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $Side
    )

    if (-not [string]::IsNullOrWhiteSpace($Side) -and $Side -match '^[0-9a-fA-F]{16}$') {
        return $Side.ToLowerInvariant()
    }

    if (-not [string]::IsNullOrWhiteSpace($Side)) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Side))
        }
        finally {
            $sha.Dispose()
        }

        $short = [byte[]]::new(8)
        [Array]::Copy($hash, 0, $short, 0, 8)
        return (ConvertTo-WormholeHex -Bytes $short)
    }

    $random = [byte[]]::new(8)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($random)
    }
    finally {
        $rng.Dispose()
    }
    ConvertTo-WormholeHex -Bytes $random
}

function Get-WormholeTransitPeerHandshake {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $TransitKey,

        [Parameter(Mandatory = $true)]
        [ValidateSet('sender', 'receiver')]
        [string] $Role
    )

    $senderInfo = [System.Text.Encoding]::ASCII.GetBytes('transit_sender')
    $receiverInfo = [System.Text.Encoding]::ASCII.GetBytes('transit_receiver')

    $senderHex = ConvertTo-WormholeHex -Bytes (Invoke-WormholeHkdfSha256 -InputKeyMaterial $TransitKey -Info $senderInfo -Length 32)
    $receiverHex = ConvertTo-WormholeHex -Bytes (Invoke-WormholeHkdfSha256 -InputKeyMaterial $TransitKey -Info $receiverInfo -Length 32)

    if ($Role -eq 'sender') {
        return [pscustomobject]@{
            SendText   = "transit sender $senderHex ready`n`n"
            ExpectText = "transit receiver $receiverHex ready`n`n"
            SendsGo    = $true
        }
    }

    [pscustomobject]@{
        SendText   = "transit receiver $receiverHex ready`n`n"
        ExpectText = "transit sender $senderHex ready`n`n"
        SendsGo    = $false
    }
}

function Invoke-WormholeTransitPeerHandshake {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream] $Stream,

        [Parameter(Mandatory = $true)]
        [byte[]] $TransitKey,

        [Parameter(Mandatory = $true)]
        [ValidateSet('sender', 'receiver')]
        [string] $Role,

        [Parameter()]
        [int] $TimeoutSeconds = 60
    )

    $handshake = Get-WormholeTransitPeerHandshake -TransitKey $TransitKey -Role $Role
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)

    $sendBytes = [System.Text.Encoding]::ASCII.GetBytes($handshake.SendText)
    $Stream.Write($sendBytes, 0, $sendBytes.Length)

    $expectedBytes = [System.Text.Encoding]::ASCII.GetBytes($handshake.ExpectText)
    $receivedBytes = Read-WormholeTransitBytes -Stream $Stream -Count $expectedBytes.Length -Deadline $deadline
    $receivedText = [System.Text.Encoding]::ASCII.GetString($receivedBytes)

    if ($receivedText -ne $handshake.ExpectText) {
        throw "Transit peer handshake mismatch. Expected '$($handshake.ExpectText.Replace("`n", '\\n'))' but received '$($receivedText.Replace("`n", '\\n'))'."
    }

    if ($handshake.SendsGo) {
        $goBytes = [System.Text.Encoding]::ASCII.GetBytes("go`n")
        $Stream.Write($goBytes, 0, $goBytes.Length)
        return
    }

    $goRead = Read-WormholeTransitBytes -Stream $Stream -Count 3 -Deadline $deadline
    $goText = [System.Text.Encoding]::ASCII.GetString($goRead)
    if ($goText -ne "go`n") {
        throw "Transit peer handshake expected 'go\\n' but received '$($goText.Replace("`n", '\\n'))'."
    }
}

function New-WormholeTransitRecordNonce {
    <#
    .SYNOPSIS
        Builds a 24-byte NaCl nonce from a 32-bit sequence counter.
        Bytes 0-19 are zero; bytes 20-23 are the big-endian sequence number.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uint32] $SeqNum
    )

    $nonce = [byte[]]::new(24)
    $nonce[20] = [byte](($SeqNum -shr 24) -band 0xFF)
    $nonce[21] = [byte](($SeqNum -shr 16) -band 0xFF)
    $nonce[22] = [byte](($SeqNum -shr 8) -band 0xFF)
    $nonce[23] = [byte]($SeqNum -band 0xFF)
    $nonce
}

function Read-WormholeTransitBytes {
    <#
    .SYNOPSIS
        Reads exactly Count bytes from a network stream, blocking until all bytes
        arrive or the deadline is exceeded.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream] $Stream,

        [Parameter(Mandatory = $true)]
        [int] $Count,

        [Parameter(Mandatory = $true)]
        [DateTimeOffset] $Deadline
    )

    $buffer = [byte[]]::new($Count)
    $totalRead = 0

    while ($totalRead -lt $Count) {
        if ([DateTimeOffset]::UtcNow -gt $Deadline) {
            throw "Timed out reading $Count bytes from transit stream (got $totalRead)."
        }

        $available = $Count - $totalRead
        $read = $Stream.Read($buffer, $totalRead, $available)

        if ($read -eq 0) {
            throw "Transit stream closed unexpectedly (expected $Count bytes, received $totalRead)."
        }

        $totalRead += $read
    }

    $buffer
}

function Connect-WormholeTransitRelay {
    <#
    .SYNOPSIS
        Connects to a Magic Wormhole transit relay over TCP, performs the relay
        handshake, and returns an open NetworkStream ready for data transfer.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $TransitRelay,

        [Parameter(Mandatory = $true)]
        [byte[]] $TransitKey,

        [Parameter(Mandatory = $true)]
        [string] $Side,

        [Parameter(Mandatory = $true)]
        [ValidateSet('sender', 'receiver')]
        [string] $Role,

        [Parameter()]
        [int] $TimeoutSeconds = 60
    )

    $relayAddress = $TransitRelay -replace '^tcp:', ''
    $parts = $relayAddress.Split(':')
    $hostname = $parts[0]
    $port = [int]$parts[1]

    $relayToken = Get-WormholeTransitHandshakeToken -TransitKey $TransitKey
    $token = ConvertTo-WormholeHex -Bytes $relayToken
    $relaySide = Get-WormholeTransitSideForRelay -Side $Side
    $handshakeText = "please relay $token for side $relaySide`n"
    $handshakeBytes = [System.Text.Encoding]::ASCII.GetBytes($handshakeText)

    Write-WormholeDebug -Component 'transit' -Message 'Connecting to transit relay.' -Data @{ hostname = $hostname; port = $port; side = $relaySide; role = $Role }

    $tcpClient = [System.Net.Sockets.TcpClient]::new()
    $connectTask = $tcpClient.ConnectAsync($hostname, $port)
    if (-not $connectTask.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))) {
        $tcpClient.Dispose()
        throw "Timed out connecting to transit relay $hostname`:$port after $TimeoutSeconds seconds."
    }

    if ($connectTask.IsFaulted) {
        $tcpClient.Dispose()
        throw "Failed to connect to transit relay $hostname`:$port`: $($connectTask.Exception.InnerException.Message)"
    }

    $stream = $tcpClient.GetStream()
    $stream.WriteTimeout = $TimeoutSeconds * 1000
    $stream.ReadTimeout = $TimeoutSeconds * 1000

    Write-WormholeDebug -Component 'transit' -Message 'Sending relay handshake.' -Data @{ handshakeLength = $handshakeBytes.Length }
    $stream.Write($handshakeBytes, 0, $handshakeBytes.Length)

    # Read the relay response up to the first newline.
    $responseBuffer = [System.Collections.Generic.List[byte]]::new()
    $oneByte = [byte[]]::new(1)
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        $read = $stream.Read($oneByte, 0, 1)
        if ($read -eq 0) {
            $tcpClient.Dispose()
            throw 'Transit relay closed connection before responding.'
        }
        $responseBuffer.Add($oneByte[0])
        if ($oneByte[0] -eq [byte][char]"`n") {
            break
        }
        if ($responseBuffer.Count -gt 128) {
            $tcpClient.Dispose()
            throw 'Transit relay response exceeded expected length.'
        }
    }

    $response = [System.Text.Encoding]::ASCII.GetString($responseBuffer.ToArray()).Trim()
    Write-WormholeDebug -Component 'transit' -Message 'Received transit relay response.' -Data @{ response = $response }

    if ($response -ne 'ok') {
        $tcpClient.Dispose()
        throw "Transit relay returned unexpected response: '$response'"
    }

    Invoke-WormholeTransitPeerHandshake -Stream $stream -TransitKey $TransitKey -Role $Role -TimeoutSeconds $TimeoutSeconds

    Write-WormholeDebug -Component 'transit' -Message 'Transit relay connection established.'

    [pscustomobject]@{
        PSTypeName  = 'PowerWormhole.TransitConnection'
        TcpClient   = $tcpClient
        Stream      = $stream
    }
}

function Send-WormholeTransitFile {
    <#
    .SYNOPSIS
        Encrypts and streams a file over an established transit connection,
        then waits for the receiver's SHA-256 acknowledgement record.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Transit,

        [Parameter(Mandatory = $true)]
        [byte[]] $SenderKey,

        [Parameter(Mandatory = $true)]
        [byte[]] $ReceiverKey,

        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter(Mandatory = $true)]
        [long] $FileSize,

        [Parameter()]
        [int] $TimeoutSeconds = 3600,

        [Parameter()]
        [scriptblock] $StatusCallback
    )

    $chunkSize = 32768
    $seqNum = [uint32]0
    $networkStream = $Transit.Stream
    $sha = [System.Security.Cryptography.SHA256]::Create()

    Write-WormholeDebug -Component 'transit' -Message 'Starting file send.' -Data @{ filePath = $FilePath; fileSize = $FileSize }

    $fileStream = [System.IO.File]::OpenRead($FilePath)
    try {
        $buffer = [byte[]]::new($chunkSize)
        $bytesSent = [long]0

        while ($bytesSent -lt $FileSize) {
            $remaining = $FileSize - $bytesSent
            $toRead = [int][Math]::Min($chunkSize, $remaining)
            $bytesRead = 0

            while ($bytesRead -lt $toRead) {
                $count = $fileStream.Read($buffer, $bytesRead, $toRead - $bytesRead)
                if ($count -eq 0) { break }
                $bytesRead += $count
            }

            if ($bytesRead -eq 0) { break }

            $chunk = [byte[]]::new($bytesRead)
            [Array]::Copy($buffer, 0, $chunk, 0, $bytesRead)

            [void]$sha.TransformBlock($chunk, 0, $chunk.Length, $null, 0)

            $nonce = New-WormholeTransitRecordNonce -SeqNum $seqNum
            $boxed = Protect-WormholeSecretBox -Key $SenderKey -Plaintext $chunk -Nonce $nonce

            $lenBytes = [byte[]]@(
                [byte](($boxed.Length -shr 24) -band 0xFF),
                [byte](($boxed.Length -shr 16) -band 0xFF),
                [byte](($boxed.Length -shr 8)  -band 0xFF),
                [byte]($boxed.Length -band 0xFF)
            )
            $networkStream.Write($lenBytes, 0, 4)
            $networkStream.Write($boxed, 0, $boxed.Length)

            $bytesSent += $bytesRead
            $seqNum += 1

            if ($null -ne $StatusCallback) {
                & $StatusCallback "Sending file: $bytesSent / $FileSize bytes"
            }
        }

        # Send empty EOF record.
        $eofNonce = New-WormholeTransitRecordNonce -SeqNum $seqNum
        $eofBoxed = Protect-WormholeSecretBox -Key $SenderKey -Plaintext ([byte[]]::new(0)) -Nonce $eofNonce
        $eofLenBytes = [byte[]]@(
            [byte](($eofBoxed.Length -shr 24) -band 0xFF),
            [byte](($eofBoxed.Length -shr 16) -band 0xFF),
            [byte](($eofBoxed.Length -shr 8)  -band 0xFF),
            [byte]($eofBoxed.Length -band 0xFF)
        )
        $networkStream.Write($eofLenBytes, 0, 4)
        $networkStream.Write($eofBoxed, 0, $eofBoxed.Length)
        $networkStream.Flush()

        Write-WormholeDebug -Component 'transit' -Message 'All file records sent. Waiting for receiver hash acknowledgement.'

        # Wait for receiver's SHA-256 ack record (receiver_key encrypted).
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds(60)
        $ackLenBytes = Read-WormholeTransitBytes -Stream $networkStream -Count 4 -Deadline $deadline
        $ackLen = ([uint32]$ackLenBytes[0] -shl 24) -bor
                  ([uint32]$ackLenBytes[1] -shl 16) -bor
                  ([uint32]$ackLenBytes[2] -shl 8)  -bor
                  [uint32]$ackLenBytes[3]

        $ackCipher = Read-WormholeTransitBytes -Stream $networkStream -Count ([int]$ackLen) -Deadline $deadline
        $ackPlain = Unprotect-WormholeSecretBox -Key $ReceiverKey -Ciphertext $ackCipher
        $ackText = [System.Text.Encoding]::UTF8.GetString($ackPlain)

        [void]$sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
        $fileHash = ConvertTo-WormholeHex -Bytes $sha.Hash
        $ackOk = $false
        $ackSha256 = $null

        try {
            $ackObj = ConvertFrom-Json -InputObject $ackText
            if ($null -ne $ackObj -and $null -ne $ackObj.PSObject.Properties['ack']) {
                $ackOk = ([string]$ackObj.ack -eq 'ok')
            }
            if ($null -ne $ackObj -and $null -ne $ackObj.PSObject.Properties['sha256']) {
                $ackSha256 = [string]$ackObj.sha256
            }
        }
        catch {
            # Back-compat with earlier PowerWormhole receiver implementation.
            $expectedLegacyAck = "file hash: $fileHash`n"
            if ($ackText -eq $expectedLegacyAck) {
                $ackOk = $true
                $ackSha256 = $fileHash
            }
        }

        Write-WormholeDebug -Component 'transit' -Message 'Received acknowledgement from receiver.' -Data @{ ackText = $ackText.Trim(); ackOk = $ackOk; ackSha256 = $ackSha256; expectedSha256 = $fileHash }

        if (-not $ackOk) {
            Write-Warning "Transit acknowledgement was not ok. Receiver response: '$($ackText.Trim())'."
        }
        elseif ($null -ne $ackSha256 -and $ackSha256 -ne $fileHash) {
            Write-Warning "Transit hash mismatch: expected '$fileHash' but got '$ackSha256'."
        }

        if ($null -ne $StatusCallback) {
            & $StatusCallback 'File sent successfully.'
        }

        Write-WormholeDebug -Component 'transit' -Message 'File send complete.'
    }
    finally {
        $sha.Dispose()
        $fileStream.Dispose()
    }
}

function Receive-WormholeTransitFile {
    <#
    .SYNOPSIS
        Receives and decrypts a streamed file over an established transit connection,
        then sends the SHA-256 hash acknowledgement record back to the sender.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Transit,

        [Parameter(Mandatory = $true)]
        [byte[]] $SenderKey,

        [Parameter(Mandatory = $true)]
        [byte[]] $ReceiverKey,

        [Parameter(Mandatory = $true)]
        [string] $OutputPath,

        [Parameter(Mandatory = $true)]
        [long] $ExpectedSize,

        [Parameter()]
        [int] $TimeoutSeconds = 3600,

        [Parameter()]
        [scriptblock] $StatusCallback
    )

    $networkStream = $Transit.Stream
    $seqNum = [uint32]0
    $bytesReceived = [long]0
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $sha = [System.Security.Cryptography.SHA256]::Create()

    Write-WormholeDebug -Component 'transit' -Message 'Starting file receive.' -Data @{ outputPath = $OutputPath; expectedSize = $ExpectedSize }

    $fileStream = [System.IO.File]::Create($OutputPath)
    try {
        while ($bytesReceived -lt $ExpectedSize) {
            $lenBytes = Read-WormholeTransitBytes -Stream $networkStream -Count 4 -Deadline $deadline
            $recordLen = ([uint32]$lenBytes[0] -shl 24) -bor
                         ([uint32]$lenBytes[1] -shl 16) -bor
                         ([uint32]$lenBytes[2] -shl 8)  -bor
                         [uint32]$lenBytes[3]

            # Full SecretBox records include a 24-byte nonce prefix.
            # Empty plaintext record length is 24 + 16 == 40 bytes.
            if ($recordLen -eq 40) {
                $eofCipher = Read-WormholeTransitBytes -Stream $networkStream -Count 40 -Deadline $deadline
                [void](Unprotect-WormholeSecretBox -Key $SenderKey -Ciphertext $eofCipher)
                Write-WormholeDebug -Component 'transit' -Message 'Received EOF record from sender.'
                break
            }

            $cipherRecord = Read-WormholeTransitBytes -Stream $networkStream -Count ([int]$recordLen) -Deadline $deadline
            $plaintext = Unprotect-WormholeSecretBox -Key $SenderKey -Ciphertext $cipherRecord

            [void]$sha.TransformBlock($plaintext, 0, $plaintext.Length, $null, 0)
            $fileStream.Write($plaintext, 0, $plaintext.Length)

            $bytesReceived += $plaintext.Length
            $seqNum += 1

            if ($null -ne $StatusCallback) {
                & $StatusCallback "Receiving file: $bytesReceived / $ExpectedSize bytes"
            }
        }

        $fileStream.Flush()

        # Send SHA-256 ack back to sender (encrypted with receiver key).
        [void]$sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
        $fileHash = ConvertTo-WormholeHex -Bytes $sha.Hash
        $ackPayload = @{ ack = 'ok'; sha256 = $fileHash }
        $ackJson = ConvertTo-Json -InputObject $ackPayload -Depth 5 -Compress
        $ackPlain = [System.Text.Encoding]::UTF8.GetBytes($ackJson)

        $ackNonce = New-WormholeTransitRecordNonce -SeqNum 0
        $ackBoxed = Protect-WormholeSecretBox -Key $ReceiverKey -Plaintext $ackPlain -Nonce $ackNonce
        $ackLenBytes = [byte[]]@(
            [byte](($ackBoxed.Length -shr 24) -band 0xFF),
            [byte](($ackBoxed.Length -shr 16) -band 0xFF),
            [byte](($ackBoxed.Length -shr 8)  -band 0xFF),
            [byte]($ackBoxed.Length -band 0xFF)
        )
        $networkStream.Write($ackLenBytes, 0, 4)
        $networkStream.Write($ackBoxed, 0, $ackBoxed.Length)
        $networkStream.Flush()

        Write-WormholeDebug -Component 'transit' -Message 'File receive complete and hash ack sent.' -Data @{ bytesReceived = $bytesReceived; fileHash = $fileHash }

        if ($null -ne $StatusCallback) {
            & $StatusCallback 'File received successfully.'
        }
    }
    catch {
        $fileStream.Dispose()
        $fileStream = $null
        if (Test-Path -Path $OutputPath -PathType Leaf) {
            Remove-Item -Path $OutputPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        $sha.Dispose()
        if ($null -ne $fileStream) {
            $fileStream.Dispose()
        }
    }
}
