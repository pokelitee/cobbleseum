# Cobbleseum

A local-first 3D Pokémon battle game: two Pokémon fight in real time in an arena, AI-vs-AI battles can be recorded as clips, and many simulated battles rank every species.

## Language

### Species and roster

**Species**:
One entry in the roster, with its own Showdown ID. A regional or other form, such as Alolan Ninetales, is a species of its own.
_Avoid_: roster entry, form (as a separate thing), Pokémon (for an entry)

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
One fight between two fighters, from the start to a knockout or a draw.
_Avoid_: game, match

**Side**:
One of a battle's two places, A or B. Every matchup is played from both sides.

**Tick**:
One step of a battle. There are 30 ticks a second.

**Intent**:
What a fighter is told to do on one tick: move in a direction, dodge, or use one of its moves. The player and the AI give the same intents.
_Avoid_: input, command, action

**Seed**:
The number a battle's luck, arena and terrain come from.

**Rules version**:
The number of one set of battle rules. Every change that can change how a battle turns out gets a new one.

**Battle spec**:
Everything needed to reproduce a battle exactly: the rules and data versions, the two fighters and their movesets, each side's AI profile, the arena and the seed, plus every tick's intents for a player's side.
_Avoid_: replay file, config

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

**Stat stage**:
A step from −6 to +6 that raises or lowers one of a fighter's stats until it wears off.
_Avoid_: boost, buff (for the stage itself)

**Status condition**:
A lasting effect on a fighter: burn, poison, bad poison, paralysis, sleep, freeze or confusion. A fighter has at most one, plus confusion.
_Avoid_: status effect, ailment

**Knockout**:
A fighter's HP reaching zero, which ends the battle.
_Avoid_: faint, KO (in prose), defeat

**Overtime**:
The stretch from 60 seconds to time-up, in which hits grow stronger every second.

**Time-up**:
A battle reaching its 90-second cap.

**Draw**:
A battle with no winner: both fighters knocked out on the same tick, or time-up.
_Avoid_: tie, stalemate

**Arena move**:
A move that changes the arena or the whole battle for a while instead of hitting a fighter, such as a weather move, Electric Terrain, Spikes or Reflect. Not in the game yet.
_Avoid_: field move

**Weather**:
Reserved for a battle condition, set by moves, that changes play. Not in the game yet.

### AI

**Utility AI**:
The AI that controls a fighter by scoring every action it could take and picking the best, giving the same intents as a player.

**AI profile**:
A named set of the utility AI's settings: reaction delay, decision interval, mistake chance and dodge chance. Rankings use the ranked profile.
_Avoid_: difficulty, level, skill

**Stand-in AI**:
The simpler AI from before the utility AI, still selectable for a side. It is not an AI profile.
_Avoid_: simple profile

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
An arena's sky, light, fog and particles.
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

**Clip**:
A video of one battle.
_Avoid_: video, recording

**Format**:
The shape of a clip's video: vertical (1080×1920) or landscape (1920×1080). Any clip can be made in either.
_Avoid_: orientation, aspect ratio, format (for battle rules)

**Clip window**:
The stretch of a battle that a clip shows, at most 60 seconds and usually ending just after the knockout.

**Instant replay**:
A slow-motion repeat of the knockout inside a clip.

**Credits card**:
The card that ends every clip, crediting Cobblemon and the other sources.
_Avoid_: end card

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
