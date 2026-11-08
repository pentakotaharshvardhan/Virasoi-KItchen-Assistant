<#
.SYNOPSIS
  Drives a live cooking session over the backend WebSocket from the terminal - no microphone,
  no emulator. Sends the exact {"type":"user_text"} frames the Flutter app sends when you type.

.DESCRIPTION
  Logs in (or registers) against the deployed backend, optionally starts a session, opens
  wss://<host>/ws/audio?token=<jwt>&sessionId=<uuid>, sends your command(s) and prints every
  frame the kitchen answers with (type, seq, message), so a whole 2-dish / 2-stove flow can be
  validated without touching the UI.

.EXAMPLE
  # fresh 2-stove session, queue two dishes, ask for state, then walk the steps
  # (";" is the separator: `powershell -File` folds -Text 'a','b' into ONE "a,b" string)
  .\tools\ws-send.ps1 -StartSession -Stoves 2 -AddDish 'paneer butter masala;dal tadka' `
      -Status -Text 'next;i am free' -GapSeconds 6 -ListenSeconds 45

  # same session again (token/session are printed at the end of every run)
  .\tools\ws-send.ps1 -Token <jwt> -SessionId <uuid> -Text 'next'
#>
[CmdletBinding()]
param(
    # One or more utterances, sent in order with -GapSeconds between them.
    [string[]]$Text = @(),

    [string]$BaseUrl = 'https://virasoi-kitchen-assistant.onrender.com',

    # JWT - omit to log in with -Username/-Password (registering the account if needed).
    [string]$Token,

    # Cooking session id - omit to reuse nothing and, with -StartSession, create one.
    [string]$SessionId,

    [string]$Username = 'wssender',
    [string]$Password = 'Wssender!123',

    [switch]$StartSession,
    [ValidateRange(1, 4)][int]$Stoves = 2,

    # Dishes to queue over REST before the socket opens (this is how the app adds a dish -
    # the WebSocket classifier deliberately has no "add dish" command).
    [string[]]$AddDish = @(),
    [int]$Serves = 2,

    # Ask the server for the current state instead of a command (reconnect/recovery check).
    [switch]$Status,

    [int]$ListenSeconds = 10,
    [double]$GapSeconds = 3,
    [switch]$RawJson
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# `powershell -File` passes the array as one comma-joined string, so -Text 'next','i am free'
# arrives as the single utterance "next,i am free". Treat ";" (and a stray ",") as a separator
# so both invocation styles produce the intended list.
$Text = @($Text | ForEach-Object { $_ -split '[;,]' } | ForEach-Object { $_.Trim() } |
    Where-Object { $_ })
$AddDish = @($AddDish | ForEach-Object { $_ -split '[;,]' } | ForEach-Object { $_.Trim() } |
    Where-Object { $_ })

function Invoke-ApiJson {
    param([string]$Path, [hashtable]$Body, [string]$BearerToken)
    $headers = @{}
    if ($BearerToken) { $headers['Authorization'] = "Bearer $BearerToken" }
    $params = @{ Method = 'Post'; Uri = "$script:BaseUrl$Path"; Headers = $headers; ContentType = 'application/json'; TimeoutSec = 180 }
    if ($null -ne $Body) { $params['Body'] = ($Body | ConvertTo-Json -Compress) }
    return Invoke-RestMethod @params
}

function Get-OrCreateToken {
    if ($Token) { return $Token }
    $registerBody = @{ username = $Username; email = "$Username@wssender.local"; password = $Password }
    $loginBody = @{ username = $Username; password = $Password }
    # Render cold-starts can outlive a single attempt, and the account may already exist
    # from an earlier run (409) - so: login, register only when the login says 401, retry.
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            $r = Invoke-ApiJson -Path '/api/auth/login' -Body $loginBody
            Write-Host "logged in as $Username"
            return $r.token
        } catch {
            $status = $null
            try { $status = [int]$_.Exception.Response.StatusCode } catch { }
            Write-Host "login attempt $attempt failed (HTTP $status): $($_.Exception.Message)"
            if ($status -eq 401) {
                try {
                    Invoke-ApiJson -Path '/api/auth/register' -Body $registerBody | Out-Null
                    Write-Host "registered $Username"
                } catch {
                    Write-Host "register skipped: $($_.Exception.Message)"
                }
            }
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
    throw "could not log in as $Username - is the backend awake?"
}

function Send-Payload {
    param($Ws, [string]$Json)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Json)
    $seg = [ArraySegment[byte]]::new($bytes)
    $Ws.SendAsync($seg, [Net.WebSockets.WebSocketMessageType]::Text, $true,
        [Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
}

function Write-Frame {
    param([string]$Json)
    if ($RawJson) { Write-Host $Json; return }
    try { $f = $Json | ConvertFrom-Json } catch { Write-Host "<unparsable> $Json"; return }
    $type = $f.type
    $seq = if ($null -ne $f.seq) { "seq=$($f.seq)" } else { 'seq=-' }
    $replay = if ($f.replay) { ' replay' } else { '' }
    $msg = $null
    if ($f.data) {
        if ($f.data.message) { $msg = $f.data.message }
        elseif ($f.data.field) { $msg = "$($f.data.field): $($f.data.text)" }
        else { $msg = ($f.data | ConvertTo-Json -Compress -Depth 6) }
    }
    $ts = (Get-Date).ToString('HH:mm:ss.fff')
    if ($msg) { Write-Host "[$ts] $type $seq$replay  $msg" }
    else { Write-Host "[$ts] $type $seq$replay" }
}

# ---- credentials ------------------------------------------------------------
$Token = Get-OrCreateToken

# ---- session ----------------------------------------------------------------
if (-not $SessionId -and $StartSession) {
    $session = Invoke-ApiJson -Path '/api/sessions/start' -Body @{ numberOfStoves = $Stoves } -BearerToken $Token
    $SessionId = $session.id
    Write-Host "started session $SessionId with $Stoves stoves"
} elseif (-not $SessionId) {
    throw 'Pass -SessionId <uuid>, or -StartSession to create one.'
}

# ---- dishes -----------------------------------------------------------------
foreach ($dish in $AddDish) {
    if ([string]::IsNullOrWhiteSpace($dish)) { continue }
    $snap = Invoke-ApiJson -Path "/api/sessions/$SessionId/dishes" `
        -Body @{ dishName = $dish; servesRequested = $Serves } -BearerToken $Token
    $dishes = @($snap.dishes | ForEach-Object { $_.dishName }) -join ', '
    Write-Host "queued '$dish' - session now has: $dishes"
}

