# DoTimer Plates

A **WoW Forever** addon for Shadow Priests and Warlocks: a compact list of every enemy carrying your DoTs, with its name, health bar and one icon + countdown per DoT. **DoTs spread by talents are included**, such as Devouring Plague jumping to nearby enemies when its target dies.

It is built as a companion to **DoTimer Forever** (by Xunga) and copies its look, but it works on its own.

## Why this addon exists

On WoW Forever, addons cannot read enemy auras during combat, and the combat log is not delivered to addons. Timer addons such as DoTimer therefore build their timers from **your casts**. A DoT that lands without a cast, such as a talent spreading Devouring Plague or Shadow Word: Pain, never shows up.

DoTimer Plates takes a different route. It uses the game's native aura display (`AuraContainer`, the same building block as ForeverAuras' "Aura (Modern)"). The addon configures it once, then **the game itself** decides which enemies have your DoTs, draws the icons and keeps the countdowns up to date. What you see is what is actually on the enemy, spread DoTs and talent-modified durations included.

## Features

- One block per enemy carrying at least one of your DoTs: `>> [level] name <<` (the arrows mark your target), raid mark, health bar and health percentage (option « % de vie »).
- One icon per DoT with its countdown, sorted by remaining time (next to expire first).
- Expiry warning: during the last seconds the countdown and a thin border around the icon blink in the warning color.
- Enemies without your DoTs take no space; the list stays compact.
- Works in the open world and in instances, where enemy names are hidden from addons.
- On first launch, the look of your DoTimer Forever profile is copied: sizes, colors, tenths of a second, warning threshold and blink rate.
- Options window: `/dtp`, or right-click the anchor while it is unlocked.
- Profiles: every character uses the shared **Commun** profile until you give it its own ("Profil propre à ce perso" copies the current settings). Use `<` / `>` to pick any existing profile, so several characters can share one.

Tracked spells, all ranks (the list follows your character's class):

- **Shadow Priest:** Shadow Word: Pain, Devouring Plague, Vampiric Touch, Void Plague, Hex of Weakness, Vampiric Embrace.
- **Warlock:** Corruption, Curse/Bane of Agony, Immolate, Siphon Life, Curse of the Elements, Curse of Weakness, Curse of Recklessness, Curse of Tongues, Curse of Exhaustion. Rank IDs come from DoTimer Forever's Warlock edition.

Channels (Mind Flay, Drain Life, Drain Soul, Drain Mana, Wrack) are not shown: they are not DoTs. The "All my debuffs" option shows every debuff you apply instead, which is also a fallback if a spell or rank is missing from the list.

## Installation

1. Download `DoTimerPlates-vX.Y.zip` from the [Releases](https://github.com/MrGrandjojo/DoTimerPlates/releases) page.
2. Extract it into `World of Warcraft\_classic_\Interface\AddOns\` (or the AddOns folder of your WoW Forever client). The result must be `Interface\AddOns\DoTimerPlates\DoTimerPlates.toc`.
3. Enable **enemy nameplates** in game (default key: `V`). The list follows the nameplates.

If you download the repository with *Code → Download ZIP* instead, rename the extracted folder from `DoTimerPlates-main` to `DoTimerPlates`.

## Commands

| Command | Effect |
|---|---|
| `/dtp` | Open / close the options window |
| `/dtp lock` | Lock / unlock the anchor (drag it while unlocked) |
| `/dtp status` | Diagnostics: build state and anything the game refused |
| `/dtp debug` | Debug mode: colored container backgrounds, nameplate tokens, nameplate log |

Settings marked `*` in the options window take effect after reloading the UI (the window has a reload button).

## Known limitations

These come from what the game allows, not from the addon:

- **An enemy without a visible nameplate is not listed**, for example when it is too far away, off screen, or its nameplate is removed by the game (in instances this can happen when you change target). The "Nameplate range" option raises the game's nameplate distance.
- **No predicted-damage bar and no fading icon.** Both would need the remaining time in Lua, which the game keeps secret. The warning blinks the countdown and the border instead.
- **Shadow Priest and Warlock only** for now. Other classes leave the addon idle.
- Warlock support is new and not tested in game yet: some WoW Forever-specific spells (runes, Curse of Doom, Curse of Shadow) are not in the list yet.
- Profile changes are refused during combat.
- The in-game texts (options, chat messages) are in **French** for now.
- The rank IDs of Hex of Weakness above rank 1 are not verified in game.

## Reporting a bug

Open an [issue](https://github.com/MrGrandjojo/DoTimerPlates/issues) with:

- a screenshot of the problem;
- the output of `/dtp status`;
- whether it happened in the open world or in an instance, in or out of combat.

## Credits

- **DoTimer Forever** by Xunga: the look and layout this addon reproduces. DoTimer Plates is an independent project, not affiliated with DoTimer.
- **ForeverAuras**: showed how the game's native `AuraContainer` can be driven on WoW Forever. No code was copied.

## License

[MIT](LICENSE)
