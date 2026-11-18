# Changelog

## 1.4

- Warlock support: Corruption, Curse/Bane of Agony, Immolate, Siphon Life and the curses (Elements, Weakness, Recklessness, Tongues, Exhaustion), all ranks. Rank IDs come from DoTimer Forever's Warlock edition. Channels (Drain Life, Drain Soul, Drain Mana, Wrack) are not shown.
- Profiles: a shared "Commun" profile (your previous settings) plus named profiles you create yourself (from the current settings). Each character picks its profile in a list; another profile's settings can be copied into the current one; a profile can be deleted or reset.
- Settings apply immediately, no reload needed: the buttons created by the game are kept and restyled (as ForeverAuras does). During combat, changes wait for the end of combat.
- Preview with 1 to 10 fake targets (option at the bottom of the window, or `/dtp test`). Off when combat starts and when the window closes.
- Options window with tabs (General, Layout, Icons, Profiles), modeled on DoTimer Forever 0.9.6.
- Health percentage at the right of the health bar, which grows from 3 to 5 px (option « % de vie », on by default).

## 1.3

- The warning border is clipped to the icon cell: a thin 1 px border, like DoTimer.
- The countdown text keeps the game font's drop shadow (better contrast, like DoTimer).

## 1.2

- Expiry warning border around the icon, blinking with the countdown.

## 1.1

- Expiry warning: the countdown blinks in the warning color during the last seconds.
- "Nameplate range" option (game setting `nameplateMaxDistance`).

## 1.0

- First stable version: DoTimer look (copied from the DoTimer Forever profile on first launch), icons sorted by remaining time, raid marks, options window (`/dtp`).
- Mind Flay removed from the tracked spells (a channel, not a DoT).
