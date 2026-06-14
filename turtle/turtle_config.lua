-- turtle_config.lua  -  copied onto every worker by the disk bootstrap.
-- Single-player: the game and server.py run on the same PC, so loopback works
-- (we allowed 127.0.0.0/8 port 8080 in computercraft-server.toml).
-- On a dedicated MC server use that machine's address, or an ngrok https URL.
return {
  server   = "http://127.0.0.1:8080",
  fuelItem = "minecraft:coal",
}
