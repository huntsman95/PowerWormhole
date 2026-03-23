function Initialize-WormholePake {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session
    )

    Write-WormholeDebug -Component 'protocol' -Message 'Initializing SPAKE2 context.' -Session $Session -Data @{ appId = $Session.AppId }
    Start-WormholeSpake2 -Code $Session.Code -AppId $Session.AppId
}

function Invoke-WormholeStatus {
    [CmdletBinding()]
    param(
        [Parameter()]
        [scriptblock] $StatusCallback,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if ($null -ne $StatusCallback) {
        & $StatusCallback $Message
    }
}

function Invoke-WormholeTextSendProtocol {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session,

        [Parameter(Mandatory = $true)]
        [string] $Text,

        [Parameter()]
        [int] $TimeoutSeconds = 300,

        [Parameter()]
        [scriptblock] $StatusCallback
    )

    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Starting key exchange...'
    Write-WormholeDebug -Component 'protocol' -Message 'Text send protocol started.' -Session $Session -Data @{ timeoutSeconds = $TimeoutSeconds; textLength = $Text.Length }
    $pakeContext = Initialize-WormholePake -Session $Session

    $pakeEnvelope = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ pake_v1 = (ConvertTo-WormholeHex -Bytes $pakeContext.Message) } -Depth 5 -Compress))
    Add-WormholeMailboxPayload -Session $Session -Phase 'pake' -Body $pakeEnvelope
    Write-WormholeDebug -Component 'protocol' -Message 'Sent PAKE payload.' -Session $Session -Data @{ bytes = $pakeEnvelope.Length }
    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Waiting for peer to join and exchange PAKE...'

    $peerPake = Receive-WormholeMailboxPayload -Session $Session -Phase 'pake' -TimeoutSeconds $TimeoutSeconds
    Write-WormholeDebug -Component 'protocol' -Message 'Received peer PAKE payload.' -Session $Session -Data @{ side = $peerPake.Side; bytes = $peerPake.Body.Length }
    $peerPakeJson = [System.Text.Encoding]::UTF8.GetString($peerPake.Body)
    $peerPakeObject = ConvertFrom-Json -InputObject $peerPakeJson
    $peerPakeBytes = ConvertFrom-WormholeHex -Hex ([string]$peerPakeObject.pake_v1)
    $result = Complete-WormholeSpake2 -Context $pakeContext -PeerMessage $peerPakeBytes
    Write-WormholeDebug -Component 'protocol' -Message 'Completed SPAKE2 and derived shared key.' -Session $Session -Data @{ sharedKeyLength = $result.SharedKey.Length }

    $versionPayload = @{
        app_versions = @{ 'PowerWormhole' = '0.1.0' }
    }
    $versionBytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $versionPayload -Depth 10 -Compress))
    $versionKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $Session.Side -Phase 'version'
    $cipherVersion = Protect-WormholeSecretBox -Key $versionKey -Plaintext $versionBytes
    Add-WormholeMailboxPayload -Session $Session -Phase 'version' -Body $cipherVersion
    Write-WormholeDebug -Component 'protocol' -Message 'Sent encrypted version payload.' -Session $Session -Data @{ plainBytes = $versionBytes.Length; cipherBytes = $cipherVersion.Length }
    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'PAKE complete. Verifying peer version...'

    $peerVersion = Receive-WormholeMailboxPayload -Session $Session -Phase 'version' -TimeoutSeconds $TimeoutSeconds
    Write-WormholeDebug -Component 'protocol' -Message 'Received encrypted peer version payload.' -Session $Session -Data @{ side = $peerVersion.Side; bytes = $peerVersion.Body.Length }
    $peerVersionKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $peerVersion.Side -Phase 'version'
    [void](Unprotect-WormholeSecretBox -Key $peerVersionKey -Ciphertext $peerVersion.Body)
    Write-WormholeDebug -Component 'protocol' -Message 'Peer version decrypted successfully.' -Session $Session

    $phase = [string]$Session.NextPhase
    $plaintext = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ offer = @{ message = $Text } } -Depth 10 -Compress))
    $phaseKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $Session.Side -Phase $phase
    $cipher = Protect-WormholeSecretBox -Key $phaseKey -Plaintext $plaintext
    Add-WormholeMailboxPayload -Session $Session -Phase $phase -Body $cipher
    Write-WormholeDebug -Component 'protocol' -Message 'Sent encrypted offer payload.' -Session $Session -Data @{ phase = $phase; plainBytes = $plaintext.Length; cipherBytes = $cipher.Length }

    $Session.NextPhase += 1
    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Offer sent. Waiting for receiver acknowledgement...'

    while ($true) {
        $incoming = Receive-WormholeMailboxPayload -Session $Session -TimeoutSeconds $TimeoutSeconds
        Write-WormholeDebug -Component 'protocol' -Message 'Received post-offer response candidate.' -Session $Session -Data @{ phase = $incoming.Phase; side = $incoming.Side; bytes = $incoming.Body.Length }
        if ($incoming.Phase -notmatch '^\d+$') {
            Write-WormholeDebug -Component 'protocol' -Message 'Skipping non-numeric post-offer message.' -Session $Session -Data @{ phase = $incoming.Phase }
            continue
        }

        $incomingKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $incoming.Side -Phase $incoming.Phase
        $incomingPlainBytes = Unprotect-WormholeSecretBox -Key $incomingKey -Ciphertext $incoming.Body
        $incomingText = [System.Text.Encoding]::UTF8.GetString($incomingPlainBytes)
        $incomingObject = ConvertFrom-Json -InputObject $incomingText

        if ($null -ne $incomingObject.PSObject.Properties['error'] -and $null -ne $incomingObject.error) {
            throw "Peer reported transfer error: $($incomingObject.error)"
        }

        $answerProp = $incomingObject.PSObject.Properties['answer']
        if ($null -ne $answerProp -and $null -ne $answerProp.Value -and
            $null -ne $answerProp.Value.PSObject.Properties['message_ack'] -and
            [string]$answerProp.Value.message_ack -eq 'ok') {
            Write-WormholeDebug -Component 'protocol' -Message 'Received message acknowledgement from receiver.' -Session $Session -Data @{ phase = $incoming.Phase }
            break
        }

        Write-WormholeDebug -Component 'protocol' -Message 'Post-offer response did not contain message acknowledgement.' -Session $Session -Data @{ phase = $incoming.Phase }
    }

    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Text message sent.'
    Write-WormholeDebug -Component 'protocol' -Message 'Text send protocol complete.' -Session $Session
}

