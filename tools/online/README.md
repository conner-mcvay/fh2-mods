# Online research: private servers for FH2 on Azimuth

Goal: get FH2 (1.0.0.64, Azimuth 0.9.7) out of offline-only mode and talking to a server we run, to work toward private multiplayer. Nothing here contacts Microsoft or Turn 10; their services are gone, and everything goes to our own server.

## How Azimuth keeps the game offline

Azimuth implements every network-facing Xbox One API as offline, on purpose (its built-in notes on each class say so):

| API | Azimuth's answer |
|---|---|
| `NetworkInformation.GetInternetConnectionProfile()` | no profile |
| `User.GetTokenAndSignatureAsync` / `...ForAllUsersAsync` (Xbox Live tokens) | an operation already failed with `ERROR_NETWORK_UNREACHABLE` (`Azimuth.OfflineTokenRequest`) |
| `IXMLHTTPRequest2` (FreeThreadedXMLHTTP60) | created, but requests never complete ("offline HTTP request") |
| Winsock `WSASocketW` (the game's UDP socket) | `WSAENETDOWN` |
| `SecureDeviceAssociation*` (peer-to-peer), `MessageWebSocket` | "need the network" |

## fh2net (`probe/`)

A DLL that Azimuth loads as `data\bin\azimuth-tls.dll`. The original (Extra Options' DLL, or Azimuth's own) is renamed `azimuth-tls-next.dll`; fh2net loads it and forwards its exports, so Extra Options keeps working. `build.ps1` builds it with Zig (`G:\FH2-1\tools\zig`); `Install-Probe.ps1 [-Uninstall]` puts it in place or takes it out (game closed). It logs to `data\bin\fh2net.log` and reads `data\bin\fh2net.ini`:

```ini
[net]
ConnectivityLevel=4        ; 0 = Azimuth's (offline); 3 = internet; 4 = Xbox Live access
[xbl]
FakeToken=1                ; answer Xbox Live token requests with a made-up token
Token=XBL3.0 x=1234567890;fh2net
[http]
Server=http://127.0.0.1:8090   ; every web request goes here instead of its own host
```

What it does:

- Hooks the game's and `Microsoft.Xbox.Services.dll`'s imports (`CoCreateInstance`, WinRT activation, Winsock, `OutputDebugString`) and logs them.
- `ConnectivityLevel`: wraps the `NetworkInformation` statics so `GetInternetConnectionProfile` answers a profile of that level. The game (`140A2A8B0`) maps level 3 to "internet" and 4 (Xbox's `XboxLiveAccess`) to "Xbox Live".
- `FakeToken`: replaces Azimuth's `LocalUser` vtable slots 16-18 (RVA `24FF10`) and `LocalUserStatics` slots 15-17 (RVA `250218`) with functions returning an already-completed `IAsyncOperation<GetTokenAndSignatureResult>` whose Token and Signature are the configured string. It checks every slot against Azimuth 0.9.7 first and patches nothing otherwise.
- `Server`: `CoCreateInstance(FreeThreadedXMLHTTP60)` returns fh2net's own `IXMLHTTPRequest2` (`xhr.c`), which sends over WinHTTP to the server, with the intended host in `X-Fh2net-Host` and scheme in `X-Fh2net-Scheme`.

## The server (`server/fh2srv.py`)

`py -3 -I server\fh2srv.py [--port 8090]`. Stage 1 records every request to `server/captures/` (`requests.jsonl` plus each body) and answers 503.

## What the game sends (first capture, 2026-10-14)

With all three settings on, at boot and in free roam:

- Turn 10's game services ("LSP"): `POST https://gameservices.FH2.forzamotorsport.net/Services.FH2Release/o.xtsw`, `Content-Type: bin/xtsw`, `User-Agent: Xls Client`. Calls are routed by headers: `X-ClassName: Forza.WebServices.User, Forza.WebServices`, `X-Method: Logon`, plus `X-TitleID: 446059611`, `X-UserId: 0x9000000000000`, `X-CorrelationId`, and the token in `Authorization` and `Signature`. The body is binary, big-endian: u64 user id (`00 09 00 00 00 00 00 00`), u32 length + gamertag (`Player 1`), more fields (111 bytes in all). On failure the game retries after 1, 2, 4, 8, 16 s (the slow load), and Online Road Trip says the FH2 server is unavailable.
- Xbox Live (from `Microsoft.Xbox.Services.dll`; documented REST APIs): `userpresence` (POST presence), `profile` (GET settings), `sessiondirectory` (GET sessions for service config `788f0100-a4bc-46c3-b19b-d1001a96545b`), `achievements`, `music`, `gameserverds` (POST variants for title `1368890819`), and a `wss://rta.xboxlive.com/connect` web socket (not redirected yet).
- The game reads `game:\Media\NerdConfig.ini` (not shipped); unexplored.
- The LSP client's endpoint comes from a config section `HttpProtocolFactory` (`url`, `port`, `UseHTTPS`; `141B7C0E0`), and there is a `TestLspProvider` (`unsecureAddress`, `testwebh.forzamotorsport.net`).

## Next

1. Work out the `Logon` response format from the client's deserializer (the `Xls` namespace: `LspAuthenticator`, `HttpRequest`, `CLspConnection`) and answer it, so the game counts as connected to Turn 10's services.
2. Answer the Xbox Live calls with minimal valid JSON (profile, presence, session directory).
3. Peer-to-peer: Azimuth refuses the game's UDP socket and secure device associations; replace them with plain UDP or a relay.
