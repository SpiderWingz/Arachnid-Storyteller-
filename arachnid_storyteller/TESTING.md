# NPC RTS live-server checklist

The browser/Lua changes need an in-game pass on a RedM OneSync staging server. This workspace does not include the game server or clients needed for these checks.

## Setup

- Run with OneSync and oxmysql; enable `Config.Encounters.enabled` and `Config.Rts.enabled`.
- Enable `Config.Rts.allowStandalone` for the sandbox checks, `Config.Rts.allowPossession` for possession checks, and `Config.Encounters.allowWeaponPickups` for pickup checks; these all default off.
- Grant the test storyteller `arachnid.storyteller.open`, `arachnid.storyteller.manage`, and `arachnid.storyteller.encounters`. Grant `arachnid.storyteller.playeractions` only for weapon-pickup checks.
- Add a test ped model and at least one patrol waypoint. Add a weapon to both `Config.Encounters.weapons` and the ped model's `weapons` list for weapon-toggle checks.
- Start a session with at least two connected participants and leave another connected player outside a selected-player audience for audience-isolation checks.

## Checks

- Confirm the RTS view opens only during the active story and closes when the session ends, the main NUI closes, or the storyteller changes sessions.
- Spawn one NPC and a group; select individual and multiple units from the board and roster; verify snapshots show current position, health, stance, order, and configured weapons.
- Right-click nearby open ground to move; Shift + right-click to move at the configured maximum pace. Test saved-waypoint move, multi-waypoint patrol, reorder/remove route points, stop/hold, zoom, pan, and Fit units. Try clear and obstructed paths and confirm unreachable orders report as stuck.
- Confirm orders beyond `Config.Rts.maxOrderDistance`, invalid waypoint IDs, unknown NPC IDs, invalid speeds, and disconnected attack targets are rejected server-side.
- Confirm Fire at Will targets only the nearest connected participant in the live audience inside the configured range; `autoEngage = false` should require explicit target orders.
- Confirm Return Fire holds until an audience participant damages the NPC, Hold Fire cancels attacks, and changing back to Fire at Will resumes automatic engagement.
- Toggle a configured weapon for one unit and for a compatible multi-selection. Confirm an unconfigured or non-shared weapon cannot be toggled and disabled weapons stop attack orders.
- Assign a name to a selection, spawn another group with the same name, select it from the group controls, and use the number/Control+number shortcuts. Confirm group assignment is limited to selected tracked NPCs.
- Test Line, Column, and Wedge formation destinations with small and large selections, including invalid spacing and destinations beyond `Config.Rts.maxOrderDistance`.
- Test attack-move against a connected eligible target in a story. Confirm it engages only the selected eligible target within `Config.Rts.attackMoveRange`; in standalone mode confirm NPCs stay passive until an explicit target/order is given.
- With `Config.Rts.allowPossession = true`, move a storyteller within `Config.Rts.possessionMaxDistance`, possess exactly one tracked NPC, move it with WASD, engage the selected target, and release with E and Esc. Confirm the storyteller's original position/frozen state is restored. Try a distant NPC, an already possessed NPC, and an NPC outside the current session/sandbox; those requests must fail.
- With `Config.Rts.allowPossession = false`, confirm the possession control is disabled and server requests are rejected.
- With `Config.Rts.allowStandalone = true`, start RTS with no live story, deploy an allowlisted NPC and prop at the storyteller position and on a nearby board point, then close and reopen the view. Confirm the sandbox remains active, snapshots still work, and a live story cannot start until the sandbox is stopped.
- Try a board spawn farther than `Config.Rts.maxSpawnDistance`, an unlisted ped/prop, an excessive group size/health, and a spawn marker from another story; confirm the server rejects each request.
- Stop the standalone sandbox and confirm all sandbox entities disappear. Repeat with the owner disconnecting and with the resource stopping. Verify a second storyteller cannot control the active sandbox.
- For pickup checks, configure `allowWeaponPickups`, add a weapon `pickupModel` and the same model to the prop allowlist, and grant the playeractions ACE. Spawn a pickup, collect it from within 2.5 meters, then try from farther away and with a forged/duplicate pickup ID. Confirm only the first eligible nearby collection grants the configured weapon/ammo and removes the networked prop for everyone. Confirm the default-off toggle and missing/invalid model fail closed.
- Disconnect a selected target and verify the NPC clears that target. End the session with `cleanupOnEnd` both true and false; verify NPC orders stop, and verify entity cleanup follows the configured policy. Restart the resource and verify tracked entities are removed.
- Run the same movement and combat checks with the production RedM build and actual allowlisted RDR3 models/weapons; server-native/RPC behavior and NPC pathing can vary by build and network ownership.