function Invoke-WormholeTextReceiveProtocol {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session,

        [Parameter()]
        [int] $TimeoutSeconds = 300,

        [Parameter()]
        [scriptblock] $StatusCallback
    )

    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Starting key exchange...'
    Write-WormholeDebug -Component 'protocol' -Message 'Text receive protocol started.' -Session $Session -Data @{ timeoutSeconds = $TimeoutSeconds }
    $pakeContext = Initialize-WormholePake -Session $Session

    $pakeEnvelope = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ pake_v1 = (ConvertTo-WormholeHex -Bytes $pakeContext.Message) } -Depth 5 -Compress))
    Add-WormholeMailboxPayload -Session $Session -Phase 'pake' -Body $pakeEnvelope
    Write-WormholeDebug -Component 'protocol' -Message 'Sent PAKE payload.' -Session $Session -Data @{ bytes = $pakeEnvelope.Length }
    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Waiting for peer PAKE message...'
    $peerPake = Receive-WormholeMailboxPayload -Session $Session -Phase 'pake' -TimeoutSeconds $TimeoutSeconds
    Write-WormholeDebug -Component 'protocol' -Message 'Received peer PAKE payload.' -Session $Session -Data @{ side = $peerPake.Side; bytes = $peerPake.Body.Length }
    $peerPakeJson = [System.Text.Encoding]::UTF8.GetString($peerPake.Body)
    $peerPakeObject = ConvertFrom-Json -InputObject $peerPakeJson
    $peerPakeBytes = ConvertFrom-WormholeHex -Hex ([string]$peerPakeObject.pake_v1)
    $result = Complete-WormholeSpake2 -Context $pakeContext -PeerMessage $peerPakeBytes
    Write-WormholeDebug -Component 'protocol' -Message 'Completed SPAKE2 and derived shared key.' -Session $Session -Data @{ sharedKeyLength = $result.SharedKey.Length }

    $versionPayload = @{
        app_versions = @{ 'PowerWormhole' = '0.1.0' }
    }
    $versionBytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $versionPayload -Depth 10 -Compress))
    $versionKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $Session.Side -Phase 'version'
    $cipherVersion = Protect-WormholeSecretBox -Key $versionKey -Plaintext $versionBytes
    Add-WormholeMailboxPayload -Session $Session -Phase 'version' -Body $cipherVersion
    Write-WormholeDebug -Component 'protocol' -Message 'Sent encrypted version payload.' -Session $Session -Data @{ plainBytes = $versionBytes.Length; cipherBytes = $cipherVersion.Length }

    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'PAKE complete. Verifying peer version...'
    $peerVersion = Receive-WormholeMailboxPayload -Session $Session -Phase 'version' -TimeoutSeconds $TimeoutSeconds
    Write-WormholeDebug -Component 'protocol' -Message 'Received encrypted peer version payload.' -Session $Session -Data @{ side = $peerVersion.Side; bytes = $peerVersion.Body.Length }
    $peerVersionKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $peerVersion.Side -Phase 'version'
    [void](Unprotect-WormholeSecretBox -Key $peerVersionKey -Ciphertext $peerVersion.Body)
    Write-WormholeDebug -Component 'protocol' -Message 'Peer version decrypted successfully.' -Session $Session
    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Waiting for inbound text message...'

    while ($true) {
        $incoming = Receive-WormholeMailboxPayload -Session $Session -TimeoutSeconds $TimeoutSeconds
        Write-WormholeDebug -Component 'protocol' -Message 'Received application-phase candidate message.' -Session $Session -Data @{ phase = $incoming.Phase; side = $incoming.Side; bytes = $incoming.Body.Length }
        if ($incoming.Phase -notmatch '^\d+$') {
            Write-WormholeDebug -Component 'protocol' -Message 'Skipping non-numeric phase message.' -Session $Session -Data @{ phase = $incoming.Phase }
            continue
        }

        $incomingKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $incoming.Side -Phase $incoming.Phase
        $plainBytes = Unprotect-WormholeSecretBox -Key $incomingKey -Ciphertext $incoming.Body
        $text = [System.Text.Encoding]::UTF8.GetString($plainBytes)
        Write-WormholeDebug -Component 'protocol' -Message 'Decrypted application payload.' -Session $Session -Data @{ phase = $incoming.Phase; plainBytes = $plainBytes.Length }
        $obj = ConvertFrom-Json -InputObject $text

        if ($null -ne $obj.PSObject.Properties['error'] -and $null -ne $obj.error) {
            throw "Peer reported transfer error: $($obj.error)"
        }

        $offerProp = $obj.PSObject.Properties['offer']
        if ($null -ne $offerProp -and $null -ne $offerProp.Value -and
            $null -ne $offerProp.Value.PSObject.Properties['message'] -and
            $null -ne $offerProp.Value.message) {
            $messageText = [string]$offerProp.Value.message
            Write-WormholeDebug -Component 'protocol' -Message 'Offer.message extracted successfully.' -Session $Session -Data @{ messageLength = $messageText.Length }

            $answerPhase = [string]$Session.NextPhase
            $answerPayload = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ answer = @{ message_ack = 'ok' } } -Depth 10 -Compress))
            $answerKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $Session.Side -Phase $answerPhase
            $answerCipher = Protect-WormholeSecretBox -Key $answerKey -Plaintext $answerPayload
            Add-WormholeMailboxPayload -Session $Session -Phase $answerPhase -Body $answerCipher
            $Session.NextPhase += 1
            Write-WormholeDebug -Component 'protocol' -Message 'Sent message acknowledgement to sender.' -Session $Session -Data @{ phase = $answerPhase }

            Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Text message received.'
            return $messageText
        }

        Write-WormholeDebug -Component 'protocol' -Message 'Application payload did not contain offer.message; continuing wait.' -Session $Session
    }
}

