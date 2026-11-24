# Arachnid Storyteller

Arachnid Storyteller is a standalone RedM gamemaster foundation. Its panel takes visual inspiration from the Jonesy Admin interface, but it has no Jonesy Admin dependency.

## Current phase

- Create and maintain story arcs with draft, published, and archived status.
- Build ordered scene beats with objectives.
- Optionally save a scene beat at the storyteller's server-verified in-game position.
- Build ordered camera rails for a scene: capture nodes, set their placement distance, and edit FOV, hold, transition, notes, and order.
- Start one live session from a published story, advance or jump between its beats, and end it explicitly.
- Target a session to everyone online, selected players, or players inside a saved sphere or box.
- Save, edit, and delete named session areas centered on the storyteller's current in-game position.
- Announce the active beat to connected players with a temporary narrative overlay.
- Turn each scene's objective into a persistent player HUD item, then update, complete, or fail it from the gamemaster console.
- Record all administration actions in MySQL.

The session runtime deliberately announces story beats only. It does **not** spawn peds, control players, start cutscenes, or execute scenes. Those capabilities should be added as explicitly designed, permission-checked phases.

## Install

1. Place `arachnid_storyteller` in your RedM resources directory.
2. Ensure `oxmysql` starts before it.
3. Add `ensure arachnid_storyteller` to `server.cfg`.
4. Grant both ACE permissions to your storyteller group:

```cfg
add_ace group.storyteller arachnid.storyteller.open allow
add_ace group.storyteller arachnid.storyteller.manage allow
```

5. Join the server and run `/STTool`.

The resource creates these tables automatically at startup:

- `arachnid_storyteller_stories`
- `arachnid_storyteller_scenes`
- `arachnid_storyteller_audit`
- `arachnid_storyteller_camera_points`
- `arachnid_storyteller_areas`

Saving a world location requires server-side player coordinates, so enable OneSync if your RedM setup does not already provide them.

## Camera rails and optional gun tools

Open a saved scene beat in `/STTool`, then use **Capture camera node**. The placement-distance slider controls how far forward from the storyteller the node is saved; its maximum is server-enforced through `Config.Camera.Tool.maxPlacementDistance`.

By default, `Config.Camera.Tool.weapon` is empty and node capture is panel-only. Set it to a RedM weapon hash or name if you want captures to require that weapon/tool to be equipped. The resource does not spawn, grant, or otherwise manage that weapon.

Camera rail playback is not enabled yet. This phase creates and validates the ordered keyframe data first; actual camera interpolation will follow after it is tested in-game.

## Live-session rules

- Only one session can be active at a time.
- A story must be `published` and contain at least one scene beat before it can go live.
- The server, not the NUI, decides which scene is active and broadcasts each change.
- Set `Config.Session.broadcastToPlayers = false` to keep session controls active without showing the player overlay.
- Advancing or jumping to another beat resets its live objective to that scene's saved objective; objective completion does not auto-advance the session.
- Selected-audience sessions send beat and objective updates only to the chosen, currently online players. The server revalidates every selected source and caps the list with `Config.Session.maxParticipants`.
- Area-audience sessions capture the online players inside the selected region when the session starts. The server checks their current positions, caps the captured list with `Config.Session.maxParticipants`, and does not add players who enter the area later.
- Spheres use a radius; boxes use width, depth, and height and remain axis-aligned. Area dimensions are checked on the server against `Config.Areas` limits.
