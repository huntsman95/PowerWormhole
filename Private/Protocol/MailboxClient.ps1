function New-WormholeSideId {
    [CmdletBinding()]
    param()

    $bytes = [byte[]]::new(5)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    ConvertTo-WormholeHex -Bytes $bytes
}

function Connect-WormholeMailbox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session
    )

    Write-WormholeDebug -Component 'mailbox' -Message 'Connecting mailbox socket.' -Session $Session -Data @{ relayUrl = $Session.RelayUrl }
    $socket = Invoke-WormholeWithRetry -Action {
        Connect-WormholeWebSocket -RelayUrl $Session.RelayUrl
    }

    $Session.Socket = $socket
    $Session.Connected = $true
    Write-WormholeDebug -Component 'mailbox' -Message 'Mailbox socket connected.' -Session $Session

    $bind = New-WormholeProtocolMessage -Type 'bind' -Fields @{
        appid = $Session.AppId
        side = $Session.Side
        id = (New-Guid).Guid
    }
    Write-WormholeDebug -Component 'mailbox' -Message 'Sending bind command.' -Session $Session -Data @{ requestId = $bind.id; appId = $Session.AppId }
    Send-WormholeWebSocketJson -Socket $Session.Socket -Message $bind

    Wait-WormholeMailboxAck -Session $Session -RequestId $bind.id | Out-Null
    Write-WormholeDebug -Component 'mailbox' -Message 'Bind acknowledged.' -Session $Session -Data @{ requestId = $bind.id }
    $Session
}

function Wait-WormholeMailboxMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session,

        [Parameter()]
        [scriptblock] $Filter = { $true },

        [Parameter()]
        [int] $TimeoutSeconds = 60
    )

    if ($null -eq $Session.PSObject.Properties['PendingMessages']) {
        $Session | Add-Member -NotePropertyName PendingMessages -NotePropertyValue ([System.Collections.Generic.Queue[object]]::new())
    }

    $pendingMessages = $Session.PendingMessages
    $deferredMessages = [System.Collections.Generic.List[object]]::new()

    function Restore-WormholeDeferredMessages {
        param(
            [pscustomobject] $RestoreSession,

            [System.Collections.Generic.List[object]] $Deferred,

            [System.Collections.Generic.Queue[object]] $Pending
        )

        if ($Deferred.Count -eq 0) {
            return
        }

        $combined = [System.Collections.Generic.Queue[object]]::new()
        foreach ($item in $Deferred) {
            $combined.Enqueue($item)
        }

        foreach ($item in $Pending) {
            $combined.Enqueue($item)
        }

        $RestoreSession.PendingMessages = $combined
    }

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    Write-WormholeDebug -Component 'mailbox' -Message 'Waiting for mailbox message.' -Session $Session -Data @{ timeoutSeconds = $TimeoutSeconds }
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        $remaining = [int][Math]::Ceiling(($deadline - [DateTimeOffset]::UtcNow).TotalSeconds)
        if ($remaining -lt 1) {
            break
        }

        if ($pendingMessages.Count -eq 0) {
            $incoming = Receive-WormholeWebSocketJson -Socket $Session.Socket -TimeoutSeconds $remaining
            foreach ($item in @($incoming)) {
                if ($null -ne $item) {
                    $pendingMessages.Enqueue($item)
                }
            }

            if ($pendingMessages.Count -gt 1) {
                Write-WormholeDebug -Component 'mailbox' -Message 'Received batched mailbox messages.' -Session $Session -Data @{ count = $pendingMessages.Count }
            }
        }

        if ($pendingMessages.Count -eq 0) {
            continue
        }

        $message = $pendingMessages.Dequeue()
        $messageId = if ($null -ne $message.PSObject.Properties['id']) { [string]$message.id } else { '' }
        $messagePhase = if ($null -ne $message.PSObject.Properties['phase']) { [string]$message.phase } else { '' }

        if ($message.type -eq 'welcome') {
            $Session.Welcome = $message.welcome
            Write-WormholeDebug -Component 'mailbox' -Message 'Captured welcome message.' -Session $Session
            continue
        }

        if ($message.type -eq 'error') {
            $serverError = if ($null -ne $message.PSObject.Properties['error']) { [string]$message.error } else { 'unknown server error' }
            Write-WormholeDebug -Component 'mailbox' -Message 'Received server error message.' -Session $Session -Data @{ error = $serverError }
            throw "Mailbox server error: $serverError"
        }

        if (& $Filter $message) {
            Restore-WormholeDeferredMessages -RestoreSession $Session -Deferred $deferredMessages -Pending $pendingMessages
            Write-WormholeDebug -Component 'mailbox' -Message 'Mailbox message matched filter.' -Session $Session -Data @{ type = [string]$message.type; id = $messageId; phase = $messagePhase }
            return $message
        }

        $deferredMessages.Add($message)
        Write-WormholeDebug -Component 'mailbox' -Message 'Mailbox message did not match filter.' -Session $Session -Data @{ type = [string]$message.type; id = $messageId; phase = $messagePhase }
    }

    Restore-WormholeDeferredMessages -RestoreSession $Session -Deferred $deferredMessages -Pending $pendingMessages

    throw "Timed out waiting for mailbox message after $TimeoutSeconds seconds."
}

