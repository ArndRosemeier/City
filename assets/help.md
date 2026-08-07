# EccentriCity — Help

An endless voxel city you can carve, fight in and rebuild. Nothing is on rails: walk out of
the door, find gems, unlock powers, and pick which kind of district you want to be standing in.
Created by Arnd Rosemeier using Cursor (mainly Grok 4.5 high with Opus 5 acting as as specialist
for hairy cases and art direction). Contact: eccentricity@futuremagic.de

## Moving around

- `W` `A` `S` `D` walk and turn, arrow keys work too.
- `Shift` sprints, `R` toggles autorun, `Space` jumps — hold it while airborne to keep rising.
- Hold `RMB` to look around; the mouse wheel zooms the camera in and out.
- `E` interacts with whatever you are facing.
- `J` opens the district picker and teleports you to the nearest tile of the type you choose (needs to be unlocked).

The compass at the top of the screen names your heading, and the minimap shows buildings,
monsters and infection tips within 100 m of you.

## Health and energy

The bar at the bottom is energy: every shot, power and shield tick spends it, and it refills
on its own when you stop spending. Health sits above it and does not come back nearly as fast,
so a fight you cannot finish is a fight worth walking away from.

## Fighting

- `LMB` fires the blaster, a fast cheap beam that also carves voxels.
More weapons can be unlocked (even some area attacks)

Most things in the city ignore you until you shoot them. Wanted posters are the clearest
example: the killer on the bill is an ordinary pedestrian walking the same tile, and only
becomes a monster once you take the first swing.

## Abilities and the tray

The tray across the bottom has nine slots: `F1`–`F6` plus the three mouse chords. Hold
`Shift` and press a slot key to reassign it, or `Shift+click` a tray button.

Abilities are bought with gems from the Inventory panel:

- **Charged blast**, **Laser**, **Stomp** — extra weapons.
- **Shield** — toggle, drains energy while up and blunts every hit.
- **Grow** and **Shrink** — temporary size changes.
- **Minion** — a half-strength ally; summoning a new one retires the old.
- **District hop** — the `J` teleport.
- **Tetris** — summons a playable cabinet in the street.
These are just examples, there is a lot more.

## Inventory, gems and crafting

`I` opens the inventory: 25 stacking slots on the left, recipes and ability unlocks on the
right. A recipe you have not discovered yet shows as a blank locked row, so the list also
tells you how much is still out there.

Six gems pay for everything: **Amber**, **Diamond**, **Emerald**, **Quartz**, **Sapphire**
and **Topaz**. Every district holds a fixed budget of them, spread between chests, ore seams
and rubble, so a tile really can be mined out.

Crafting turns gems into tools: regen and speed tonics, hold traps you lob at a voxel, and
cloudstone blocks that lower gravity while you stand on them. These are just examples, there 
is more.

## Building

Learned build stamps ride the same `F1`–`F6` slots as your abilities. Each one costs a gem to
place and drops a whole finished structure into the world — arches, statues, cottages, pools,
pyramids. They are ordinary voxels afterwards, so you can carve them right back up.

## Things worth finding

- **Gem chests** stand in furnished rooms. Open one, the lid swings, and it pays out of the
  district's budget once.
- **Alchemy labs** hide in ordinary buildings a few blocks apart. Sick green ground-floor
  glass and a sign over the door are the tell; the vat is inside.
- **Wanted posters** hang on walls facing the avenues, five metres by ten, with the killer's
  face on them.
- **Ore seams** run through hill caves, where the stone itself is the ledger rather than the
  chests. Legend has it that hills also house a demon.

## Saving and settings

`Game` in the top-right corner saves, loads and starts new runs. `Settings` next to it holds
graphics presets, volume and the full key rebind list. `Esc` closes whatever panel is open,
and quits when nothing is.

# Districts

The city is a grid of tiles, each one a district with its own type. Five are ordinary urban
quarters. The rest replace most of the street grid with one big spectacle, and only carry
roads along their edges. The city is truely infinite in all directions.

## Core High-Rise

Downtown towers, dense streets, and the wildest skyline. The tallest massing in the game and
the best place to fall off something.

