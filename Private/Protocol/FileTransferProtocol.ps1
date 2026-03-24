function Get-WormholeTransitRelayFromHints {
    <#
    .SYNOPSIS
        Extracts the first usable relay-v1 hostname:port from a parsed transit hints object.
        Falls back to the module default if no valid hints are found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $TransitInfo
    )

    try {
        if ($null -ne $TransitInfo -and $null -ne $TransitInfo.PSObject.Properties['hints-v1']) {
            foreach ($hint in $TransitInfo.'hints-v1') {
                if ($hint.type -eq 'relay-v1' -and $null -ne $hint.hints) {
                    foreach ($endpoint in $hint.hints) {
                        if ($null -ne $endpoint.hostname -and $null -ne $endpoint.port) {
                            return "tcp:$($endpoint.hostname):$($endpoint.port)"
                        }
                    }
                }
            }
        }
    }
    catch {
        Write-WormholeDebug -Component 'filetransfer' -Message 'Error parsing transit hints, using default relay.' -Data @{ error = $_.Exception.Message }
    }

    $script:PowerWormholeDefaults.TransitRelay
}

function Build-WormholeTransitInfo {
    <#
    .SYNOPSIS
        Constructs the transit abilities/hints object for inclusion in offer or answer messages.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $TransitRelay = $script:PowerWormholeDefaults.TransitRelay
    )

    $relayAddress = $TransitRelay -replace '^tcp:', ''
    $parts = $relayAddress.Split(':')
    $hostname = $parts[0]
    $port = [int]$parts[1]

    @{
        'abilities-v1' = @(
            @{ type = 'direct-tcp-v1' },
            @{ type = 'relay-v1' }
        )
        'hints-v1' = @(
            @{
                type  = 'relay-v1'
                hints = @(
                    @{
                        type     = 'direct-tcp-v1' # adding this fixes file transfers to wormhole-william
                        hostname = $hostname
                        port     = $port
                        priority = 0.0
                    }
                )
            }
        )
    }
}