function Wait-WormholeMailboxAck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session,

        [Parameter(Mandatory = $true)]
        [string] $RequestId,

        [Parameter()]
        [int] $TimeoutSeconds = 30
    )

    Write-WormholeDebug -Component 'mailbox' -Message 'Waiting for ACK.' -Session $Session -Data @{ requestId = $RequestId; timeoutSeconds = $TimeoutSeconds }
    Wait-WormholeMailboxMessage -Session $Session -TimeoutSeconds $TimeoutSeconds -Filter {
        param($msg)
        $msg.type -eq 'ack' -and $msg.id -eq $RequestId
    }
}

function Invoke-WormholeMailboxCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session,

        [Parameter(Mandatory = $true)]
        [string] $Type,

        [Parameter()]
        [hashtable] $Fields = @{},

        [Parameter()]
        [string] $ResponseType,

        [Parameter()]
        [int] $TimeoutSeconds = 30
    )

    $requestId = (New-Guid).Guid
    $commandFields = @{}
    foreach ($key in $Fields.Keys) {
        $commandFields[$key] = $Fields[$key]
    }
    $commandFields.id = $requestId

    $message = New-WormholeProtocolMessage -Type $Type -Fields $commandFields
    Write-WormholeDebug -Component 'mailbox' -Message 'Sending mailbox command.' -Session $Session -Data @{ type = $Type; requestId = $requestId; expects = $ResponseType }
    Send-WormholeWebSocketJson -Socket $Session.Socket -Message $message

    Wait-WormholeMailboxAck -Session $Session -RequestId $requestId -TimeoutSeconds $TimeoutSeconds | Out-Null

    if ([string]::IsNullOrWhiteSpace($ResponseType)) {
        Write-WormholeDebug -Component 'mailbox' -Message 'Mailbox command completed with ACK only.' -Session $Session -Data @{ type = $Type; requestId = $requestId }
        return $null
    }

    $response = Wait-WormholeMailboxMessage -Session $Session -TimeoutSeconds $TimeoutSeconds -Filter {
        param($msg)
        $msg.type -eq $ResponseType
    }
    Write-WormholeDebug -Component 'mailbox' -Message 'Mailbox command received response.' -Session $Session -Data @{ type = $Type; requestId = $requestId; responseType = $ResponseType }
    $response
}

