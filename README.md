# ServerUplinkEx

Add the following to the list of `ServerActors`:
`ServerActors=ServerUplinkEx.ServerUplinkEx`

Add the following to your UnrealTournament.ini:
```ini
[ServerUplinkEx.ServerUplinkEx]
MasterServers=(Address="unreal.epicgames.com",Port=27900)
UpdateMinutes=1
```

Add more master servers by adding `MasterServers=(Address="masterserver.example.com",Port=27900)` lines to that section.
