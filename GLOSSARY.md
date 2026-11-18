# Cobbleseum

A local-first 3D Pokémon battle game: two Pokémon fight in real time in an arena, AI-vs-AI battles can be recorded as clips, and many simulated battles rank every species.

## Language

### Species and roster

**Species**:
One entry in the roster, with its own Showdown ID. A regional or other form, such as Alolan Ninetales, is a species of its own.
_Avoid_: roster entry, form (as a separate thing), Pokémon (for an entry)

**Cosmetic form**:
A look a species can appear in that changes nothing in battle, such as East Sea Gastrodon, one of Vivillon's wing patterns or a female model. A form that changes battle data is a species instead.
_Avoid_: variant, form (alone)

**Shiny**:
A fighter drawn in its species' alternate colours, marked with a sparkle. Like a cosmetic form, it never changes a battle.

**Roster**:
Every species that has both a Cobblemon model and Showdown data.

**Fighter**:
A species on one side of a battle.
_Avoid_: combatant, unit, mon

**Matchup**:
Two species set against each other.
_Avoid_: pairing

### Battles

**Battle**:
One fight between two sides, from the start until a side has no one left, or a draw.
_Avoid_: game, match

**Team**:
The 1–6 Pokémon a side brings to a battle, in order. One fighter of each team is out at a time; a battle of one Pokémon a side is a team battle with teams of one.
_Avoid_: party, roster (that's every species)

**Send-out**:
A team member coming into the battle, landing from its ball at its side's start spot. After a knockout with more of the team to come, it comes after a short lull and can't be hit until it lands.
_Avoid_: switch-in (for this), spawn

**Trainer**:
The figure standing in a side's trainer's box, drawn from the games' trainer sprites, who throws its team's Pokémon out, calls them back and reacts. Presentation only.
_Avoid_: player (that's the person playing), character

**Switch**:
Recalling the fighter out for a healthy member of its team on the bench, which lands where it stood and can be hit while it does. A side can switch again only after a cooldown that every send-out starts.
_Avoid_: swap, substitute

**Side**:
One of a battle's two places, A or B. Every matchup is played from both sides.

**Tick**:
One step of a battle. There are 30 ticks a second.

**Intent**:
What a fighter is told to do on one tick: move in a direction, dodge, guard, use one of its moves, feint one, or switch to a team member. The player and the AI give the same intents.
_Avoid_: input, command, action

**Seed**:
The number a battle's luck, arena and terrain come from.

**Rules version**:
The number of one set of battle rules. Every change that can change how a battle turns out gets a new one.

**Battle spec**:
Everything needed to reproduce a battle exactly: the rules and data versions, each side's team (its fighters with their movesets, abilities and held items), each side's AI profile, the arena and the seed, plus every tick's intents for a player's side. It also says how each fighter looks (shiny, cosmetic form), which only the presentation reads.
_Avoid_: replay file, config

**Battle flags**:
Command-line options such as `--watch=garchomp --vs=hydreigon --seed=7` that describe a battle spec without a file. The setup screen builds its battles through them too.
_Avoid_: CLI args (for these)

**Setup screen**:
The screen a plain launch opens, where a battle is set up by hand (mode, fighters, arena, weather, seed) before watching, playing or recording it.
_Avoid_: main menu, lobby

**Replay**:
Playing a battle again from its battle spec, which gives the same battle.

**Event**:
Something that happens in a battle on one tick, such as a hit, a critical hit, a dodge, a status change, a knockout or time-up.

**Event log**:
All of a battle's events, in order.

**Battle record**:
What a battle leaves behind: its battle spec, result, length, event log and checksum.

**Checksum**:
A fingerprint of a battle's final state, which shows that a replay matched the original.

### Fighting

**Move**:
Something a fighter can use, taken from Showdown's data.

**Moveset**:
The moves a fighter brings to a battle, at most four.

**Standard moveset**:
The moveset a species gets from the one policy applied to every species' learnset. A battle uses it unless its battle spec names other moves.
_Avoid_: random-battle set, build

**Ability**:
A lasting trait of a fighter from Showdown's list for its species, such as Levitate or Intimidate, with an effect from Cobbleseum's own table. A fighter has at most one.
_Avoid_: trait, passive, skill

**Standard ability**:
The ability a species gets from the one policy applied to every species: its highest-valued ability in the table. A battle uses it unless its battle spec names another.

**Held item**:
An item a fighter carries into battle, such as Leftovers or a Sitrus Berry, with an effect from Cobbleseum's own table. A fighter has at most one, and some are used up.
_Avoid_: item (alone, where it could mean anything else), equipment

**Standard item**:
The held item a species gets from the one policy applied to every species, from its stats, types and standard moveset. A battle uses it unless its battle spec names another.

**Move kind**:
How a move plays in real time: melee, projectile, area, self-buff, debuff, heal or status.
_Avoid_: move type (that's Fire, Water and so on), category (that's physical or special)

**Wind-up**:
The part of a move before it lands, while the fighter is committed and can't dodge.

**Recovery**:
The part of a move after it lands, before the fighter can act or dodge again.

**Cooldown**:
The time before a fighter can use a move again. Strong, scarce moves have longer ones.

**Dodge**:
A short, invulnerable dash. Each fighter has two dodge charges, which refill over time.

**Feint**:
A fake wind-up of a melee or area move that breaks off before it lands, to draw the foe's dodge or guard. It deals no damage and spends no move cooldown, but a fighter can feint only once every few seconds.
_Avoid_: fake, bluff, cancel

**Guard**:
A short stance that blocks hits from the front, with a cooldown. A guard that blocks a melee strike **parries** it, staggering the attacker; one that blocks nothing leaves the fighter briefly open.
_Avoid_: block (for the action), shield, protect (that's a move)

**Stat stage**:
A step from −6 to +6 that raises or lowers one of a fighter's stats until it wears off.
_Avoid_: boost, buff (for the stage itself)

**Status condition**:
A lasting effect on a fighter: burn, poison, bad poison, paralysis, sleep, freeze or confusion. A fighter has at most one, plus confusion.
_Avoid_: status effect, ailment

**Knockout**:
A fighter's HP reaching zero. The battle ends when a side's last fighter is knocked out.
_Avoid_: faint, KO (in prose), defeat

**Overtime**:
The stretch from 60 seconds to time-up, in which hits grow stronger every second. In a team battle the clock restarts at each send-out after a knockout.

**Time-up**:
A battle reaching its 90-second cap (in a team battle, 90 seconds since the last send-out after a knockout). A team battle then goes to the side with more Pokémon left.

**Draw**:
A battle with no winner: both sides' last fighters knocked out on the same tick, or a one-on-one time-up (a team battle's only when both sides are even).
_Avoid_: tie, stalemate

**Arena move**:
A move that sets an arena condition instead of hitting a fighter: a weather move, a surge move (Electric Terrain) or a screen (Reflect). Entry hazards such as Spikes are arena moves too.
_Avoid_: field move

**Arena condition**:
A weather, surge or screen that is up for a while and changes play.

**Weather**:
The arena condition of the sky over the whole battle: rain, sun, sandstorm or snow. One at a time; a new one replaces the old.
_Avoid_: look (the arena's sky and light, which weather changes on top of)

**Surge**:
The arena condition on the ground under the whole battle (electric, grassy, misty or psychic), set by the moves Showdown calls Electric Terrain and so on. It affects only grounded fighters.
_Avoid_: terrain (that's the ground's shape), field effect

**Entry hazard**:
An arena condition laid on the foe's side, such as Stealth Rock or Spikes, that hurts or hinders each Pokémon sent out there until it's cleared. Only team battles have send-outs for it to act on.
_Avoid_: trap, field hazard

**Screen**:
An arena condition on one side that weakens hits taken: Reflect, Light Screen or Aurora Veil.

### AI

**Utility AI**:
The AI that controls a fighter by scoring every action it could take and picking the best, giving the same intents as a player.

**AI profile**:
A named set of the utility AI's settings: reaction delay, decision interval, mistake chance, dodge chance, feint chance and guard chance. Rankings use the ranked profile.
_Avoid_: difficulty, level, skill

**Stand-in AI**:
The simpler AI from before the utility AI, still selectable for a side. It is not an AI profile.
_Avoid_: simple profile

**Melee lean**:
How much of a fighter's damage comes from close range, from 0 to 1: its melee and area moves' share of the damage per second its whole moveset would deal the foe. It sets the utility AI's spacing: a **kiter** (under 0.5) keeps its range, a **brawler** presses in.
_Avoid_: style score, aggression

**Trade**:
How a fighter fares against its foe, as the utility AI weighs it for switching: how much faster it would wear the foe down than be worn down, from both sides' expected damage, its HP and its status.
_Avoid_: matchup (that's two species set against each other)

**Opening**:
A moment a kiter goes in for a melee strike: the foe recovering, asleep, frozen, stunned, or out of dodges with its guard on cooldown, or a feint about to be thrown.
_Avoid_: window (alone), chance

### Arenas

**Arena**:
Where a battle is fought: a field, a venue and a look, chosen from the arena presets.
_Avoid_: stage, map, biome

**Field**:
The ground inside the arena wall that fighters move on, of one kind: grassland, beach, volcano, snowfield, cave or paving.

**Arena wall**:
The circle around the field that fighters can't cross. There are no ring-outs.

**Terrain**:
The shape of a field's ground: its heights, terraces, cliffs and features. It is different in every battle.
_Avoid_: map, level, landscape

**Feature**:
Something standing on a field that fighters must climb or go around and that can block shots, such as a rock cluster, a tree, a log or an ice spike.
_Avoid_: prop, obstacle, cover

**Venue**:
What surrounds the field: open land or a coliseum.

**Coliseum**:
A venue of walled stands with a crowd around the field.
_Avoid_: stadium (that's part of a preset's name)

**Crowd**:
The people and watchers in a coliseum's stands.

**Watcher**:
A Pokémon in a coliseum's front row, watching a fighter.
_Avoid_: Cobblemon (for the creature), spectator Pokémon

**Look**:
An arena's sky, light (sun, ambient light, and a coliseum's floodlights), fog and particles.
_Avoid_: weather

### Presentation and clips

**Presentation time**:
The clock that what's shown runs on, kept apart from the battle's ticks, so effects can pause or stretch the view without changing the battle.

**Hit-stop**:
A brief freeze of the fighters on a heavy hit while the view keeps going.

**Slow motion**:
Showing a battle slower than real time, for knockouts and near-misses.

**Skip ahead**:
Running a battle on without showing it, to start a clip partway through.

**Director**:
What chooses the camera shot for every moment, planned ahead from the event log so it can build up to the knockout.
_Avoid_: camera AI

**Move style**:
How a damaging move looks, such as punch, slash, beam or orb. It never changes play.
_Avoid_: move effect, move animation

**Battlefield mark**:
What a hit leaves on the arena's ground for the rest of the battle: a scorch, frost, cracks, a crater ring, a splash stain or a scuff, and for area and ground-shaking moves debris that settles. It never changes play.
_Avoid_: scar, damage (for these), terrain (that's the ground's shape)

**Ambience**:
The steady background sound of an arena: the crowd in a coliseum, or the field's own sound (wind, surf, rumble, drips) in the open.
_Avoid_: atmosphere, background noise

**Track**:
One piece of battle music: an intro that plays once, then a loop that repeats until the music ends.
_Avoid_: theme (a coliseum's colours), song

**Climax layer**:
The extra part of a track that overtime brings in.
_Avoid_: intensity track

**Sting**:
A short piece of music marking one moment, such as the victory.
_Avoid_: jingle

**Clip**:
A video of one battle.
_Avoid_: video, recording

**Format**:
The shape of a clip's video: vertical (1080×1920) or landscape (1920×1080). Any clip can be made in either.
_Avoid_: orientation, aspect ratio, format (for battle rules)

**Clip window**:
The stretch of a battle that a clip shows, at most 60 seconds and usually ending just after the knockout.

**Instant replay**:
A slow-motion repeat of the knockout from new angles, shown after the knockout and before the victory. Its pictures come from a replay of the battle, so the battle itself is never stepped again.

**Caption**:
A short line across the lower third of a clip marking a big beat, such as "COMEBACK!" or "FINAL BLOW".
_Avoid_: subtitle, callout (text over a fighter)

**Credits card**:
The card that ends every clip, crediting Cobblemon and the other sources.
_Avoid_: end card

**Name plate**:
A fighter's panel on the HUD: its portrait, name, type pills and HP bar, with its effect row under the bar.

**Effect row**:
The square badges under a name plate's HP bar for what is on the fighter now: its status condition, confusion and its side's screens, each with a draining timer, then its changed stat stages as arrows with counts. Type pills stay on the plate itself, so a condition never reads as a type.
_Avoid_: status pills

### Rankings

**Rating**:
A species' strength with its standard moveset under one rules version and the ranked AI profile, fitted from battle records.
_Avoid_: Elo, score

**Ranking**:
Every species ordered by rating, under one rules version. A new rules version starts a new ranking.

**Matchup matrix**:
Head-to-head win rates among the top species, published beside the ranking because matchups aren't transitive.

**AI-sensitivity check**:
Re-ranking with a second AI profile, to confirm that the species, not the AI, decide the results.

**Balance batch**:
A run of simulated battles that reports battle length, draw rate, type-advantage wins and move-kind use, for tuning the rules.

### Sources and assets

**Showdown**:
The battle simulator whose data (species, moves, learnsets and types) Cobbleseum uses. Never its battle engine.

**Cobblemon**:
The Minecraft mod whose models, textures, animations and cries Cobbleseum converts. Never a creature.

**Animation**:
One motion of a model, such as idle, walk or faint.
_Avoid_: clip

**Animation role**:
The part an animation plays for a fighter: idle, walk, attack, hit, faint, air idle and so on.
_Avoid_: clip role