function Open-WormholeMailbox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session,

        [Parameter()]
        [switch] $AllocateNameplate
    )

    if ($AllocateNameplate) {
        Write-WormholeDebug -Component 'mailbox' -Message 'Allocating nameplate.' -Session $Session
        $allocated = Invoke-WormholeMailboxCommand -Session $Session -Type 'allocate' -ResponseType 'allocated'

        if ($allocated -is [System.Array]) {
            $allocated = @($allocated | Where-Object { $null -ne $_ -and $_.PSObject.Properties['type'] -and [string]$_.type -eq 'allocated' } | Select-Object -First 1)
            if ($allocated.Count -gt 0) {
                $allocated = $allocated[0]
            }
            else {
                $allocated = $null
            }
        }

        $nameplate = $null
        foreach ($propertyName in @('nameplate', 'nameplate_id', 'nameplateId')) {
            if ($null -ne $allocated -and $null -ne $allocated.PSObject.Properties[$propertyName]) {
                $candidateValue = [string]$allocated.$propertyName
                if (-not [string]::IsNullOrWhiteSpace($candidateValue)) {
                    $nameplate = $candidateValue
                    break
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($nameplate) -and $null -ne $allocated -and $null -ne $allocated.PSObject.Properties['allocated']) {
            $allocatedObject = $allocated.allocated
            if ($null -ne $allocatedObject) {
                foreach ($propertyName in @('nameplate', 'nameplate_id', 'nameplateId')) {
                    if ($null -ne $allocatedObject.PSObject.Properties[$propertyName]) {
                        $candidateValue = [string]$allocatedObject.$propertyName
                        if (-not [string]::IsNullOrWhiteSpace($candidateValue)) {
                            $nameplate = $candidateValue
                            break
                        }
                    }
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($nameplate)) {
            $allocatedJson = ConvertTo-Json -InputObject $allocated -Depth 20 -Compress
            throw "Allocate response did not include nameplate. Response: $allocatedJson"
        }

        $Session.Nameplate = $nameplate
        Write-WormholeDebug -Component 'mailbox' -Message 'Allocated nameplate.' -Session $Session -Data @{ nameplate = $Session.Nameplate }
    }

    Write-WormholeDebug -Component 'mailbox' -Message 'Claiming nameplate.' -Session $Session -Data @{ nameplate = $Session.Nameplate }
    $claimed = Invoke-WormholeMailboxCommand -Session $Session -Type 'claim' -Fields @{ nameplate = $Session.Nameplate } -ResponseType 'claimed'
    if ($claimed -is [System.Array]) {
        $claimed = @($claimed | Where-Object { $null -ne $_ -and $_.PSObject.Properties['type'] -and [string]$_.type -eq 'claimed' } | Select-Object -First 1)
        if ($claimed.Count -gt 0) {
            $claimed = $claimed[0]
        }
        else {
            $claimed = $null
        }
    }

    $mailboxId = $null
    foreach ($propertyName in @('mailbox', 'mailbox_id', 'mailboxId', 'mbox')) {
        if ($null -ne $claimed -and $null -ne $claimed.PSObject.Properties[$propertyName]) {
            $candidateValue = [string]$claimed.$propertyName
            if (-not [string]::IsNullOrWhiteSpace($candidateValue)) {
                $mailboxId = $candidateValue
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($mailboxId) -and $null -ne $claimed -and $null -ne $claimed.PSObject.Properties['claimed']) {
        $claimedObject = $claimed.claimed
        if ($null -ne $claimedObject) {
            foreach ($propertyName in @('mailbox', 'mailbox_id', 'mailboxId', 'mbox')) {
                if ($null -ne $claimedObject.PSObject.Properties[$propertyName]) {
                    $candidateValue = [string]$claimedObject.$propertyName
                    if (-not [string]::IsNullOrWhiteSpace($candidateValue)) {
                        $mailboxId = $candidateValue
                        break
                    }
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($mailboxId)) {
        $claimedJson = ConvertTo-Json -InputObject $claimed -Depth 20 -Compress
        throw "Claim response did not include mailbox id. Response: $claimedJson"
    }

    $Session.MailboxId = $mailboxId
    Write-WormholeDebug -Component 'mailbox' -Message 'Claimed mailbox.' -Session $Session -Data @{ mailboxId = $Session.MailboxId }

    Write-WormholeDebug -Component 'mailbox' -Message 'Opening mailbox subscription.' -Session $Session
    Invoke-WormholeMailboxCommand -Session $Session -Type 'open' -Fields @{ mailbox = $Session.MailboxId } | Out-Null
    Write-WormholeDebug -Component 'mailbox' -Message 'Mailbox open command accepted.' -Session $Session
    $Session
}

function Add-WormholeMailboxPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session,

        [Parameter(Mandatory = $true)]
        [string] $Phase,

        [Parameter(Mandatory = $true)]
        [byte[]] $Body
    )

    $hex = ConvertTo-WormholeHex -Bytes $Body
    Write-WormholeDebug -Component 'mailbox' -Message 'Adding mailbox payload.' -Session $Session -Data @{ phase = $Phase; bodyBytes = $Body.Length }
    Invoke-WormholeMailboxCommand -Session $Session -Type 'add' -Fields @{ phase = $Phase; body = $hex } | Out-Null
}

function Receive-WormholeMailboxPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session,

        [Parameter()]
        [string] $Phase,

        [Parameter()]
        [int] $TimeoutSeconds = 300
    )

    Write-WormholeDebug -Component 'mailbox' -Message 'Waiting for mailbox payload.' -Session $Session -Data @{ phase = $Phase; timeoutSeconds = $TimeoutSeconds }
    $message = Wait-WormholeMailboxMessage -Session $Session -TimeoutSeconds $TimeoutSeconds -Filter {
        param($msg)
        if ($msg.type -ne 'message') {
            return $false
        }

        if ($msg.side -eq $Session.Side) {
            return $false
        }

        if ([string]::IsNullOrWhiteSpace($Phase)) {
            return $true
        }

        $msg.phase -eq $Phase
    }

    [pscustomobject]@{
        Side = [string]$message.side
        Phase = [string]$message.phase
        Body = ConvertFrom-WormholeHex -Hex ([string]$message.body)
        MessageId = [string]$message.id
    }
}

function Close-WormholeMailbox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Session,

        [Parameter()]
        [ValidateSet('happy', 'lonely', 'scary', 'errory')]
        [string] $Mood = 'happy'
    )

    if ($Session.Socket -eq $null) {
        Write-WormholeDebug -Component 'mailbox' -Message 'Close requested but no active socket.' -Session $Session
        return
    }

    Write-WormholeDebug -Component 'mailbox' -Message 'Closing mailbox.' -Session $Session -Data @{ mood = $Mood }
    try {
        if ($Session.MailboxId) {
            Invoke-WormholeMailboxCommand -Session $Session -Type 'close' -Fields @{ mailbox = $Session.MailboxId; mood = $Mood } -ResponseType 'closed' | Out-Null
            Write-WormholeDebug -Component 'mailbox' -Message 'Mailbox closed.' -Session $Session
        }
    }
    catch {
    }

    try {
        if ($Session.Nameplate) {
            Invoke-WormholeMailboxCommand -Session $Session -Type 'release' -Fields @{ nameplate = $Session.Nameplate } -ResponseType 'released' | Out-Null
            Write-WormholeDebug -Component 'mailbox' -Message 'Nameplate released.' -Session $Session
        }
    }
    catch {
    }

    Disconnect-WormholeWebSocket -Socket $Session.Socket
    $Session.Socket = $null
    $Session.Connected = $false
    Write-WormholeDebug -Component 'mailbox' -Message 'Mailbox disconnect complete.' -Session $Session
}
