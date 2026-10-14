# SessionRecap

A running tally of your play session: time, money, experience, quests, loot and gathering. One addon, one repository: `bizzal70/SessionRecap`.

## Workflow

- **No local `.git`.** GitHub holds all history. Publish with `tools\Publish.ps1 -Message "..."`, which uses a throwaway temp clone and runs the tests first.
- **Layout:** the addon's own files (`SessionRecap.toc` and the Lua files) sit at the top of the project, because that is what the release packager expects. `tests/`, `tools/`, `media/` and `.github/` are development-only and are left out of the released zip by `.pkgmeta`.
- **Testing in game:** `tools\Link-Addon.ps1` junctions this folder into the client's `Interface\AddOns` as `SessionRecap`. Edits are live after `/reload`; a new file or a TOC change needs a full client restart.
- **Client install:** `C:\Program Files (x86)\World of Warcraft\_classic_beta_\` (`WowB.exe`). Expect a different flavor folder after launch (reported for 2026-11-04); pass `-Flavor` to the link script then.
- **Tests:** `python tests/run.py` runs the addon in real Lua 5.1 (the `lupa` pip package) against a fake WoW API in `tests/wow_stub.lua`, loading the files the TOC lists. The tests run before every publish and again on GitHub. They prove the addon's own logic only; whether the real client behaves like the stub can only be checked in game. Earlier bugs in sibling addons were wrong assumptions about the game that the fake shared, so anything that calls a game function runs under `pcall` and a surprise ends in a chat line, not an error box.
- **Releases:** a tag starting with `v` runs `.github/workflows/release.yml`, which uses the BigWigs packager (it recognises this client and builds `-forever.zip` as game version 1.60.1). CurseForge and Wago uploads are skipped until their project IDs are in the TOC and their tokens are in the repository secrets.
- **This repository may be made public.** Keep character names, account details and machine-specific paths out of it.

## How it works

- Per character: `SessionRecapCharDB.current` (the session in progress) and `.history` (up to 10 ended sessions, newest first). Account-wide: `SessionRecapDB` holds settings only.
- A session carries on across a login or reload if its `last` timestamp is within `SESSION_GAP` (15 minutes); otherwise it is filed (if at least 2 minutes long) and a new one starts. `last` is refreshed on every tallied event and by a 30-second ticker.
- Money: differences in `GetMoney` on `PLAYER_MONEY`, rises and falls kept apart. Experience: differences in `UnitXP` on `PLAYER_XP_UPDATE`; when `UnitLevel` has risen, the rest of the old level plus the new level's progress. Quests: `QUEST_TURNED_IN`. Deaths: `PLAYER_DEAD`.
- Gathering: `UNIT_SPELLCAST_SUCCEEDED` for the player with a spell named "Mining", "Herb Gathering" / "Herbalism" or "Skinning" (the first three confirmed on Forever by GatherTrail).
- Loot: `CHAT_MSG_LOOT` matched against patterns built from the game's own `LOOT_ITEM_SELF`, `LOOT_ITEM_SELF_MULTIPLE`, `LOOT_ITEM_PUSHED_SELF` and `LOOT_ITEM_PUSHED_SELF_MULTIPLE` strings, so it follows the client's language; the item name is the bracketed part of the link.
- Every tally handler runs under `pcall`.
- Not run in the real game when written (2026-10-13). Unverified: whether chat loot text is readable by addons on Forever, and whether those four strings exist under those names.

## Client facts

Everything below, unless marked verified, comes from community sources during the beta (Warcraft Wiki, GitHub ports, fan guides), not from Blizzard docs. Builds change. Verify in game before relying on any of it.

- Local client was 1.60.1.70338 on 2026-10-11 (read from `WowB.exe`).
- TOC: `## Interface: 16001` (verified in game on build 70338).
- TOC flavor suffix is `_Forever.toc` or `_Camelot.toc`. The TOC `[Game]` variable expands to `Camelot`. Game type for `AllowLoadGameType` is `forever` / `camelot`.
- The client is Retail-based: Midnight 12.x API and UI architecture, not the Classic API. Port from Retail code.
- `WOW_PROJECT_ID` is `18` on build 70338 (verified in game 2026-10-11, along with interface 16001, by a starter addon since removed). Community guides written against earlier builds say it is 1 (`WOW_PROJECT_MAINLINE`); that is out of date, so Retail code gated on `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` will not run here. The name of the constant for 18 is not yet known. Prefer testing for the specific API you need over branching on either number.
- Lua 5.1: no `goto`, no `//`, no bitwise operators (use `bit.band` etc.), no `require`. The TOC is the module loader. Start files with `local addonName, ns = ...`.
- Removed globals: `GetItemInfo`, `GetSpellInfo`, `UnitAura`/`UnitBuff`/`UnitDebuff`, `GetTalentInfo`, `GetNumTalentTabs`, `CombatLogGetCurrentEventInfo`, `InterfaceOptionsFrame_OpenToCategory`. Use `C_Item`, `C_Spell`, `C_UnitAuras`, `C_Traits`, and the `Settings` API.
- `C_Spell.GetSpellInfo` returns a table. Item and spell data can be nil until cached.
- Registering an event that does not exist throws and aborts the file. Wrap speculative `RegisterEvent` calls in `pcall`.
- Secret values (Midnight combat restrictions) are active. In combat, `UnitHealth`, aura data, and some names and booleans can be secret: arithmetic, comparison, and printing fail. Guard with `issecretvalue`, and pass values straight to widgets (`StatusBar:SetValue`, `Cooldown:SetCooldownFromDurationObject`) instead of doing Lua math. Combat-log parsing is not available.
- Check `InCombatLockdown()` before touching protected frames and defer to `PLAYER_REGEN_ENABLED`.
- SavedVariables: initialise in `ADDON_LOADED`. Early beta builds reportedly wrote them but did not read them back; on build 70338 they are read back (confirmed in game 2026-10-11).
