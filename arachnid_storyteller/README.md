# Arachnid Storyteller

Arachnid Storyteller is a standalone RedM gamemaster foundation. Its panel takes visual inspiration from the Jonesy Admin interface, but it has no Jonesy Admin dependency.

## Current phase

- Create and maintain story arcs with draft, published, and archived status.
- Build ordered scene beats with objectives.
- Optionally save a scene beat at the storyteller's server-verified in-game position.
- Record all administration actions in MySQL.

The first release deliberately stores and organizes story data only. It does **not** spawn peds, control players, start cutscenes, or execute scenes. Those runtime capabilities should be added as explicitly designed, permission-checked phases.

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

Saving a world location requires server-side player coordinates, so enable OneSync if your RedM setup does not already provide them.
