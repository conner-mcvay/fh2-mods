# fh2net: online free roam for Forza Horizon 2 (PC)

Experimental. fh2net lets FH2 on Azimuth join **online free roam** with other players through a server you run yourself (on a LAN, or over the internet with port forwarding). Microsoft's and Turn 10's services are long gone; nothing here contacts them.

**No Turn 10 or Microsoft code is used.** fh2net and the server are written from scratch, and the package contains no game files. The server reads the game's message formats at runtime from your own copy of FH2.

Single player keeps working with fh2net installed: with the server running, events pay XP and CR and drivatars race as usual. Without it, the game starts offline.

> **Used fh2net 0.1.0 or 0.1.1?** Their server zeroed your save's XP and CR payouts (even offline). Close the game and run `Repair-Fh2Save.ps1` once (right-click > *Run with PowerShell*). It adds a fixed save revision and keeps the old ones.

## What you need

| | |
|---|---|
| Every player | FH2 1.0.0.64 on **Azimuth 0.9.9** (0.9.7 also works) with **FH2 Extra Options** installed |
| The server PC (one player, or any PC) | [Python 3](https://www.python.org/downloads/) with `pefile` (`py -3 -m pip install pefile`) and a copy of FH2 1.0.0.64 (the server reads message formats from the game's exe; nothing of the game is shipped) |

## How it works

- **fh2net.dll** sits in front of Extra Options as Azimuth's `data\bin\azimuth-tls.dll` (Extra Options becomes `azimuth-tls-next.dll`, and fh2net loads it, so both keep working). It replaces Azimuth's offline stubs: the game sees an Xbox Live connection, its web requests go to your server, and its game traffic (UDP) goes to your server's relay.
- **fh2srv.py** is the server. On TCP **8090** it answers the game's web calls (sign-in, Xbox Live session directory, profiles, liveries). On UDP **5101** it relays game traffic between consoles: each console simulates its own car and the relay forwards it to the others, as Turn 10's servers did.

## Setup

### 1. The server

On the server PC (it can be one of the players' PCs):

```powershell
py -3 -m pip install pefile
py -3 -I server\fh2srv.py --host 0.0.0.0 --game "C:\Games\Anthem_1.0.0.64_x64__8wekyb3d8bbwe"
```

Leave it running. Let it through Windows Firewall (PowerShell as administrator):

```powershell
New-NetFirewallRule -DisplayName fh2srv-http -Direction Inbound -Protocol TCP -LocalPort 8090 -Action Allow
New-NetFirewallRule -DisplayName fh2srv-game -Direction Inbound -Protocol UDP -LocalPort 5101 -Action Allow
```

Over the internet, forward TCP 8090 and UDP 5101 on the server's router to the server PC, and give players its public IP. Liveries players upload are kept in `server\data\`.

### 2. Every player

1. Close the game.
2. Run `Install-Fh2net.ps1` (right-click > *Run with PowerShell*, or `powershell -ExecutionPolicy Bypass -File Install-Fh2net.ps1 -AzimuthRoot <Azimuth folder>`). It copies `fh2net.ini` into Azimuth's `data\bin` the first time.
3. Edit `<Azimuth folder>\data\bin\fh2net.ini`:

   | Setting | Value |
   |---|---|
   | `[http] Server` | `http://<server IP>:8090` (`http://127.0.0.1:8090` on the server PC itself) |
   | `[net] ServerAddress` | `<server IP>` (`::1` on the server PC itself) |
   | `[xbl] Xuid` | a number unique to this player, e.g. `2533274790395904` for the first, `...905` for the second, `...906` for the third |
   | `[net] LocalAddress` | unique per player too: `ZmgybmV0LWxvY2FsLWRldmljZS0x`, `...ZS0y`, `...ZS0z` |
   | `[xbl] Gamertag` | your name in the session (empty: Azimuth's player name) |

4. **Your save follows the Xuid.** Azimuth keeps it in `data\titles\1A96545B\saves\player-1\User_<Xuid in hex>`. With the default Xuid (`2533274790395904` = `User_9000000000000`) nothing changes. With another one, copy your `User_9000000000000` folder to the new name first (`...905` = `User_9000000000001`, `...906` = `User_9000000000002`), or the game starts a new save.

### 3. Playing

1. Start the server, then the game through Azimuth. The game signs in to your server while it loads (the server's window shows the requests). If fh2net can't reach the server when the game starts, it stays out of the way and the game starts offline, as with Azimuth alone (`fh2net.log` says so). Restart the game once the server is up to play online.
2. In free roam, open the pause menu and start **online free roam**. When it says "freeroam session found", press **Select** (View) to join.
3. Other players do the same and join the same session. Players appear in the session list and each other's world.

## Known problems

- If the server stops while you play, the game may hang on its next request to the server. Restart the game.
- No AI traffic online, and the weather isn't shared (each player keeps their own).
- Races, Road Trips, car meets and other online events aren't supported yet; only free roam driving.
- Liveries: other players see your design only after you **save it in the paint shop while online** (that uploads it to the server). Designs saved offline aren't sent.
- Leaving and rejoining is handled; if a session gets stuck, restart the game (the server doesn't need restarting).

## Files

```
README.md, LICENSE
fh2net.dll            the Azimuth DLL
fh2net.ini            settings template (installed into data\bin the first time)
Install-Fh2net.ps1    install / -Uninstall
Repair-Fh2Save.ps1    restores XP and CR payouts in saves zeroed by 0.1.0/0.1.1's server
server\               fh2srv.py (run this), relay.py, nerd.py, xls.py
extras\               controller scripts for testing ([input] Script=): idle (fakes a connected controller), drive (joins and drives in circles)
```

Troubleshooting: fh2net logs to `<Azimuth folder>\data\bin\fh2net.log`; the server records every request in `server\captures\`.

## Credits

- **[Azimuth](https://almost-there-games.itch.io/azimuth)** by Almost There Games, which runs Forza Horizon 2 on PC. fh2net is a plug-in for it and wouldn't exist without it.
- **[FH2 Extra Options](https://github.com/RokkuDayo/ForzaHorizon2_ExtraOptions)** by RokkuDayo, which fh2net loads alongside itself.
