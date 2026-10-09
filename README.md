# Duel Tracker (alpha 0.1)

A World of Warcraft addon that records your duels: who won, how it ended, the fight's
length, both players' health and specs, and your record against every opponent. Duels
against friends who also run Duel Tracker can be played as **Elo duels** that count
toward a rating.

> Alpha: largely untested in game so far. Expect bugs, and please report them.

## Features

- **Duel history**: every duel is recorded automatically, with filters by opponent,
  result, how it ended, class, spec, time and Elo.
- **Opponents**: your overall record, recent duels and your wins and losses against
  each player.
- **Duel log**: health at the start and end, how one-sided the fight was and, when
  enabled, the combat log written to the game's `Logs` folder during duels.
- **Duelists**: a friends list of players you play Elo duels with, shown as a ranking
  by rating that includes you.
- **Elo duels**: challenge a duelist, they get an Accept/Decline popup, and the next
  duel between you within a minute is an Elo duel. Both addons swap ratings and
  compute the same change (standard Elo, start 1500, K = 32).
- **Result check**: when both players have Duel Tracker, the two addons compare the
  result. A disputed Elo duel doesn't count for the rating.
- **Rating sync**: targeting a duelist quietly swaps current ratings with them (at
  most every 5 minutes).
- **Right-click menu**: add, challenge or remove duelists from Blizzard's player menus.

## Trust

Elo duels and rating updates only happen between players who have **each other** on
their Duelists lists. Ratings and results are reported by the players' own addons and
are not verified beyond that, so only add players you trust.

All communication between addons uses hidden addon whispers. Nothing appears in chat,
and nothing is sent to players who aren't on your list.

## Commands

| Command | What it does |
|---|---|
| `/duels` | Open or close the window |
| `/duels record` | Print your record against everyone |
| `/duels <name>` | Print your record against that player |
| `/duels add [name]` | Add a duelist (your target without a name) |
| `/duels remove <name>` | Remove a duelist |
| `/duels elo [name]` | Challenge a duelist to an Elo duel (your target without a name) |
| `/duels duelists` | Open the Duelists tab |
| `/duels minimap` | Show or hide the minimap button |
| `/duels test [count]` | Add made-up test duels and duelists |
| `/duels cleartest` | Remove all test duels and test duelists |

## Installation

Copy the `DuelTracker` folder into `World of Warcraft\<game version>\Interface\AddOns`
and reload the game. Data is saved account-wide in `DuelTrackerDB`.

## Credits

Made by **mitschnack0r**.

Built with AI assistance: most of the code was written by Claude (Anthropic) under
mitschnack0r's direction. The design, decisions, review and testing are
mitschnack0r's.

## License

[MIT](LICENSE): free to use, change and share, as long as copies keep the copyright
notice and the license text.