function Invoke-WormholeFileSendProtocol {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session,

        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter()]
        [int] $TimeoutSeconds = 300,

        [Parameter()]
        [scriptblock] $StatusCallback
    )

    # ── PAKE ──────────────────────────────────────────────────────────────────
    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Starting key exchange...'
    Write-WormholeDebug -Component 'filetransfer' -Message 'File send protocol started.' -Session $Session -Data @{ path = $Path; timeoutSeconds = $TimeoutSeconds }
    $pakeContext = Initialize-WormholePake -Session $Session

    $pakeEnvelope = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ pake_v1 = (ConvertTo-WormholeHex -Bytes $pakeContext.Message) } -Depth 5 -Compress))
    Add-WormholeMailboxPayload -Session $Session -Phase 'pake' -Body $pakeEnvelope
    Write-WormholeDebug -Component 'filetransfer' -Message 'Sent PAKE payload.' -Session $Session
    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Waiting for peer to join and exchange PAKE...'

    $peerPake = Receive-WormholeMailboxPayload -Session $Session -Phase 'pake' -TimeoutSeconds $TimeoutSeconds
    $peerPakeObject = ConvertFrom-Json -InputObject ([System.Text.Encoding]::UTF8.GetString($peerPake.Body))
    $peerPakeBytes = ConvertFrom-WormholeHex -Hex ([string]$peerPakeObject.pake_v1)
    $result = Complete-WormholeSpake2 -Context $pakeContext -PeerMessage $peerPakeBytes
    Write-WormholeDebug -Component 'filetransfer' -Message 'Completed SPAKE2.' -Session $Session

    # ── VERSION ───────────────────────────────────────────────────────────────
    $versionBytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ app_versions = @{ 'PowerWormhole' = '0.1.0' } } -Depth 10 -Compress))
    $versionKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $Session.Side -Phase 'version'
    Add-WormholeMailboxPayload -Session $Session -Phase 'version' -Body (Protect-WormholeSecretBox -Key $versionKey -Plaintext $versionBytes)
    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'PAKE complete. Verifying peer version...'

    $peerVersion = Receive-WormholeMailboxPayload -Session $Session -Phase 'version' -TimeoutSeconds $TimeoutSeconds
    $peerVersionKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $peerVersion.Side -Phase 'version'
    [void](Unprotect-WormholeSecretBox -Key $peerVersionKey -Ciphertext $peerVersion.Body)
    Write-WormholeDebug -Component 'filetransfer' -Message 'Peer version verified.' -Session $Session

    # ── TRANSIT KEY + FILE METADATA ───────────────────────────────────────────
    $transitKey = Get-WormholeTransitKey -SharedKey $result.SharedKey -AppId $Session.AppId
    $senderRecordKey   = Get-WormholeTransitRecordKey -TransitKey $transitKey -Direction 'sender'
    $receiverRecordKey = Get-WormholeTransitRecordKey -TransitKey $transitKey -Direction 'receiver'

    $fileItem = Get-Item -LiteralPath $Path
    $fileName = $fileItem.Name
    $fileSize = $fileItem.Length

    Write-WormholeDebug -Component 'filetransfer' -Message 'File metadata resolved.' -Session $Session -Data @{ fileName = $fileName; fileSize = $fileSize }

    # ── SEND PHASE "0": TRANSIT INFO ──────────────────────────────────────────
    $myTransitInfo = Build-WormholeTransitInfo
    $transitPhase = [string]$Session.NextPhase
    $transitPlain = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ transit = $myTransitInfo } -Depth 10 -Compress))
    $transitPhaseKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $Session.Side -Phase $transitPhase
    Add-WormholeMailboxPayload -Session $Session -Phase $transitPhase -Body (Protect-WormholeSecretBox -Key $transitPhaseKey -Plaintext $transitPlain)
    $Session.NextPhase += 1
    Write-WormholeDebug -Component 'filetransfer' -Message 'Sent transit info.' -Session $Session -Data @{ phase = $transitPhase }

    # ── SEND PHASE "1": FILE OFFER ────────────────────────────────────────────
    $offerPhase = [string]$Session.NextPhase
    $offerPlain = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ offer = @{ file = @{ filename = $fileName; filesize = $fileSize } } } -Depth 10 -Compress))
    $offerPhaseKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $Session.Side -Phase $offerPhase
    Add-WormholeMailboxPayload -Session $Session -Phase $offerPhase -Body (Protect-WormholeSecretBox -Key $offerPhaseKey -Plaintext $offerPlain)
    $Session.NextPhase += 1
    Write-WormholeDebug -Component 'filetransfer' -Message 'Sent file offer.' -Session $Session -Data @{ phase = $offerPhase; fileName = $fileName; fileSize = $fileSize }
    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message "Offer sent ($fileName, $fileSize bytes). Waiting for receiver..."

    # ── RECV PHASE "0": PEER TRANSIT INFO ─────────────────────────────────────
    $peerTransitMsg = Receive-WormholeMailboxPayload -Session $Session -Phase $transitPhase -TimeoutSeconds $TimeoutSeconds
    $peerTransitKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $peerTransitMsg.Side -Phase $transitPhase
    $peerTransitPlain = Unprotect-WormholeSecretBox -Key $peerTransitKey -Ciphertext $peerTransitMsg.Body
    $peerTransitObj = ConvertFrom-Json -InputObject ([System.Text.Encoding]::UTF8.GetString($peerTransitPlain))
    $peerRelayAddress = Get-WormholeTransitRelayFromHints -TransitInfo $peerTransitObj.transit
    Write-WormholeDebug -Component 'filetransfer' -Message 'Received peer transit info.' -Session $Session -Data @{ relay = $peerRelayAddress }

    # ── RECV PHASE "1": PEER ANSWER ───────────────────────────────────────────
    $peerAnswerMsg = $null
    $waitDeadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTimeOffset]::UtcNow -lt $waitDeadline) {
        $remaining = [int][Math]::Ceiling(($waitDeadline - [DateTimeOffset]::UtcNow).TotalSeconds)
        $incoming = Receive-WormholeMailboxPayload -Session $Session -TimeoutSeconds $remaining

        if ($incoming.Phase -notmatch '^\d+$') {
            Write-WormholeDebug -Component 'filetransfer' -Message 'Skipping non-numeric post-offer message.' -Session $Session -Data @{ phase = $incoming.Phase }
            continue
        }

        $inKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $incoming.Side -Phase $incoming.Phase
        $inPlain = Unprotect-WormholeSecretBox -Key $inKey -Ciphertext $incoming.Body
        $inObj = ConvertFrom-Json -InputObject ([System.Text.Encoding]::UTF8.GetString($inPlain))

        if ($null -ne $inObj.PSObject.Properties['error'] -and $null -ne $inObj.error) {
            throw "Peer reported error: $($inObj.error)"
        }

        $answerProp = $inObj.PSObject.Properties['answer']
        if ($null -ne $answerProp -and $null -ne $answerProp.Value -and
            $null -ne $answerProp.Value.PSObject.Properties['file_ack'] -and
            [string]$answerProp.Value.file_ack -eq 'ok') {
            Write-WormholeDebug -Component 'filetransfer' -Message 'Received file_ack from receiver.' -Session $Session
            $peerAnswerMsg = $inObj
            break
        }
    }

    if ($null -eq $peerAnswerMsg) {
        throw 'Timed out waiting for receiver file acknowledgement.'
    }

    # ── TRANSIT: CONNECT AND SEND FILE ────────────────────────────────────────
    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Connecting to transit relay...'
    Write-WormholeDebug -Component 'filetransfer' -Message 'Connecting to transit relay for send.' -Session $Session -Data @{ relay = $peerRelayAddress }

    $transitConn = Connect-WormholeTransitRelay -TransitRelay $peerRelayAddress -TransitKey $transitKey -Side $Session.Side -Role 'sender' -TimeoutSeconds 60
    try {
        Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Connected. Sending file...'
        Send-WormholeTransitFile -Transit $transitConn `
            -SenderKey $senderRecordKey `
            -ReceiverKey $receiverRecordKey `
            -FilePath $Path `
            -FileSize $fileSize `
            -TimeoutSeconds $TimeoutSeconds `
            -StatusCallback $StatusCallback
    }
    finally {
        try { $transitConn.Stream.Dispose() } catch { }
        try { $transitConn.TcpClient.Dispose() } catch { }
    }

    Write-WormholeDebug -Component 'filetransfer' -Message 'File send protocol complete.' -Session $Session
}