## Old Town

Brick lanes, clay roofs, and crooked medieval massing. Low, tight and full of courtyards.

## Waterfront Industrial

Metal sheds, tanks, and gravel yards by the docks. Sparse roads, big hollow volumes.

## Garden Residential

Low housing, pocket parks, and calm leafy blocks. The quietest tile type — good for building.

## Civic Quarter

Stone monuments, grand plazas, and ceremonial streets. Arches and pierced slabs over open ground.

## Hill

One big hill, rock strata and caves, with roads only at the edges. The cave network is where
ore seams live, so a hill is worth mining rather than looting. The cave is truely gargantuan and
its easy to get lost.

## Graveyard

An elevated churchyard of hedges and graves. The chapel hides a crypt that keeps sending
undead up into the yard.

## Lake

One big natural lake with wooded islands. Deep water, no streets, and a long swim.

## Castle

A walled fortress on a plinth, reached by a causeway. Dungeon pads below the keep summon what
lives down there.

## Fractal

A glowing plaza with Mandelbrot walls. The panels are live — you can aim into them and travel
deeper into the set.

## Arena

A colosseum filling the whole tile. Four wall stations let you summon monsters down into the
pit and watch them fight from safety, or drop in yourself.

## Monster Zoo

A fenced battlefield where six factions hold territory and never stop fighting. The gate hands
you a spectator cloak on a timer: while it lasts nothing acquires you, and the moment it lapses
the nearest fight turns around.

## Gaming

Several games are here, all on a professional level. Play master class monster chess (animated
monsters visualize it) or on a giant go board, up to the highest dan levels. Tetris for in 
between. The maze houses gems.

## Siege Quarter

A barricaded block around a Lodestone. Four outer stones shield the centre, hell gates send
waves on a clock, and kill loot goes into a pot you bank at the Lodestone once the ground is
clear. Buy towers from the pads with gems from your bag.

# Thanks

EccentriCity stands on a lot of other people's work. Everything below is used under a licence
that permits it — and where that licence asks for credit, or simply appreciates it, this is it.

## Engine and libraries

- **Godot Engine** 4.6 — the engine the whole game runs in. MIT.
- **Voxel Tools** 1.6 by Marc Gilleron (Zylann) — the streaming voxel terrain every district is
  carved out of. MIT.
- **godot-rust** (gdext) — the Rust bindings behind the native district baker and the in-process
  Go engine. MPL 2.0.
- **dashu** — arbitrary-precision decimals, so the Fractal district can keep zooming long after
  a 64-bit number has run out of digits. MIT / Apache 2.0.
- **KataGo** 1.16.5 by David Wu — the Go opponent. It plays on the Human-SL net, which is why a
  rank on the table means something close to that human rank. MIT.
- **Eigen** 3.4 — the linear algebra KataGo's CPU backend runs on. MPL 2.0.
- **zlib** 1.3.1 by Jean-loup Gailly and Mark Adler — unpacks the neural net. zlib licence.

The chess opponent is this project's own search rather than a borrowed engine.

## Art and sound

- **Kenney** (kenney.nl) — sound effects, plus the Car, Pirate, Furniture, Graveyard and Nature
  kits behind the traffic, the chests, the room furniture, the graves and the greenery. CC0.
- **ambientCG** (ambientcg.com) — the photo textures on brick, stone, asphalt, plaster and most
  other city surfaces. CC0.
- **Kay Lousberg** (KayKit Character Pack: Skeletons) — the skeleton bodies. CC0.
- **Quaternius** (quaternius.com) — the Ultimate Monsters pack and the Universal Animation
  Library. CC0.
- **MakeHuman** and the **MPFB** plugin — the pedestrian bodies and their wardrobe, including
  community garments by Donitz, culturalibre and Joel Palmius. CC0.
- **Freesound** — the charged blast is built from CC0 recordings by bennettfilmteacher, wjl and
  d_yonqui.
- **Adobe Mixamo** — a handful of character animations, used under the Mixamo terms.

Per-asset provenance — every licence, author and source URL — lives in `LICENSE_ASSETS.md` and
in the `CREDITS.txt` beside each asset folder.
