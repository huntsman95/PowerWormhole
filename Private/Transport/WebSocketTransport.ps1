function Connect-WormholeWebSocket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $RelayUrl
    )

    Assert-WormholeRelayUrl -RelayUrl $RelayUrl
    Write-WormholeDebug -Component 'ws' -Message 'Opening WebSocket connection.' -Data @{ relayUrl = $RelayUrl }

    $client = [System.Net.WebSockets.ClientWebSocket]::new()
    $uri = [System.Uri]::new($RelayUrl)
    $null = $client.ConnectAsync($uri, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    Write-WormholeDebug -Component 'ws' -Message 'WebSocket connection established.' -Data @{ state = [string]$client.State }
    $client
}

function Send-WormholeWebSocketJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.WebSockets.ClientWebSocket] $Socket,

        [Parameter(Mandatory = $true)]
        [object] $Message
    )

    $bytes = ConvertTo-WormholeJsonBytes -InputObject $Message
    $json = [System.Text.Encoding]::UTF8.GetString($bytes)
    $segment = [System.ArraySegment[byte]]::new($bytes)
    Write-WormholeDebug -Component 'ws' -Message 'Sending WebSocket JSON message.' -Data @{ type = [string]$Message.type; bytes = $bytes.Length; json = $json }
    $Socket.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
}

function Receive-WormholeWebSocketJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.WebSockets.ClientWebSocket] $Socket,

        [Parameter()]
        [ValidateRange(1, 3600)]
        [int] $TimeoutSeconds = 30
    )

    $buffer = [byte[]]::new(8192)
    $stream = [System.IO.MemoryStream]::new()
    $cts = [System.Threading.CancellationTokenSource]::new()
    $cts.CancelAfter([TimeSpan]::FromSeconds($TimeoutSeconds))
    Write-WormholeDebug -Component 'ws' -Message 'Waiting for WebSocket message.' -Data @{ timeoutSeconds = $TimeoutSeconds }

    try {
        while ($true) {
            $segment = [System.ArraySegment[byte]]::new($buffer)
            try {
                $result = $Socket.ReceiveAsync($segment, $cts.Token).GetAwaiter().GetResult()
            }
            catch [System.OperationCanceledException] {
                throw "Timed out waiting for WebSocket message after $TimeoutSeconds seconds."
            }

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                Write-WormholeDebug -Component 'ws' -Message 'Received close frame from server.'
                throw 'Mailbox server closed the WebSocket connection.'
            }

            $stream.Write($buffer, 0, $result.Count)
            Write-WormholeDebug -Component 'ws' -Message 'Received WebSocket frame fragment.' -Data @{ count = $result.Count; endOfMessage = [bool]$result.EndOfMessage }
            if ($result.EndOfMessage) {
                break
            }
        }

        $message = ConvertFrom-WormholeJsonBytes -Bytes $stream.ToArray()
        Write-WormholeDebug -Component 'ws' -Message 'Parsed WebSocket JSON message.' -Data @{ type = [string]$message.type }
        $message
    }
    finally {
        $cts.Dispose()
        $stream.Dispose()
    }
}

function Disconnect-WormholeWebSocket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.WebSockets.ClientWebSocket] $Socket
    )

    if ($Socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        Write-WormholeDebug -Component 'ws' -Message 'Closing WebSocket connection.'
        $null = $Socket.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'closing', [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }

    $Socket.Dispose()
    Write-WormholeDebug -Component 'ws' -Message 'WebSocket disposed.'
}