# ---- socket -----------------------------------------------------------------
$wsUrl = ($BaseUrl -replace '^http', 'ws') + "/ws/audio?token=$Token&sessionId=$SessionId"
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$cts = [Threading.CancellationToken]::None
Write-Host "connecting $wsUrl"
$ws.ConnectAsync([Uri]$wsUrl, $cts).GetAwaiter().GetResult() | Out-Null
Write-Host "connected - listening for $ListenSeconds s"

# ---- send -------------------------------------------------------------------
if ($Status) {
    Send-Payload $ws '{"type":"status"}'
    if ($Text.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($Text[0])) {
        Start-Sleep -Seconds $GapSeconds
    }
}
if ($Text.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($Text[0])) {
    $i = 0
    foreach ($t in $Text) {
        if ($i -gt 0) { Start-Sleep -Seconds $GapSeconds }
        $payload = @{ type = 'user_text'; text = $t } | ConvertTo-Json -Compress
        Write-Host ">> $t"
        Send-Payload $ws $payload
        $i++
    }
}

# ---- receive ----------------------------------------------------------------
$deadline = (Get-Date).AddSeconds($ListenSeconds)
$buffer = New-Object byte[] 131072
$sb = [Text.StringBuilder]::new()
while ((Get-Date) -lt $deadline) {
    $seg = [ArraySegment[byte]]::new($buffer)
    $remaining = [int](($deadline - (Get-Date)).TotalMilliseconds)
    if ($remaining -le 0) { break }
    try {
        $task = $ws.ReceiveAsync($seg, [Threading.CancellationToken]::None)
        if (-not $task.Wait($remaining)) { break }   # nothing more arrived in time
        $res = $task.Result
        [void]$sb.Append([Text.Encoding]::UTF8.GetString($buffer, 0, $res.Count))
        if ($res.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) {
            Write-Host "server closed: $($res.CloseStatus) $($res.CloseStatusDescription)"
            break
        }
        if ($res.EndOfMessage -and $sb.Length -gt 0) {
            Write-Frame $sb.ToString()
            [void]$sb.Clear()
        }
    } catch [AggregateException] {
        Write-Host "receive error: $($_.Exception.InnerException.Message)"
        break
    } catch {
        break
    }
}

if ($ws.State -eq [Net.WebSockets.WebSocketState]::Open) {
    # Bounded: a busy server must never leave this script hanging.
    try {
        $close = $ws.CloseAsync([Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', $cts)
        $null = $close.Wait(3000)
    } catch { }
}
$ws.Dispose()
Write-Host "session $SessionId  token $Token"
