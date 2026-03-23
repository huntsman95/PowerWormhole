function Receive-WormholeText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Code,

        [Parameter()]
        [string] $RelayUrl = $script:PowerWormholeDefaults.RelayUrl,

        [Parameter()]
        [string] $AppId = $script:PowerWormholeDefaults.AppId

        ,[Parameter()]
        [ValidateRange(1, 3600)]
        [int] $TimeoutSeconds = 300

        ,[Parameter()]
        [switch] $NoStatus
    )

    $session = $null
    try {
        Write-WormholeDebug -Component 'cmd-recv' -Message 'Receive-WormholeText invoked.' -Data @{ code = $Code; timeoutSeconds = $TimeoutSeconds; noStatus = [bool]$NoStatus }
        $session = Open-Wormhole -Code $Code -RelayUrl $RelayUrl -AppId $AppId
        Write-WormholeDebug -Component 'cmd-recv' -Message 'Open-Wormhole returned session.' -Session $session

        $statusCallback = $null
        if (-not $NoStatus) {
            $statusCallback = {
                param($Message)
                Write-Host "[recv] $Message"
            }
        }

        $message = Invoke-WormholeTextReceiveProtocol -Session $session -TimeoutSeconds $TimeoutSeconds -StatusCallback $statusCallback
        Write-WormholeDebug -Component 'cmd-recv' -Message 'Receive-WormholeText protocol finished.' -Session $session -Data @{ receivedLength = $message.Length }
        $message
    }
    finally {
        if ($null -ne $session) {
            Write-WormholeDebug -Component 'cmd-recv' -Message 'Closing mailbox from Receive-WormholeText.' -Session $session
            Close-WormholeMailbox -Session $session -Mood 'happy'
        }
    }
}
