# Local multiplayer validation

Implemented 2–4-player local split-screen in Team Deathmatch, with co-op or versus teams and keyboard/mouse plus controllers or all-controller input. Each seat has independent movement, aim, firing, crouch/prone, weapons, pickups, health, score and respawns. Missing or disconnected controllers leave a neutral seat that can accept a new controller. Start/Options pauses everyone; pause/resume preserves stance.

HUD text uses outlines over the world. No full-width HUD backgrounds cover the top or bottom of any view.

## Verification

- Core: 55 passed, 0 failed.
- Prone/movement: 23 passed, 0 failed.
- Local multiplayer: 49 passed, 0 failed, including controller isolation, four-controller assignment, reconnects, pickups and balanced versus teams at 2/3/4 players.
- Rendered Metal probe: 33 passed, 0 failed, covering actual 2/3/4-player views, input routing, prone skeleton offsets, pause/resume, results, cleanup and returning to single-player.
- Script checker: 0 failures.
- Mac app rebuilt and code signature verified.
- Packaged app smoke test: `EXPORT SMOKE PASS` (all 13 steps passed).

Reports are in `.artifacts/reports/`. Screenshots are in `.artifacts/screenshots/local-multiplayer/`. The focused suite runs with `python3 tools/dev.py test --suite local-multiplayer`; the rendered probe is `tools/local_multiplayer_probe.gd`.

## Limits

Controller checks used synthetic device-specific events; four physical controllers were not tested simultaneously. Split-screen is limited to Team Deathmatch. Campaign and Zombies remain single-player. No sustained four-player performance benchmark was run.
