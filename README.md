<p align="center"><img src="docs/logo.png" alt="ItemInfo Forever" width="200"></p>

# ItemInfo

**An in-game item encyclopedia for World of Warcraft: Forever.**

Search every item in the game, see how it is crafted, what it is used for,
which recipe teaches it and who sells that recipe, in a window of its own and
in every item tooltip. No dependencies: the database ships with the addon.

## Features

### Encyclopedia window

![The encyclopedia window: a category tree, search results and the details of Green Silk Pack](docs/screenshots/window.png)

- **Search every item.** Type any part of a name: `green` lists everything
  with "green" in it. Works in your client's language.
- **Browse by category.** A tree of the game's own item classes and
  subclasses, plus every profession with its recipes ordered by skill.
- **How it's made.** Profession, required skill, when the recipe turns
  yellow and green, reagents and the amount created.
- **Where the recipe comes from.** The recipe item, the vendors who sell it
  with their zone and coordinates, the creatures that drop it, or whether a
  trainer teaches it.
- **What it's used for.** Every recipe the item is a reagent of.
- **Quest rewards.** The quests that reward the item, with their level, zone
  and quest giver.
- **Prices.** What a vendor pays you for the item, and what a vendor charges
  for it once you have visited one.
- **Everything is a link.** Click a reagent, a product or a recipe to open
  it, *Back* returns. Shift-click links the item in chat.

### Item tooltips

Hover an item anywhere (bags, auction house, vendors, chat links) and its
tooltip gains:

- the profession and skill that make it, with the reagents,
- where to get the recipe, limited to vendors of your faction,
- the quests that reward it, with their level and zone,
- which vendors sell the item itself, the nearest first, with coordinates
  for those in your zone,
- which creatures drop it, or that it is a world drop,
- the recipes it is used in, with the icons of the professions involved.
  Hold **Shift** to unfold a long list.

![Item tooltips: how an item is made, where its recipe is sold, and what it is used in](docs/screenshots/tooltips.png)

The quests that reward an item, colored by difficulty:

![Idol of Shifting Tides: the quests that reward it, with their level and zone](docs/screenshots/tooltip-quests.png)

The vendors of an item, the nearest first:

![Sweet Nectar: its vendors, the nearest first with coordinates](docs/screenshots/tooltip-vendors.png)

The creatures that drop an item:

![Krol'dok Warplate Chest: the creature that drops it](docs/screenshots/tooltip-drops.png)

Holding **Shift** unfolds the full list:

![Holding Shift unfolds every recipe Golden Pearl is used in](docs/screenshots/tooltip-shift.png)

Turn it off with `/iteminfo tooltip` if you only want the window.

### Item database

- Scanned from your client in the background on first login; items found so
  far are searchable while it runs. It pauses in combat and resumes after a
  logout.
- Scanned again by itself only after a game patch. Otherwise it is updated
  when you ask for it, and items you come across in game are added right away.
- On every login, ItemInfo reports the state of the database in chat.

### Update notice

Addons cannot reach the internet, so ItemInfo compares versions with the
other ItemInfo users of your guild and group. When one of them has a newer
version, a single line in chat tells you so.

## Installation

1. Download the latest release, or this repository.
2. Copy the `ItemInfo` folder into
   `World of Warcraft/_forever_/Interface/AddOns/`.
3. Restart the game. The first scan starts a few seconds after login.

## Usage

Click the book icon on the minimap, or use a command:

| Command | |
| --- | --- |
| `/iteminfo` or `/ii` | Open or close the window |
| `/iteminfo <name>` | Search, and open the item if the name is exact |
| `/iteminfo <link or ID>` | Open an item |
| `/iteminfo update` | Look for items missing from the database |
| `/iteminfo rebuild` | Rebuild the item database from scratch |
| `/iteminfo tooltip` | Show or hide the crafting info in item tooltips |
| `/iteminfo minimap` | Show or hide the minimap button |
| `/iteminfo help` | List the commands |

Other addons and macros can call `ItemInfo.Toggle()`, `ItemInfo.Search(text)`
and `ItemInfo.ShowItem(itemId)`.

## Languages

Item, spell, profession and zone names come from the game client, so they are
always in your language, and each language keeps an item database of its own.

The interface is translated to German, French, Spanish, Portuguese, Italian,
Russian, Korean, Simplified and Traditional Chinese. Vendor names are
localized for the same languages. To add or fix a translation, edit
`ItemInfo/Locales/Locales.lua`.

## Known limits

- Items that are hidden until they first drop on your server cannot be
  scanned. Run `/iteminfo update` to look for them again.
- Enchants are listed by their spell, since they create no item.
- The skill at which a recipe turns yellow and green is unknown for the
  recipes that are new in Forever.
- What a vendor charges is not part of the shipped data, it is recorded when
  you open a vendor.

## Development

```
ItemInfo/        the addon
  Core/          scanner, lookups, tooltips, slash commands
  UI/            window, lists, minimap button
  Data/          generated recipe, vendor, NPC and quest data
  Locales/       interface translations
  Media/         logo
tools/           data generator
tests/           offline test harness
```

`tools/gen_data.py` regenerates `ItemInfo/Data` from a local AddOns folder
that holds AtlasLootContinued and QuestieDB. `tests/harness.py` loads the
addon in Lua 5.1 against a stubbed WoW API with a simulated item server, and
runs a scenario over the scan, the search, the window and the tooltips:

```sh
pip install cbor2 lupa
python3 tools/gen_data.py "<path to Interface/AddOns>" ItemInfo/Data
python3 tests/harness.py          # enUS
python3 tests/harness.py deDE     # any other locale
```

## Releasing

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager)
on GitHub Actions and uploaded to CurseForge and GitHub:

```sh
git tag -a v1.0.0 -m "v1.0.0"
git push origin v1.0.0
```

A tag containing `beta` or `alpha` (`v1.0.0-beta1`) is published as such. The
tests run first, a failing test stops the release. The version in the TOC is
filled in from the tag, and the changelog from the commits since the last tag.

One-time setup:

1. Add `## X-Curse-Project-ID: <id>` to `ItemInfo/ItemInfo.toc`, the ID is on
   the project's CurseForge page.
2. Create a [CurseForge API token](https://authors.curseforge.com/#/settings/api-tokens)
   and save it as the repository secret `CF_API_TOKEN`.

## Credits and license

ItemInfo is released under the GPL-2.0, see `ItemInfo/LICENSE`.

- Recipe data is derived from **AtlasLootClassic** (GPL-2.0).
- Vendor, drop, NPC and quest data is derived from **QuestieDB**.
- The item scan is adapted from **ItemAutocomplete** by Elliott Linder (MIT).

The details are in `ItemInfo/NOTICE.md`.
