# NPC RTS live-server checklist

The browser/Lua changes need an in-game pass on a RedM OneSync staging server. This workspace does not include the game server or clients needed for these checks.

## Setup

- Run with OneSync and oxmysql; enable `Config.Encounters.enabled` and `Config.Rts.enabled`.
- Grant the test storyteller `arachnid.storyteller.open`, `arachnid.storyteller.manage`, and `arachnid.storyteller.encounters`.
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
- Disconnect a selected target and verify the NPC clears that target. End the session with `cleanupOnEnd` both true and false; verify NPC orders stop, and verify entity cleanup follows the configured policy. Restart the resource and verify tracked entities are removed.
- Run the same movement and combat checks with the production RedM build and actual allowlisted RDR3 models/weapons; server-native/RPC behavior and NPC pathing can vary by build and network ownership.
