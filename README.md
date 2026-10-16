# SessionRecap

A running tally of your play session: time, money, experience, quests, loot and gathering. An addon for World of Warcraft: Forever (client 1.60.x).

## What it does

SessionRecap keeps count while you play, so at any point you can see how the session is going:

- time played
- money in, money out, and the difference
- experience gained, experience per hour, and a level bar with how long the rest of the level will take at this pace
- levels gained, quests handed in, deaths
- what you gathered (ore, herbs, skins)
- the items you looted most, with their icons

It also keeps your last ten sessions on each character, to compare against.

## Using it

Type `/session`, or click the pocket-watch button on the minimap, to open the window. The figures update as you play. Counting starts by itself when you log in, with one line in chat to say so.

| Command | What it does |
|---|---|
| `/session` | Open the window |
| `/session report` | Sum the session up in chat |
| `/session new` | Start a new session now |
| `/session greet` | The line about your session when you log in, on or off |
| `/session button` | Show or hide the minimap button |
| `/session debug` | What the game has reported this login, to explain a count that stays at zero |

## What counts as a session

A session belongs to one character. Logging out and back in, or reloading the interface, within 15 minutes carries on the same session. After a longer break a new one starts, and you get one line in chat about the last one.

## Good to know

- **Gathering is counted by casts**: each time you mine, pick a herb or skin.
- **Loot is read from the game's own chat lines**, so it counts what you personally received.
- **Nothing is sent anywhere.** It is all saved on your own computer.

## More from this author

Other small addons for World of Warcraft: Forever, all free:

- **[GatherTrail](https://github.com/bizzal70/GatherTrail)** remembers ore, herbs, fishing pools, skinning spots, chests and rares across all your characters, and guides you back to the best spots.
- **[MouseTip](https://www.curseforge.com/wow/addons/mousetip)** shows tooltips at your mouse cursor.
- **[RangeShade](https://www.curseforge.com/wow/addons/rangeshade)** shades action buttons red when your target is out of range.
- **[VendorMate](https://github.com/bizzal70/VendorMate)** sells junk and repairs at vendors, and warns when your gear is wearing out.
- **[AltBoard](https://github.com/bizzal70/AltBoard)** shows all your characters at a glance: level, gold, rested and where you left them.
- **[SwiftQuest](https://github.com/bizzal70/SwiftQuest)** accepts quests and hands them in as soon as you talk to the quest giver, without ever choosing a reward for you.

## Installing

Copy this folder into `World of Warcraft\_classic_beta_\Interface\AddOns\` as `SessionRecap`, restart the game, and enable SessionRecap on the character select screen.

## Developing

- `tools\Link-Addon.ps1` links this folder into the game's AddOns folder, so edits are live after `/reload`.
- `python tests/run.py` runs the tests (`pip install lupa` once). They run the addon in real Lua 5.1 against a fake of the game's API.
- `tools\Publish.ps1 -Message "..."` runs the tests and pushes to GitHub. GitHub runs the tests again on every push.

## Releasing

`tools\Publish.ps1 -Message "Release x.y.z" -Tag vx.y.z` publishes and tags. The tag makes GitHub package the addon and attach the zip to a GitHub release.

To also upload to CurseForge and Wago, two things are needed once:

1. Create the project on each site, then add its ID to `SessionRecap.toc`:
   `## X-Curse-Project-ID: 123456` and `## X-Wago-ID: abc123`.
2. Create an upload token on each site and add it to this repository's secrets (Settings, Secrets and variables, Actions) as `CF_API_KEY` and `WAGO_API_TOKEN`.

Before each release: raise `## Version:` in `SessionRecap.toc` and add the version to `CHANGELOG.md`.

## Licence

MIT. See `LICENSE`.