function Invoke-WormholeFileReceiveProtocol {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session,

        [Parameter(Mandatory = $true)]
        [string] $OutputDirectory,

        [Parameter()]
        [int] $TimeoutSeconds = 300,

        [Parameter()]
        [scriptblock] $StatusCallback
    )

    # ── PAKE ──────────────────────────────────────────────────────────────────
    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Starting key exchange...'
    Write-WormholeDebug -Component 'filetransfer' -Message 'File receive protocol started.' -Session $Session -Data @{ outputDirectory = $OutputDirectory; timeoutSeconds = $TimeoutSeconds }
    $pakeContext = Initialize-WormholePake -Session $Session

    $pakeEnvelope = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ pake_v1 = (ConvertTo-WormholeHex -Bytes $pakeContext.Message) } -Depth 5 -Compress))
    Add-WormholeMailboxPayload -Session $Session -Phase 'pake' -Body $pakeEnvelope
    Write-WormholeDebug -Component 'filetransfer' -Message 'Sent PAKE payload.' -Session $Session
    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Waiting for peer PAKE message...'

    $peerPake = Receive-WormholeMailboxPayload -Session $Session -Phase 'pake' -TimeoutSeconds $TimeoutSeconds
    $peerPakeObject = ConvertFrom-Json -InputObject ([System.Text.Encoding]::UTF8.GetString($peerPake.Body))
    $peerPakeBytes = ConvertFrom-WormholeHex -Hex ([string]$peerPakeObject.pake_v1)
    $result = Complete-WormholeSpake2 -Context $pakeContext -PeerMessage $peerPakeBytes
    Write-WormholeDebug -Component 'filetransfer' -Message 'Completed SPAKE2.' -Session $Session

    # ── VERSION ───────────────────────────────────────────────────────────────
    $versionBytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ app_versions = @{ 'PowerWormhole' = '0.1.0' } } -Depth 10 -Compress))
    $versionKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $Session.Side -Phase 'version'
    Add-WormholeMailboxPayload -Session $Session -Phase 'version' -Body (Protect-WormholeSecretBox -Key $versionKey -Plaintext $versionBytes)
    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'PAKE complete. Verifying peer version...'

    $peerVersion = Receive-WormholeMailboxPayload -Session $Session -Phase 'version' -TimeoutSeconds $TimeoutSeconds
    $peerVersionKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $peerVersion.Side -Phase 'version'
    [void](Unprotect-WormholeSecretBox -Key $peerVersionKey -Ciphertext $peerVersion.Body)
    Write-WormholeDebug -Component 'filetransfer' -Message 'Peer version verified.' -Session $Session

    # ── TRANSIT KEY ───────────────────────────────────────────────────────────
    $transitKey = Get-WormholeTransitKey -SharedKey $result.SharedKey -AppId $Session.AppId
    $senderRecordKey   = Get-WormholeTransitRecordKey -TransitKey $transitKey -Direction 'sender'
    $receiverRecordKey = Get-WormholeTransitRecordKey -TransitKey $transitKey -Direction 'receiver'

    # ── SEND PHASE "0": OUR TRANSIT INFO ──────────────────────────────────────
    $myTransitInfo = Build-WormholeTransitInfo
    $transitPhase = [string]$Session.NextPhase
    $transitPlain = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ transit = $myTransitInfo } -Depth 10 -Compress))
    $transitPhaseKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $Session.Side -Phase $transitPhase
    Add-WormholeMailboxPayload -Session $Session -Phase $transitPhase -Body (Protect-WormholeSecretBox -Key $transitPhaseKey -Plaintext $transitPlain)
    $Session.NextPhase += 1
    Write-WormholeDebug -Component 'filetransfer' -Message 'Sent our transit info.' -Session $Session -Data @{ phase = $transitPhase }
    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Waiting for peer transit info and file offer...'

    # ── RECEIVE PHASE "0" (TRANSIT) AND PHASE "1" (OFFER) ────────────────────
    # Messages may arrive in any order; collect both before proceeding.
    $peerTransitObj = $null
    $peerRelayAddress = $script:PowerWormholeDefaults.TransitRelay
    $fileName = $null
    $fileSize = [long]0
    $offerPhaseNumber = '1'  # Expected offer phase from sender

    $waitDeadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)

    while (($null -eq $peerTransitObj -or $null -eq $fileName) -and [DateTimeOffset]::UtcNow -lt $waitDeadline) {
        $remaining = [int][Math]::Ceiling(($waitDeadline - [DateTimeOffset]::UtcNow).TotalSeconds)
        $incoming = Receive-WormholeMailboxPayload -Session $Session -TimeoutSeconds $remaining

        if ($incoming.Phase -notmatch '^\d+$') {
            Write-WormholeDebug -Component 'filetransfer' -Message 'Skipping non-numeric message.' -Session $Session -Data @{ phase = $incoming.Phase }
            continue
        }

        $inKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $incoming.Side -Phase $incoming.Phase
        $inPlain = Unprotect-WormholeSecretBox -Key $inKey -Ciphertext $incoming.Body
        $inObj = ConvertFrom-Json -InputObject ([System.Text.Encoding]::UTF8.GetString($inPlain))

        if ($null -ne $inObj.PSObject.Properties['error'] -and $null -ne $inObj.error) {
            throw "Peer reported error: $($inObj.error)"
        }

        # Transit info
        if ($null -eq $peerTransitObj -and $null -ne $inObj.PSObject.Properties['transit']) {
            $peerTransitObj = $inObj
            $peerRelayAddress = Get-WormholeTransitRelayFromHints -TransitInfo $inObj.transit
            $offerPhaseNumber = [string]([int]$incoming.Phase + 1)
            Write-WormholeDebug -Component 'filetransfer' -Message 'Received peer transit info.' -Session $Session -Data @{ relay = $peerRelayAddress; offerPhaseExpected = $offerPhaseNumber }
            continue
        }

        # File offer
        $offerProp = $inObj.PSObject.Properties['offer']
        if ($null -ne $offerProp -and $null -ne $offerProp.Value -and
            $null -ne $offerProp.Value.PSObject.Properties['file']) {
            $fileOffer = $offerProp.Value.file
            $fileName  = [string]$fileOffer.filename
            $fileSize  = [long]$fileOffer.filesize
            Write-WormholeDebug -Component 'filetransfer' -Message 'Received file offer.' -Session $Session -Data @{ fileName = $fileName; fileSize = $fileSize }
            Invoke-WormholeStatus -StatusCallback $StatusCallback -Message "Receiving file: $fileName ($fileSize bytes)"
            continue
        }
    }

    if ($null -eq $fileName) {
        throw 'Timed out waiting for file offer from sender.'
    }

    # ── SEND PHASE "1": ANSWER ────────────────────────────────────────────────
    $answerPhase = [string]$Session.NextPhase
    $answerPlain = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ answer = @{ file_ack = 'ok' } } -Depth 10 -Compress))
    $answerPhaseKey = Get-WormholeDerivedPhaseKey -SharedKey $result.SharedKey -Side $Session.Side -Phase $answerPhase
    Add-WormholeMailboxPayload -Session $Session -Phase $answerPhase -Body (Protect-WormholeSecretBox -Key $answerPhaseKey -Plaintext $answerPlain)
    $Session.NextPhase += 1
    Write-WormholeDebug -Component 'filetransfer' -Message 'Sent file_ack answer.' -Session $Session -Data @{ phase = $answerPhase }

    # ── TRANSIT: CONNECT AND RECEIVE FILE ─────────────────────────────────────
    $outputPath = Join-Path -Path $OutputDirectory -ChildPath $fileName
    Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Connecting to transit relay...'
    Write-WormholeDebug -Component 'filetransfer' -Message 'Connecting to transit relay for receive.' -Session $Session -Data @{ relay = $peerRelayAddress; outputPath = $outputPath }

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

    Write-WormholeDebug -Component 'filetransfer' -Message 'File receive protocol complete.' -Session $Session
    return $outputPath
}
