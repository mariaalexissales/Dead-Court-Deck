# Dead Court Deck

A collectible card mod for Project Zomboid Build 42. Packs spawn in the world,
each one rolls 5 cards out of 352, and a completed suit is traded back in for
loot an admin defines in JSON.

Server-authoritative, so it works the same in singleplayer and on a dedicated
server. Needs **42.20+**.

> **The card art is third-party and its licence has an edge to it.** TTRPG
> Legacy [Cards] by [Ddant1100](https://ddant1100.itch.io) permits use in any
> project, commercial or not, but forbids "directly distributing... parts or the
> entirety of an asset, edited or not". A Workshop mod ships the images as loose
> icon files. That was a judgement call, not an oversight. Credit is required
> and is in `mod.info` and `workshop.txt`.

## The deck

Four suits, thirteen ranks, four finishes. **352 cards**, plus the pack itself.

| | |
| --- | --- |
| Suits | Hearts, Diamonds, Clubs, Spades |
| Ranks | A, 2–10, J, Q, K |
| Finishes | Standard, Bronze, Silver, Gold |
| Races | Human, Goblin, Elf, Dwarf — **court cards only** |

Jack, Queen and King carry a race. The Ace does not, because the art has no race
version of it. That is the whole reason the split exists.

```
raceless   4 suits x 10 ranks x 4 finishes  = 160
court      4 suits x  3 ranks x 4 races x 4 = 192
                                              352 + 1 pack
```

A **full suit** is 13 cards: Ace through 10, plus a Jack, Queen and King. All 13
in one finish, all three courts of one race. `Gold Goblin Hearts` is a set. A
Gold Jack beside a Silver Queen is not.

Every variant is its own script item rather than one item wearing modData, so
each has a real icon and name, stacks properly, and survives save/load and MP
sync without re-skinning.

| Kind | Full type | Icon |
| --- | --- | --- |
| Raceless | `DeadCourtDeck.Card_Hearts_7_Bronze` | `Item_DCD_Hearts_7_Bronze.png` |
| Court | `DeadCourtDeck.Card_Spades_K_Goblin_Gold` | `Item_DCD_Spades_K_Goblin_Gold.png` |
| Pack | `DeadCourtDeck.CardPack` | `Item_DCD_CardPack.png` |

## Build

Two PowerShell scripts, no dependencies beyond `System.Drawing`. They live in
[estral-tools](https://github.com/mariaalexissales/estral-tools), cloned next to
this folder, and read the mod out of the working directory — so run them from
here, in this order. The second one reports art the first one failed to produce.

```bash
powershell -ExecutionPolicy Bypass -File ../estral-tools/dead-court-deck/build_icons.ps1
powershell -ExecutionPolicy Bypass -File ../estral-tools/dead-court-deck/gen_cards.ps1
```

`build_icons.ps1` crops every source card at a fixed `(99, 35) 314x442`, fits it
to 64x64 and centres it on a transparent square. Pass `-Source` if the art pack
lives somewhere other than `~/Downloads/ttrpg_legacy_cards_1.1`. Twelve source
files are misspelled upstream (`ace_of_space`, `human_queen_club_of`); an alias
map catches those, and a token-set index catches any others.

`gen_cards.ps1` writes `DCD_items.txt` and `ItemName.json` from the same suit,
rank, race and finish lists that `DCD_Core.lua` loops over. **Change a list in
one, change it in the other**, or the Lua card table and the item scripts drift
apart. It prints `all icons present` when 353 items have 353 icons.

## Layout

```
Contents/mods/DeadCourtDeck/42/media/
  scripts/DCD_items.txt        GENERATED   353 item definitions
  textures/Item_DCD_*.png      GENERATED   353 icons at 64x64
  DeadCourtDeck/rewards.json               shipped reward table
  sandbox-options.txt
  lua/shared/DCD_Core.lua                  card model, set maths, helpers
  lua/shared/DCD_Json.lua                  json parser, tolerant of hand edits
  lua/shared/DCD_Net.lua                   sp direct-call / mp command bridge
  lua/server/DCD_Packs.lua                 pack rng
  lua/server/DCD_Commands.lua              openPacks, tradeSuit
  lua/server/DCD_Rewards.lua               reward table, seeding, payout
  lua/server/DCD_Distributions.lua         world loot
  lua/server/DCD_ZombieDrops.lua           corpse drops
  lua/client/DCD_ContextMenu.lua           right-click menus
  lua/client/DCD_ClientState.lua           halo feedback
```

## Rewards

The payout is keyed to the **race** of the suit's court cards, multiplied by its
**finish**. First run writes the table and never touches it again, so admin
edits survive restarts and Workshop updates.

First match wins:

```
Zomboid/Lua/DeadCourtDeck/rewards.json     written on first run
Zomboid/Lua/DeadCourtDeck_rewards.json     fallback if the folder can't be made
<mod>/42/media/DeadCourtDeck/rewards.json  shipped copy
```

```json
{
  "rarityMultiplier": { "Standard": 1, "Bronze": 2, "Silver": 3, "Gold": 5 },
  "races": {
    "Human": { "items": [ { "item": "Base.MetalPipe", "count": 2 } ] }
  }
}
```

Counts are multiplied by the finish, floored, minimum 1 — a Standard Human suit
pays 2 pipes, the Gold one pays 10. **What ships is placeholder junk**; replace
it.

`grant` re-reads the file on every trade-in, so edits apply to the next trade
with no restart and nobody kicked. A broken edit keeps the last good table and
says what upset it in the log, instead of everyone's payout quietly becoming
nothing. Unknown races, bad counts and item ids that resolve to nothing are each
warned about by name at load.

## Sandbox options

| Option | Default | |
| --- | --- | --- |
| `CourtChance` | 10 | % chance per card to be a J/Q/K |
| `StandardWeight` | 70 | finish weights, relative to each other |
| `BronzeWeight` | 20 | |
| `SilverWeight` | 8 | |
| `GoldWeight` | 2 | |
| `RaceWeight{Human,Goblin,Elf,Dwarf}` | 25 | which races turn up |
| `PackLootWeight` | 1.0 | world spawn multiplier, 0 disables |
| `ZombieDropChance` | 1.0 | % per zombie killed, 0 disables |

Packs go into the loot tables vanilla already puts a `CardDeck` in — dressers,
nightstands, desks, rec room shelves, school lockers, toy and hobby shelves.
Weights are recomputed from a recorded base each time the sandbox loads, so
re-running never compounds them.

At those defaults, simulated median packs opened before a first complete set:

| Standard | Bronze | Silver | Gold |
| --- | --- | --- | --- |
| 61 | 233 | 563 | 2064 |

Gold is a long-haul chase by design. Raise `CourtChance` if that is too much
grind for your server — 20% roughly halves the first set.

## Multiplayer

The client sends intent, never outcomes. `openPacks` carries item ids and
`tradeSuit` carries a suit/race/finish, and the server re-derives everything
else from its own copy of the inventory — a crafted packet cannot open a pack
you are not carrying or trade a suit you do not hold. A trade takes all 13 cards
or none: every card is confirmed present before any is removed.

`DCD_Net` bridges both worlds. With no remote server the "send" is a direct call
into the handler that would have received it, so singleplayer runs the same
authoritative code path a dedicated server does.

Rate limits are runtime-only — they have no business in a save file.

## Credits

Card art is **TTRPG Legacy [Cards]** by
[Ddant1100](https://ddant1100.itch.io). See the note at the top.

Code by Estral. [Ko-fi](https://ko-fi.com/estralexe) ·
[Twitch](https://www.twitch.tv/estralexe)

## More from Estral

- **[Pinoy Pantry](https://steamcommunity.com/sharedfiles/filedetails/?id=3791631305)**: sarap ng Pinas in Knox Country ([source](https://github.com/mariaalexissales/Pinoy-Pantry))
- **[Quest System Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3794717412)**: add quests to your multiplayer servers ([source](https://github.com/mariaalexissales/Quest-System-Framework))
- **[Player Leaderboard System](https://steamcommunity.com/sharedfiles/filedetails/?id=3795596462)**: have your players fight for first place, or keep track of your best lives in solo ([source](https://github.com/mariaalexissales/Leaderboard-Framework))
- **[Remove Vanilla Anything](https://steamcommunity.com/sharedfiles/filedetails/?id=3799346338)**: for those who are tired of seeing vanilla items in their heavily modded servers
- **[Bundle Up! - A Packing Mod](https://steamcommunity.com/sharedfiles/filedetails/?id=3746632343)**: to organize all of your excessive stuff ([source](https://github.com/mariaalexissales/Bundle-Up))
- **[LAPLACE//DAEMON](https://steamcommunity.com/sharedfiles/filedetails/?id=3809376465)**: every blade you forge rolls a rarity, and a fortune ([source](https://github.com/mariaalexissales/LAPLACE-DAEMON))
