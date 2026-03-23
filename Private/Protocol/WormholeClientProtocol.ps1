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
    Write-WormholeDebug -Component 'protocol' -Message 'Sent encrypted application payload.' -Session $Session -Data @{ phase = $phase; plainBytes = $plaintext.Length; cipherBytes = $cipher.Length }

    $Session.NextPhase += 1
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

        if ($null -ne $obj.offer.message) {
            Invoke-WormholeStatus -StatusCallback $StatusCallback -Message 'Text message received.'
            Write-WormholeDebug -Component 'protocol' -Message 'Offer.message extracted successfully.' -Session $Session -Data @{ messageLength = ([string]$obj.offer.message).Length }
            return [string]$obj.offer.message
        }

        Write-WormholeDebug -Component 'protocol' -Message 'Application payload did not contain offer.message; continuing wait.' -Session $Session
    }
}
