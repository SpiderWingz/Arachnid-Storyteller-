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
- Build a per-story visual node flow with Start, Scene Beat, Delay, Branch, Random Branch, variable, objective, area wait, and End nodes.
- Save flow graphs in MySQL and run them on the server with Pause, Resume, and Stop controls. Area and objective waits have no automatic timeout.
- Add opt-in flow actions for messages, health, armor, weapons, freeze, teleport, kill, VORP respawn, and active-job changes.
- Capture named teleport destinations for each story at the storyteller's server-verified position and heading.
- Announce the active beat to connected players with a temporary narrative overlay.
- Turn each scene's objective into a persistent player HUD item, then update, complete, or fail it from the gamemaster console.
- Record all administration actions in MySQL.

The flow runtime is server-authoritative. Player actions are limited to the session audience and disabled by default unless noted below. NPCs, props, world controls, audio/visual effects, and camera-rail playback remain later phases.

## Install

1. Place `arachnid_storyteller` in your RedM resources directory.
2. Ensure `oxmysql` starts before it.
3. Add `ensure arachnid_storyteller` to `server.cfg`.
4. Grant the console permissions to your storyteller group. Add the third ACE when they should be allowed to start flows containing player-action nodes:

```cfg
add_ace group.storyteller arachnid.storyteller.open allow
add_ace group.storyteller arachnid.storyteller.manage allow
add_ace group.storyteller arachnid.storyteller.playeractions allow
```

5. Join the server and run `/STTool`.

The resource creates these tables automatically at startup:

- `arachnid_storyteller_stories`
- `arachnid_storyteller_scenes`
- `arachnid_storyteller_audit`
- `arachnid_storyteller_camera_points`
- `arachnid_storyteller_areas`
- `arachnid_storyteller_flows`
- `arachnid_storyteller_teleports`

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

## Visual story flows

Open a saved story in `/STTool` and use **Story flow graph** to add, move, configure, and connect nodes. Choose an output port, then an input port. Graphs are saved per story in `arachnid_storyteller_flows`.

Supported nodes are Start, Scene Beat, Delay, Branch, Random Branch, Set/Add/Subtract Variable, Set Objective, Wait for Objective, Wait for Area, Send Message, Freeze/Unfreeze, Set Health/Armor, Give/Remove/Strip Weapons, Teleport, Kill, VORP Respawn, VORP Change Job, and End. Variables reset for every run and can store numbers, text, or true/false values; arithmetic nodes require numeric values. Branch nodes support equality and numeric ordering comparisons.

The server validates node types, scene, area, teleport, weapon, and VORP job references, connections, cycles, reachability, and graph limits before a flow starts. One Start node and at least one End node are required. Every branch output must connect to another node. Runs snapshot their graph, area geometry, and teleport markers at start, so later edits do not change a live run. A 32-node per-tick limit protects the server from long immediate chains.

Delay, objective, and area waits pause graph progression without a timeout. An objective wait continues through the matching completed or failed output. An area wait continues when any connected participant in the session audience enters its saved sphere or axis-aligned box. The storyteller can pause, resume, or end a flow from the session controls. Existing stories with no saved graph keep the manual scene controls.

Set `Config.Flow` limits to tune maximum nodes, links, delay, work per tick, and tick interval. Flows are stored in MySQL, but active runtime state is in memory and does not resume after a resource restart.

## Flow player actions and VORP

Each action node targets all connected session participants or one random connected participant. Selected-player and area audiences remain captured at session start. An action node executes once when reached; pausing and resuming does not repeat it. When the session or resource ends, Arachnid unfreezes only the players it froze.

Send Message is enabled by default. All state-changing actions are disabled by default in `Config.PlayerActions.enabled`; enable only the actions your server intends to use. Grant the separate `arachnid.storyteller.playeractions` ACE to storytellers who may start flows containing action nodes. Weapon and job allowlists start empty. Replace those empty tables at the bottom of `config.lua` with entries using the server's actual RedM weapon and VORP job names:

```lua
Config.PlayerActions.weapons = {
  WEAPON_REVOLVER_CATTLEMAN = { label = 'Cattleman Revolver', maxAmmo = 120, defaultAmmo = 6 }
}

Config.PlayerActions.jobs = {
  sheriff = { label = 'Sheriff', grades = { 0, 1, 2 } }
}
```

Set each action's toggle in `Config.PlayerActions.enabled` to `true` to allow that node to run. `maxHealth`, `maxArmor`, the global `maxAmmo` cap (also limited by each weapon entry), `maxMessageLength`, and `teleportZOffset` bound the corresponding effects. Health defaults to a maximum of 500 and armor to 100.

Change Job replaces the active VORP job and grade through the public active-character API; it does not add a multijob. Respawn and job nodes require `vorp_core` and the corresponding public Core API at flow start. Targets without a currently loaded VORP character are skipped by Change Job.

Teleport markers are stored per story in `arachnid_storyteller_teleports`. Each marker saves its label, position, and heading. A running flow uses the saved marker snapshot from when the session started.
