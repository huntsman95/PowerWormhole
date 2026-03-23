function Invoke-WormholeWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock] $Action,

        [Parameter()]
        [int] $MaxAttempts = 6,

        [Parameter()]
        [int] $InitialDelayMilliseconds = 1000,

        [Parameter()]
        [int] $MaxDelayMilliseconds = 60000
    )

    $attempt = 0
    $delay = $InitialDelayMilliseconds

    while ($attempt -lt $MaxAttempts) {
        $attempt += 1
        try {
            return & $Action
        }
        catch {
            if ($attempt -ge $MaxAttempts) {
                throw
            }

            Start-Sleep -Milliseconds $delay
            $delay = [Math]::Min([int]($delay * 1.5), $MaxDelayMilliseconds)
        }
    }
}