function Invoke-WormholeReceiveProtocol {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session,

        [Parameter()]
        [string] $OutputDirectory = (Get-Location).Path,

        [Parameter()]
        [int] $TimeoutSeconds = 300,

        [Parameter()]
        [scriptblock] $StatusCallback
    )

    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Starting key exchange...'
    Write-WormholeDebug -Component 'protocol' -Message 'Unified receive protocol started.' -Session $Session -Data @{ timeoutSeconds = $TimeoutSeconds; outputDirectory = $OutputDirectory }

    $pakeContext = Initialize-WormholePake -Session $Session
    $pakeEnvelope = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ pake_v1 = (ConvertTo-WormholeHex -Bytes $pakeContext.Message) } -Depth 5 -Compress))
    Add-WormholeMailboxPayload -Session $Session -Phase 'pake' -Body $pakeEnvelope

    $peerPake = Receive-WormholeMailboxPayload -Session $Session -Phase 'pake' -TimeoutSeconds $TimeoutSeconds
    $peerPakeObject = ConvertFrom-Json -InputObject ([System.Text.Encoding]::UTF8.GetString($peerPake.Body))
    $peerPakeBytes = ConvertFrom-WormholeHex -Hex ([string]$peerPakeObject.pake_v1)
    $result = Complete-WormholeSpake2 -Context $pakeContext -PeerMessage $peerPakeBytes

    $versionPayload = @{ app_versions = @{ 'PowerWormhole' = '0.1.0' } }
    $versionBytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $versionPayload -Depth 10 -Compress))
    $versionKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $Session.Side -Phase 'version'
    $cipherVersion = Protect-WormholeSecretBox -Key $versionKey -Plaintext $versionBytes
    Add-WormholeMailboxPayload -Session $Session -Phase 'version' -Body $cipherVersion

    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'PAKE complete. Verifying peer version...'
    $peerVersion = Receive-WormholeMailboxPayload -Session $Session -Phase 'version' -TimeoutSeconds $TimeoutSeconds
    $peerVersionKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $peerVersion.Side -Phase 'version'
    [void](Unprotect-WormholeSecretBox -Key $peerVersionKey -Ciphertext $peerVersion.Body)

    $transitKey = Get-WormholeTransitKey -SharedKey $result.SharedKey -AppId $Session.AppId
    $senderRecordKey   = Get-WormholeTransitRecordKey -TransitKey $transitKey -Direction 'sender'
    $receiverRecordKey = Get-WormholeTransitRecordKey -TransitKey $transitKey -Direction 'receiver'

    $peerTransitReceived = $false
    $peerRelayAddress = $script:PowerWormholeDefaults.TransitRelay
    $fileOfferReceived = $false
    $fileName = $null
    [long]$fileSize = 0

    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Waiting for inbound offer...'
    $waitDeadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTimeOffset]::UtcNow -lt $waitDeadline) {
        $remaining = [int][Math]::Ceiling(($waitDeadline - [DateTimeOffset]::UtcNow).TotalSeconds)
        $incoming = Receive-WormholeMailboxPayload -Session $Session -TimeoutSeconds $remaining

        if ($incoming.Phase -notmatch '^\d+$') {
            continue
        }

        $incomingKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $incoming.Side -Phase $incoming.Phase
        $plainBytes = Unprotect-WormholeSecretBox -Key $incomingKey -Ciphertext $incoming.Body
        $obj = ConvertFrom-Json -InputObject ([System.Text.Encoding]::UTF8.GetString($plainBytes))

        if ($null -ne $obj.PSObject.Properties['error'] -and $null -ne $obj.error) {
            throw "Peer reported transfer error: $($obj.error)"
        }

        if (-not $peerTransitReceived -and $null -ne $obj.PSObject.Properties['transit']) {
            $peerTransitReceived = $true
            $peerRelayAddress = Get-WormholeTransitRelayFromHints -TransitInfo $obj.transit

            $myTransitInfo = Build-WormholeTransitInfo
            $transitPhase = [string]$Session.NextPhase
            $transitPlain = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ transit = $myTransitInfo } -Depth 10 -Compress))
            $transitKeyPhase = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $Session.Side -Phase $transitPhase
            Add-WormholeMailboxPayload -Session $Session -Phase $transitPhase -Body (Protect-WormholeSecretBox -Key $transitKeyPhase -Plaintext $transitPlain)
            $Session.NextPhase += 1

            if (-not $fileOfferReceived) {
                continue
            }
        }

        $offerProp = $obj.PSObject.Properties['offer']
        if ($null -eq $offerProp -or $null -eq $offerProp.Value) {
            continue
        }

        if ($null -ne $offerProp.Value.PSObject.Properties['message'] -and $null -ne $offerProp.Value.message) {
            $messageText = [string]$offerProp.Value.message
            $answerPhase = [string]$Session.NextPhase
            $answerPayload = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ answer = @{ message_ack = 'ok' } } -Depth 10 -Compress))
            $answerKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $Session.Side -Phase $answerPhase
            $answerCipher = Protect-WormholeSecretBox -Key $answerKey -Plaintext $answerPayload
            Add-WormholeMailboxPayload -Session $Session -Phase $answerPhase -Body $answerCipher
            $Session.NextPhase += 1

            Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Text message received.'
            return [pscustomobject]@{
                Type = 'text'
                Text = $messageText
                FilePath = $null
                FileName = $null
                FileSize = $null
            }
        }

        if ($null -ne $offerProp.Value.PSObject.Properties['file'] -and $null -ne $offerProp.Value.file) {
            $fileOfferReceived = $true
            $fileName = [string]$offerProp.Value.file.filename
            $fileSize = [long]$offerProp.Value.file.filesize

            if (-not $peerTransitReceived) {
                continue
            }

            $answerPhase = [string]$Session.NextPhase
            $answerPlain = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ answer = @{ file_ack = 'ok' } } -Depth 10 -Compress))
            $answerPhaseKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $Session.Side -Phase $answerPhase
            Add-WormholeMailboxPayload -Session $Session -Phase $answerPhase -Body (Protect-WormholeSecretBox -Key $answerPhaseKey -Plaintext $answerPlain)
            $Session.NextPhase += 1

            $outputPath = Join-Path -Path $OutputDirectory -ChildPath $fileName
            Invoke-WormholeStatus -StatusCallback $StatusCallback -Message "Receiving file: $fileName ($fileSize bytes)..."
            Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Connecting to transit relay...'

            $transitConn = Connect-WormholeTransitRelay -TransitRelay $peerRelayAddress -TransitKey $transitKey -Side $Session.Side -Role 'receiver' -TimeoutSeconds 60
            try {
                Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Connected. Receiving file...'
                Receive-WormholeTransitFile -Transit $transitConn `
                    -SenderKey $senderRecordKey `
                    -ReceiverKey $receiverRecordKey `
                    -OutputPath $outputPath `
                    -ExpectedSize $fileSize `
                    -TimeoutSeconds $TimeoutSeconds `
                    -StatusCallback $StatusCallback
            }
            finally {
                try { $transitConn.Stream.Dispose() } catch { }
                try { $transitConn.TcpClient.Dispose() } catch { }
            }

            return [pscustomobject]@{
                Type = 'file'
                Text = $null
                FilePath = $outputPath
                FileName = $fileName
                FileSize = $fileSize
            }
        }
    }

    throw 'Timed out waiting for sender offer.'
}
