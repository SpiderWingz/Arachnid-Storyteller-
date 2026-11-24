# Arachnid Storyteller

Arachnid Storyteller is a standalone RedM gamemaster foundation. Its panel takes visual inspiration from the Jonesy Admin interface, but it has no Jonesy Admin dependency.

## Features

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
- Play a scene's existing camera rail locally for preview or to the current live-session audience, manually or from a flow; pause and stop playback.
- Configure per-scene freeze, HUD, letterbox, loop, fade, and default FOV settings for cutscenes.
- Open an RTS sandbox when no story is live; deploy allowlisted NPCs, props, and optional shared weapon pickups, then command tracked NPCs with move, attack-move, formations, patrols, named groups, stances, weapon toggles, or direct possession.
- Capture named teleport destinations for each story at the storyteller's server-verified position and heading.
- Spawn allowlisted NPCs, NPC groups, and props at story-specific server-captured markers; set hostility, targets, patrol routes, and death waits.
- Control only registered world targets with owner-approved operations and explicit restore/persist behavior.
- Send allowlisted sound, screen fade, announcement, subtitle, and screen shake effects to the current audience.
- Announce the active beat to connected players with a temporary narrative overlay.
- Turn each scene's objective into a persistent player HUD item, then update, complete, or fail it from the gamemaster console.
- Record all administration actions in MySQL.

The flow runtime is server-authoritative. Player actions, cutscenes, and transient effects are limited to connected session participants. Spawned world entities are shared, so nearby nonparticipants may see them. State-changing actions, encounters, world controls, and effects are disabled by default unless noted below.

## Install

1. Place `arachnid_storyteller` in your RedM resources directory.
2. Ensure `oxmysql` starts before it.
3. Add `ensure arachnid_storyteller` to `server.cfg`.
4. Grant the console permissions to your storyteller group. Grant each optional feature ACE only to storytellers who should use that feature family:

```cfg
add_ace group.storyteller arachnid.storyteller.open allow
add_ace group.storyteller arachnid.storyteller.manage allow
add_ace group.storyteller arachnid.storyteller.playeractions allow
add_ace group.storyteller arachnid.storyteller.cutscenes allow
add_ace group.storyteller arachnid.storyteller.encounters allow
add_ace group.storyteller arachnid.storyteller.world allow
add_ace group.storyteller arachnid.storyteller.effects allow
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
- `arachnid_storyteller_cutscene_settings`
- `arachnid_storyteller_spawn_points`

Saving a world location requires server-side player coordinates, so enable OneSync if your RedM setup does not already provide them.

## Camera rails and optional gun tools

Open a saved scene beat in `/STTool`, then use **Capture camera node**. The placement-distance slider controls how far forward from the storyteller the node is saved; its maximum is server-enforced through `Config.Camera.Tool.maxPlacementDistance`.

By default, `Config.Camera.Tool.weapon` is empty and node capture is panel-only. Set it to a RedM weapon hash or name if you want captures to require that weapon/tool to be equipped. The resource does not spawn, grant, or otherwise manage that weapon.

Use the **Cutscene playback** panel to preview a camera rail locally when no live session is active, or play/pause/resume/stop it for the matching live session audience. A local preview has its own stop control, including when the rail loops. Flow graphs can use Play Cutscene, Wait for Completion, and Stop Cutscene nodes. A looping cutscene waits until stopped. Pausing a flow pauses its active cutscene; resume continues from the paused position. Stop, resource shutdown, and session end restore the camera and freeze state owned by playback.

Set `Config.Cutscenes.enabled = true` and grant `arachnid.storyteller.cutscenes` to enable playback. Each scene stores its own freeze, HUD, letterbox, loop, fade, and fallback FOV settings in `arachnid_storyteller_cutscene_settings`; defaults are freeze off, HUD unchanged, letterbox on, loop off, and fades off. Rail points remain in `arachnid_storyteller_camera_points`. The client creates the scripted camera and local presentation; the server selects the session audience and validates rail settings and duration.

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

Supported nodes include Start, Scene Beat, Delay, Branch, Random Branch, Set/Add/Subtract Variable, Set/Complete/Fail Objective, Wait for Objective, Wait for Area/All in Area/Area Empty, Check Player Count, Check VORP Job, Check Registered Entity Alive, AND/OR joins, NOT pass-through, Play/Wait/Stop Cutscene, Send Message, Freeze/Unfreeze, Set Health/Armor, Give/Remove/Strip Weapons, Teleport, Kill, VORP Respawn, VORP Change Job, NPC/prop encounter actions, registered world actions, audio/visual effects, and End. Variables reset for every run and can store numbers, text, or true/false values; arithmetic nodes require numeric values. Branch and count checks support equality and numeric ordering comparisons.

The server validates node types, scene, area, teleport, weapon, and VORP job references, connections, cycles, reachability, and graph limits before a flow starts. One Start node and at least one End node are required. Every branch output must connect to another node. Runs snapshot their graph, area geometry, and teleport markers at start, so later edits do not change a live run. A 32-node per-tick limit protects the server from long immediate chains.

Delay, objective, area, cutscene, and NPC-death waits pause their own graph path without a timeout. An objective wait continues through the matching completed or failed output. Area waits use connected audience participants: any entering, all currently connected participants entering, or the area becoming empty. AND joins wait for both A/B inputs; OR continues on the first input; NOT is the GMod-compatible pass-through. The storyteller can pause, resume, or end a flow from the session controls. Existing stories with no saved graph keep manual scene control.

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

## NPC and prop encounters

Grant `arachnid.storyteller.encounters` and set `Config.Encounters.enabled = true`. Add models to the server-owned ped and prop allowlists in `config.lua`; the lists start empty. Model names, NPC health, group size, total NPCs/props, and patrol wait time are checked on the server. For example:

```lua
Config.Encounters.pedModels = {
  a_m_m_farmer_01 = { label = 'Farmer', maxHealth = 200, weapons = { 'WEAPON_REVOLVER_CATTLEMAN' } }
}

