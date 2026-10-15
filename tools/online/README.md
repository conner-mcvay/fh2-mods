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

Further `[net]` settings, each replacing an Azimuth offline stub that blocks the online path:

| Setting | File | What it does |
|---|---|---|
| `FakeQos=1` | `qos.c` | `QualityOfService.MeasureQualityOfServiceAsync` answers a completed measurement (status 1, 20 ms) for every address |
| `LocalAddress=<base64>` | `qos.c` | `SecureDeviceAddress.GetLocal`/`FromBase64String` objects answer their base64 (Azimuth's answer an empty string, so session members can't be written) |
| `FixStreams=1` | `streams.c` | fh2net's own `DataWriter`/`Buffer`/`DataReader` (Azimuth's `DataWriter` drops every byte, so Xbox Live replies read as empty) |
| `RealSockets=1` | `fh2net.c` | the game's ws2_32 imports go to Windows' ws2_32 |
| `FakeParty=1` | `party.c` | `Party` register game/match session (statics slots 6, 7) answer a completed action |
| `FakeAssociation=1` | `assoc.c` | `SecureDeviceAssociationTemplate.CreateAssociationAsync` answers an association whose remote socket address is `ServerAddress`/`ServerPort` (default `[::1]:5101`) |

Debugging: `[trace] Game=`/`Xsapi=` (int3 trace points, `trace.c`), `[debug] Json/Streams/Party` (logging proxies), and `[input] Script=` (scripted controller presses, `input.c`). `Run-Test.ps1 -Tag <name>` runs one test unattended: archives the captures, starts Azimuth, presses Enter in its launcher, waits for the input script to finish, closes the game.

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

## Logon works (2026-10-14)

With `server/fh2srv.py` answering `Forza.WebServices.User.Logon`, the game counts as connected to Turn 10's services and its online menus unlock.

- Message schemas come from the game's own reflection descriptors (`tools/re/xlstypes.py` dumps them; `server/xls.py` encodes and decodes with them, reading the user's exe). Wire format: big-endian; u32-length strings and blobs; u32-count arrays; structs in field order; DateTime as an ISO 8601 string (an empty one is an error); see `xls.py`.
- Reply body: `WEB_RESPONSE_HEADER` (`Result`, `ErrorCode`, `DataLength`: u32 each; `Result` 0 = success, 2 = error with an `ErrorCode` and a `DataLength`-byte message), then the `<Call>_Results` struct. Parsed by `140EFC9E0` / `140EFCCA0`; fields by `140EE5880`.
- The client reads a reply until the stream returns `S_FALSE` (fh2net's response stream does that on a short read).

After Logon the game calls: `Xls.WebServices.User.GetUserData`, `Storefront.GetFileKeywords` / `GetFeaturedLiveriesForRandomCars`, `CarClub.GetClubKeywords` / `GetRecommendedClubs`, `User.GetOwnedProducts` / `GetEconomySettings` / `GetCompareStatsForRelatedUsers`, `Drivatar.GetDrivatarsForCache`, `DailyCreditBonus.GetPayout`, `OnlineProfile.UpdateAllTables` / `UpdateAll` (all unanswered so far).

## Online free roam uses dedicated servers

Starting a private free roam session calls Xbox Live's game server discovery (`POST gameserverds.xboxlive.com/titles/1368890819/variants`, body `{"locale":"en-us","maxVariants":8,"publisherOnly":false}`); unanswered, the game says it can't reach the Live configuration servers. The game then allocates a cluster (`AllocateClusterAsync` on `gameserverms.xboxlive.com`, `IDS_MultiplayerStatus_AllocatingCluster`) and connects to the server it gets (`[SecureIPResolver][CreateGameServerAssociation]`). These were Turn 10's servers on Xbox Live Compute; their program was never public. The client's replication code has server roles (`m_pManager->IsServer()`, `IsServerOwned`, `SessionHost`), which is worth reading before deciding how to stand in for the server.

## Reaching the join prompt (2026-10-15)

`fh2srv.py` answers the variants (`GSI_NAME` `Release_6CC152FD.FreeRoam`), `/qosservers`, and runs an in-memory session directory (MPSD contract 105). When the game writes its game session (`gameServerPlatform` constants), the server pre-fills `servers.gameServerPlatform` with an Active server (`secureDeviceAddress` `ZmgybmV0LWdhbWUtc2VydmVy`), so `AllocateServer` (`141836190`) skips the cluster allocation. The game then shows "freeroam session found, press select to join!".

Joining creates a secure device association to the server's address (`SecureIPResolver`, `1417A0FF0`, template `SecurePeerTraffic`), then reads the association's remote socket address (slot 9, a 28-byte `sockaddr_in6`, `141763310`). The game's UDP socket is `[::]:5100` (manifest `SecureConsoleSocket`).

## The game's first packets to the server

With `FakeAssociation=1`, the game sends to `[::1]:5101` (recorded in `captures/udp.jsonl`) a 51-byte packet every ~2.1 s, 5 tries, then 5 more with one field changed:

```
0000 feff 00000000 01 33 0000 109ba1a1981a1923221023b6b0b339b4 3438 00..00 1200 0400 00..00 0200 00000000
```

## Next

1. Decode that handshake from the client's receive path and answer it.
2. Answer the remaining LSP calls with real data.