Config.Encounters.propModels = {
  p_campfire01x = { label = 'Campfire' }
}

Config.Encounters.weapons = {
  WEAPON_REVOLVER_CATTLEMAN = { label = 'Cattleman revolver', ammo = 60 }
}

Config.Rts.enabled = true
Config.Rts.maxOrderDistance = 1000
Config.Rts.autoEngage = true
Config.Rts.autoEngageRange = 75
```

Use the **NPC**, **Prop**, or **Patrol waypoint** marker type in the story editor. The server captures each marker's position and heading from the storyteller's current in-game character. Markers are stored in `arachnid_storyteller_spawn_points`; live sessions use a start-time snapshot. Manual controls and flow nodes can spawn one NPC or a group, remove Arachnid-spawned NPCs/props, make NPCs hostile, select session participants as targets, author ordered patrol routes from saved waypoints, and wait for one/all tracked NPCs to die. `Config.Encounters.cleanupOnEnd` defaults to true. The resource also deletes tracked entities when it stops. OneSync server entity creation is required. Spawned entities are networked/shared with nearby players, including players outside the session audience.

### RTS command view and standalone sandbox

Enable `Config.Encounters.enabled` and `Config.Rts.enabled`, then grant `arachnid.storyteller.encounters`. The story RTS view is opened from the live encounter panel and can only command Arachnid-spawned NPCs in that story. The separate sandbox is available from the console when no story is live; enable `Config.Rts.allowStandalone = true` to use it. Only its owner can issue orders. The sandbox and a live story session cannot run at the same time. Closing the RTS view leaves the sandbox running; **Stop RTS and remove sandbox entities** removes its tracked NPCs, props, and pickups. They are also removed when the sandbox owner disconnects or the resource stops. Sandbox state is in memory and is not restored after a resource restart.

The board is a schematic top-down view of tracked NPCs, saved story patrol waypoints, pickups, and eligible players; it is not an in-world map texture. Left-click units to select them. Right-click the board to move; Shift + right-click uses the fastest configured pace. Choose Line, Column, or Wedge, then right-click to order that formation. Attack-move sends selected units toward a selected eligible player and engages that player if they come within `Config.Rts.attackMoveRange` (30 meters by default). Set `Config.Rts.autoEngage = false` to disable story-session automatic targeting; standalone NPCs stay passive unless the storyteller explicitly gives them a target or attack-move order. Fire at Will automatically assigns the nearest connected story participant within `Config.Rts.autoEngageRange` (75 meters by default), which is a server-side distance check, not line of sight. Return Fire holds until a participant damages that NPC; Hold Fire stops its attack order.

Name a group from the current selection, then use number keys to select the groups shown in the view. `Ctrl + number` assigns the selected NPCs to `Group 1` through `Group 9`. The `F`, `Z`, and `H` keys switch stances; `Q` attacks the chosen eligible player; `Space` stops selected units; `Esc` closes the RTS view. Movement pace, patrol dwell, formation spacing, spawn distance, and order distance are validated on the server. NPC weapons must appear in both the ped model's `weapons` list and `Config.Encounters.weapons` before they can be applied or toggled.

Direct possession is a separate, opt-in control mode. Set `Config.Rts.allowPossession = true`; a storyteller must be within `Config.Rts.possessionMaxDistance` (25 meters by default) of a tracked NPC. Possession follows that NPC with a camera, maps WASD and mouse movement to it, and uses left click to engage the selected eligible target. **E** or **Esc** releases control; releasing, removing the NPC, ending the session, disconnecting, and stopping the resource restore the storyteller's controls. This changes no player model and cannot possess arbitrary world NPCs.

The deploy panel offers models from the server allowlists. Spawn at the storyteller's current server-verified position, at a saved story marker, or arm a placement and right-click a tactical-board point. Board positions must be within `Config.Rts.maxSpawnDistance` (250 meters by default) of the storyteller's current server-verified position. NPC group size, health, entity totals, and model choices are server checked.

Weapon pickups are disabled by default. To enable them, set `Config.Encounters.allowWeaponPickups = true`, grant storytellers `arachnid.storyteller.playeractions` in addition to the encounters ACE, and add `pickupModel` to each pickup weapon in the server allowlist. The pickup model must also be in `Config.Encounters.propModels`. For example:

```lua
Config.Encounters.weapons = {
  WEAPON_REVOLVER_CATTLEMAN = { label = 'Cattleman revolver', ammo = 60, pickupModel = 'w_revolver_cattleman01' }
}
Config.Encounters.propModels = {
  w_revolver_cattleman01 = { label = 'Cattleman pickup' }
}
Config.Encounters.allowWeaponPickups = true
Config.Rts.allowStandalone = true
Config.Rts.allowPossession = true
```

The server tracks a networked display prop and accepts a pickup only when a connected player is within 2.5 meters. Anyone nearby can collect it with the context key; the server then grants the configured RDR3 weapon/ammo to that player's ped and removes the pickup. This is a base game weapon grant, not a VORP inventory item integration. Confirm pickup model visibility and weapon behavior on the target RedM/VORP build before enabling it on a live server. `Config.Rts.allowStandalone`, `Config.Rts.allowPossession`, and `Config.Encounters.allowWeaponPickups` default to false.

See [TESTING.md](TESTING.md) for the RedM live-server checklist.

## Registered world controls

World actions require `arachnid.storyteller.world`, `Config.World.enabled = true`, and a server-owned target entry. Targets are named in config; clients send only the stable target name and a requested operation. Never put client-provided entity IDs or script input strings in this configuration. Example shapes:

```lua
Config.World.enabled = true
Config.World.targets = {
  valentine_cell_door = {
    label = 'Valentine cell door', kind = 'door', doorHash = 123456789,
    actions = { open = true, close = true, lock = true, unlock = true },
    restoreOnSessionEnd = true, openRatio = -1.0
  },
  station_notice_board = {
    label = 'Station notice board', kind = 'entity',
    model = 'p_noticeboard01x', coords = { x = -176.0, y = 626.0, z = 114.0 }, radius = 3.0,
    actions = { enable = true, disable = true }, restoreOnSessionEnd = false
  }
}
```

Door targets need a valid door-system hash. Entity targets resolve by configured model and location. Each target must choose `restoreOnSessionEnd = true` or `false`; true restores the captured door/entity state, while false leaves the change in place. A `trigger` operation can call only the server event named in that target's config and must use the persistent policy. Unknown names and unconfigured operations are rejected. RedM server builds can differ in native availability; unsupported native state inspection or control is rejected at runtime.

## Audio and visual effects

Effects require `arachnid.storyteller.effects` and `Config.Effects.enabled = true`. Sound entries start empty; each entry maps a safe resource key to a RedM frontend sound and sound set:

```lua
Config.Effects.sounds = {
  arrival = { label = 'Arrival cue', name = 'CHECKPOINT_PERFECT', set = 'HUD_MINI_GAME_SOUNDSET' }
}
```

Flow nodes and live controls support Play/Stop Sound, Screen Fade, Announcement, Subtitle, and Screen Shake. Sound IDs, volume, pitch, text length, duration, amplitude, and frequency are checked against `Config.Effects`. Transient sounds, fades, overlays, and shakes are cleared when a session ends or the resource stops.

## Verification notes

For the RTS sandbox increment, `node --check` passed for `html/flow.js`, and the new NUI callbacks and client/server event names were checked. `git diff --check` passed. This checkout has no Lua parser, FXServer/RedM runtime, VORP server, or staging oxmysql database, so Lua parsing and the live scenarios in [TESTING.md](TESTING.md) still need a staging server before enabling possession or weapon pickups.
