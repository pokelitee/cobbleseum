# Cobbleseum concept brief

Status: living document. First draft 2026-11-08; presentation section and milestones revised 2026-11-09.

## 1. Summary

Cobbleseum is a local-first 3D Pokémon battle game built with Godot 4.

- **Battles:** two Pokémon fight in real time in a small arena. They are rendered with the models, textures and animations of the Cobblemon mod.
- **Modes:** player-vs-AI and AI-vs-AI.
- **Clips:** AI-vs-AI battles can be recorded as video clips: vertical 1080×1920 for short-form posts, or landscape 1920×1080, from the same battle.
- **Rankings:** later, many battles can be simulated to keep a local ranking of every Pokémon.

Everything runs on the user's machine. The repository contains only original code and data. A pipeline then:

1. downloads pinned releases of Pokémon Showdown's data and Cobblemon's assets into a git-ignored cache;
2. verifies them by SHA-256;
3. converts them into a form Godot can use.

## 2. Decisions at a glance

| Topic | Decision | Section |
|---|---|---|
| Battle style | Real-time action under Cobbleseum's own rules, driven by Showdown's data | §9 |
| Showdown | Data only. Node.js is needed only for one pipeline step that exports the data to JSON. | §5.1 |
| Cobblemon | Pinned release jar; models, animations, textures and cries | §5.2 |
| Pokémon GO APK | Considered and rejected | §5.3 |
| Model conversion | A GDScript converter, run in the pipeline, writes native Godot scenes to the cache. Optional `.glb` output for debugging. | §7 |
| Missing models | Species without a Cobblemon model are left out of the roster, with no placeholders | §8 |
| Determinism | Our own fixed-tick simulation with seeded random streams. A battle replays from its spec and is checked by checksum. | §10 |
| AI | Utility AI that issues the same intents as a player | §11 |
| Presentation | A camera director, impact frames and slow motion driven by battle events, framed for landscape and vertical | §12 |
| Recording | Movie Maker at 30 fps in either format, encoded to MP4 with ffmpeg | §12 |
| Ranking | A Bradley–Terry fit over stored results, plus a matchup matrix | §13 |
| Engine | Godot 4.7.2, GDScript | §4 |

## 3. Goals and non-goals

Goals, in priority order:

1. Watchable real-time 3D battles between two Pokémon, AI-vs-AI and player-vs-AI.
2. An asset pipeline that fetches, verifies, extracts and converts assets on demand.
3. Recording AI-vs-AI battles as clips with Godot's Movie Maker mode, so the output doesn't depend on rendering speed: vertical 1080×1920 for short-form posts, and landscape 1920×1080.
4. Later: simulating many battles and keeping a local ranking per Pokémon.

Non-goals:

- **Out of scope for the project:**
  - Online multiplayer, mobile builds and a hosted website.
  - **Main-series accuracy.** Cobbleseum borrows stats, types, moves and the damage formula, but its real-time rules are its own. Rankings measure strength under these rules, not competitive strength in the main-series games.
  - Pokémon GO as an asset source.
- **Left out of the first version:**
  - Abilities, held items, Terastallization, Mega Evolution and Gigantamax.
  - Field effects such as weather, terrain, entry hazards and screens.

## 4. Constraints

- **Engine:** Godot 4.7.2, the current stable release. This satisfies the "4.3 or later" requirement. Pinning one exact version keeps Movie Maker output and the converted-asset cache reproducible.
- **Language:** GDScript throughout.
- **External tools:**
  - Node.js 20 or later, for one pipeline step only (§5.1).
  - ffmpeg, for the final MP4 encode (§12).
- **Platforms:** Windows, macOS and Linux.
- **Fully local:** no accounts and no telemetry. The only network access is fetching the pinned asset sources.
- **No third-party assets in git, ever.** That covers downloads, extracted files, converted output, and screenshots or videos made from them.

## 5. Asset sources

### 5.1 Pokémon Showdown: battle data

Pokémon Showdown (`smogon/pokemon-showdown`, MIT licence) is an open-source battle simulator. Cobbleseum uses only its data:

| Data | File in the package | Used for |
|---|---|---|
| Species: base stats, types, forms | `dist/data/pokedex.js` | Fighter stats and types |
| Moves | `dist/data/moves.js` | Move type, category, power, accuracy, PP, priority, flags, target, secondary effects |
| Learnsets | `dist/data/learnsets.js` | Generating each species' moveset |
| Type chart | `dist/data/typechart.js` | Type effectiveness |
| Gen 9 random-battle sets | `dist/data/random-battles/gen9/sets.json` | A sanity check for generated movesets |

**Pinned release:** the npm package `pokemon-showdown` 0.11.11, published 2026-07-28.

- URL: `https://registry.npmjs.org/pokemon-showdown/-/pokemon-showdown-0.11.11.tgz`
- Size: 16,897,160 bytes
- SHA-256: `49af14aaed1084887f756372c7386c9987905930cc848ed31e9202c10c592d66`

**Why the npm tarball:**

- Registry tarballs never change once published, so a checksum pin holds.
- GitHub source archives would need a TypeScript build.
- The data files on Showdown's website have no version, so they can't be pinned.

**Why Node.js:**

- The package ships its data as compiled JavaScript modules, not JSON, and some entries contain functions.
- A small Node script loads the modules and writes plain JSON into the cache, dropping the functions. The four modules have no dependencies of their own (checked), so the step needs only `node`, with no `npm install`.
- Node is not needed at game runtime, for the AI, for batch simulation or for recording.

**Release cadence:** npm releases are infrequent (0.11.10 in February 2025, 0.11.11 in July 2026), so the pinned data can lag upstream by months. That's acceptable; stable data matters more here than new moves.

**Checked facts for 0.11.11:**

- The species list has 1,517 entries, including forms.
- Every species on the roster (§8) has a learnset.
- Only 338 of the 905 roster species have a Gen 9 random-battle set.

### 5.2 Cobblemon: models, animations, textures and sounds

Cobblemon is a Minecraft mod that adds Pokémon. Its models and animations use Minecraft Bedrock Edition's JSON formats, which are usually authored in Blockbench.

**Pinned release:** the Fabric jar 1.8.4 for Minecraft 1.21.1, published 2026-10-27 on Modrinth.

- URL: `https://cdn.modrinth.com/data/MdwFAVRL/versions/PdOzYHKU/Cobblemon-fabric-1.8.4%2B1.21.1.jar`
- Size: 139,966,403 bytes
- SHA-256: `77c4866b2e4c38afb488ed09b62ffd2729ce291dc793fca9c055c087f0b03978`

Modrinth publishes only SHA-1 and SHA-512 hashes, so the manifest records a SHA-256 that we computed. The jar is a zip archive.

**Layout of the 1.8.4 jar.** These paths come from listing the jar itself. `NNNN` is the zero-padded National Pokédex number.

| Content | Path in the jar | Count |
|---|---|---|
| Geometry | `assets/cobblemon/bedrock/pokemon/models/NNNN_name/*.geo.json` | 1,170 files, format 1.12.0 |
| Animations | `assets/cobblemon/bedrock/pokemon/animations/NNNN_name/*.animation.json` | 1,010 files, format 1.8.0 |
| Posers | `assets/cobblemon/bedrock/pokemon/posers/NNNN_name/*.json` | 759 files for 657 species |
| Resolvers | `assets/cobblemon/bedrock/pokemon/resolvers/NNNN_name/N_*.json` | 1,091 files for 905 species |
| Textures | `assets/cobblemon/textures/pokemon/NNNN_name/*.png` | 4,089 |
| Cries and sounds | `assets/cobblemon/sounds/pokemon/<name>/*.ogg` | 2,116 |
| Move sounds | `assets/cobblemon/sounds/move/<move>/<move>_{actor,target}*.ogg`, plus `impact_generic/impact_generic_<type>_N.ogg` | 302 (136 generic impacts) |
| Species data | `data/cobblemon/species/generationN/<name>.json` | 1,025 |
| Model licences | `assets/cobblemon/bedrock/pokemon/models/NNNN_name/license` | one per model folder |

**Terms used below:**

- A **poser** says which clips a species plays in each pose, such as standing or flying in battle. It also lists one-off clips (physical attack, special attack, cry), head-tracking bones and idle quirks like blinking.
- A **resolver** lists a species' visual **variations**. Each variation is selected by **aspects** (shiny, female, Alolan, …) and names a model, a texture, a poser and optional extra texture layers.

**What we use:** geometry, animations, textures, posers, resolvers, cries and move sounds. From the species data we use only the `implemented` flag and `baseScale`. All battle data comes from Showdown, so stats and moves have a single source of truth.

**Facts that shape the design:**

- **Missing models:** 905 of the 1,025 species are implemented with a model. The 120 without include many legendary and mythical Pokémon, such as Celebi, Entei, Raikou, Suicune, Deoxys, Groudon, Kyogre, Jirachi, Arceus and Darkrai.
- **Forms:** regional forms exist as resolver variations: 66 Alolan, 43 Hisuian, 40 Galarian and 12 Paldean variation entries. There are no Mega or Gigantamax forms.
- **Animation coverage is uneven.** Of the 904 species with animation files:

  | Clip | Species with it |
  |---|---|
  | `ground_idle` | 860 |
  | `cry` | 758 |
  | `ground_walk` | 560 |
  | `battle_idle` | 419 |
  | `ground_run` | 213 |
  | `recoil` (hit reaction) | 213 |
  | `faint` | 212 |
  | `hurt` | 142 |
  | `air_fly` | 113 |
  | `physical` | 110 |
  | `special` | 103 |

  - Only 58 species have the full set of battle idle, physical, special, faint, cry and recoil.
  - 316 species have no walk, run or fly clip.
- **Posers:** 248 species have no JSON poser. Their pose logic is compiled into the mod's code, which we can't use.
- **Molang:** 714 of the 1,010 animation files contain Molang expressions, Bedrock's small expression language.
  - Almost all of them are functions of animation time: `q.anim_time` with `math.sin`, `math.cos` and `math.clamp`.
  - `math.random` appears 244 times.
  - All 206,054 keyframes in the jar use Catmull-Rom interpolation.
- **Geometry** uses only "box UV" texture mapping, with no per-face UVs. Inflated, rotated and mirrored cubes are common. Models have a median of 57 cubes, with a maximum of 566. Textures are between 64×64 and 256×256 pixels.
- **Hitbox data is unreliable.** One species has a height of 0. Hitboxes therefore come from converted model bounds (§8).
- **Move assets (unused in the first version):** the jar also ships 617 Bedrock particle effects for moves, 140 scripted move effects and 390 move sounds.

### 5.3 Pokémon GO APK: considered and rejected

The project won't support a Pokémon GO APK as a source:

- **The APK lacks what a 3D battle renderer needs.** Pokémon models, animations and game data are downloaded at runtime and cached in app-private storage. The APK mostly holds UI sprites and some textures and sounds.
- **The terms forbid it.** The game's terms of service prohibit reverse engineering the app and extracting its content, and an importer would exist only to do that.
- **Poor trade-off.** It would add Unity asset-extraction tooling for little gain.

## 6. Asset pipeline

**Requirements and how they're met:**

| Requirement | How it's met |
|---|---|
| One fetch/convert script per source | `tools/sources/showdown.gd` (with a Node helper) and `tools/sources/cobblemon.gd` |
| Pinned versions with checksums | `sources.json` manifest: URL, size and SHA-256 per source |
| Git-ignored cache | `cache/` at the repository root |
| Safe to re-run | Every step writes a stamp; steps with a matching stamp are skipped |
| Offline once cached | Nothing touches the network if the files are present; `--offline` turns a missing download into an error |
| Clear error when a layout changes | Layout checks run after extraction |
| No third-party assets in git | `.gitignore` plus a guard script run in CI |

**Manifest.** `sources.json` lists each source with:

- id, version, URL, size, SHA-256 and archive type;
- a licence note;
- the expected layout: path patterns, minimum file counts and format versions.

**Cache layout.** The cache contains a `.gdignore` file, so the Godot editor never tries to import its thousands of files. The game loads cached files by path.

```
cache/
  downloads/<sha256>.<ext>                       verified archives
  sources/<source>/<version>/                    extracted subset
  build/<source>/<version>/                       converted output, roster, credits
```

**Running it.** One entry point runs in headless Godot:

```
godot --headless --path . --script tools/assets.gd -- [all|fetch|extract|convert] [source] [--offline]
```

**Steps for each source:**

1. **Fetch:** download to a temporary file, check its size and SHA-256, then move it into `downloads/`. On a checksum mismatch the file is discarded and the step fails.
2. **Extract:** unpack only the subtrees that are needed.
3. **Check layout:** confirm every expected path pattern, minimum count and format version.
4. **Convert or export:** run the source's converter (§7), or the Node export (§5.1).

**Re-running.** Each step writes a stamp file recording the hashes of its inputs and its tool version. Output is written to a temporary location and renamed when complete, so an interrupted step never looks finished.

**Layout errors** name:
- the source and its pinned version;
- the expected pattern, and what was found instead;
- the fix: update the manifest pin and the layout spec together.

**Why GDScript.**

- Godot has HTTP, zip reading, SHA-256 and gzip built in. The tar container inside the npm tarball needs a small reader.
- The converter has to produce Godot resources anyway.
- This avoids adding a third runtime such as Python.

**Keeping assets out of git:**

- `.gitignore` covers `cache/`, `recordings/` and `results/`.
- A guard script, run in CI and usable as a pre-commit hook, fails if any tracked file looks like a third-party artefact:
  - `*.geo.json`, `*.animation.json`, `*.jar` or `*.tgz`;
  - anything under the ignored folders;
  - any binary over a size threshold.
- Test fixtures are original, hand-made files.

**Credits.** The pipeline collects the licence of every converted model into a credits file. The game's credits screen and the clip end card use it.

## 7. Converting Cobblemon models

### 7.1 Approach

A GDScript converter runs as a pipeline step and writes binary Godot scenes (`.scn`) into the cache. The game loads only converted scenes and never parses Bedrock JSON. A `--gltf` debug option also writes `.glb` files through Godot's glTF exporter, so a model can be inspected in Blender or any glTF viewer.

**Alternatives considered:**

- **`.glb` as the main output.** glTF has no Catmull-Rom interpolation and no animated texture layers. We would bake everything and patch materials after loading anyway.
- **A runtime loader that parses Bedrock JSON at startup.** It would redo the expensive work, such as sampling Molang, on every launch. A changed upstream layout would also surface as a broken render instead of a pipeline error.

### 7.2 Geometry

A `.geo.json` file holds a list of bones. Each bone has:

- a name and an optional parent;
- a pivot point in model pixels and an optional rest rotation in degrees;
- cubes and locators (named marker points).

Each cube has:

- an origin (its minimum corner) and a size;
- a UV offset into the texture;
- an optional inflate amount, which grows the box on every side without changing its UVs;
- a mirror flag, which mirrors its texture;
- an optional rotation around its own pivot.

The geometry header gives the texture size.

**Conversion rules.** Milestone 1 confirmed these with unit tests on hand-made geometry and with rendered previews of real models:

- 16 model pixels = 1 metre.
- **Axes:** Bedrock's X axis points the opposite way to Godot's.
  - Positions and pivots: negate X.
  - Rest and animated rotations: negate the X and Y angles, keep Z.
  - Animated position offsets: negate X.
  - Scale: unchanged.
- **Rotation order:** a rotation combines as Z·Y·X, so X is applied first.
- **Box UV:** the six faces are unwrapped from the cube's UV offset in the standard box layout, sized by the cube's dimensions.
  - Mirroring swaps the east and west faces and flips every face horizontally.
  - A cube with zero thickness on one axis produces only its two large faces.
  - A converter design doc will specify the exact face layout.
- **Mesh structure:**
  - One `Skeleton3D` per model.
  - One mesh per texture layer.
  - Every cube's vertices bind fully to its own bone (rigid skinning).
  - Locators become marker transforms, for example as spawn points for projectiles.
- **Materials:**
  - Nearest-neighbour filtering, no mipmaps, and alpha-scissor cut-outs.
  - Glowing and translucent layers come from the resolver.
  - Animated layers (a list of texture frames plus a frame rate) become flipbooks.

### 7.3 Animations

**The format.** An `.animation.json` file holds clips named `animation.<species>.<clip>`. Each clip has:

- a length;
- a loop mode: loop, play once, or hold on the last frame;
- rotation, position and scale channels per bone.

Each channel is either a constant or a set of timed keyframes:

- A keyframe value is a number or a Molang expression.
- A keyframe can have different values just before and just after its time, which makes a jump.
- Each keyframe has an interpolation mode.

**Conversion:**

1. Every channel is evaluated at a fixed 60 Hz by our own evaluator. The evaluator matches Bedrock's interpolation: a Catmull-Rom segment uses the keys on either side as neighbours, duplicating the end keys at the edges.
2. The samples are stored as Godot animation tracks with linear interpolation. Rotations are stored as quaternions relative to the bone's rest pose.
3. `math.random` gets a fixed seed per clip, so converted clips are deterministic.

**Molang.** A small parser and evaluator covers the subset found in the jar:

- **Syntax:** numbers, arithmetic, comparisons, logical operators, the ternary operator and parentheses.
- **Functions:** `math.sin` and `math.cos` (in degrees), plus `clamp`, `abs`, `mod`, `round`, `pow`, `min`, `max`, `sqrt`, `ceil`, `exp`, `random` and `random_integer`.
- **Time:** `q.anim_time` and `query.anim_time`.

Unknown queries and variables, such as riding yaw and a few custom variables, evaluate to 0 and are reported. Asset text is never evaluated as code.

**Posers:**

- For the 657 species with a JSON poser, the converter reads:
  - the clips for each battle pose;
  - the named one-off clips: physical, special, status, cry and recoil;
  - head-tracking bones and their limits;
  - quirks such as blinking.
- The 248 species without a poser use a name-based fallback: `battle_idle`, else `ground_idle`, with `air_idle` for species that fly.

**Resolvers:** the converter takes the base variation (no aspects) or the requested aspects (shiny, female, regional form).

### 7.4 Playback

Animations play in three layers:

1. **Base loop:** an idle or locomotion clip, crossfaded between states. Walk and run clips play faster or slower to match movement speed. Base clips are padded so that bones they don't key hold the idle pose; otherwise a crossfade passes through the rest pose and the model briefly looks like it's in a T-pose.
2. **One-off actions** on top: attack clips, applied only to the bones they key.
3. **Additive reactions:** hit recoil, cries and blinking, applied as offsets from rest and faded in and out.

**Procedural layer.** Most species lack attack, hit or faint clips, so a procedural layer on the model root fills the gaps:

- a hop, bob or glide for movement;
- a lunge, spin or squash-and-stretch for attacks;
- a tilt and knockback for hits;
- a tip-over and fade for fainting.

Implemented in `game/presentation/procedural_motion.gd`, as a transform on a node between the fighter and its model, so it stacks with clips, knockback and the hit flash. It fills in only the roles a species has no clip for:

- a hop while walking (408 entries have no walk clip);
- a lunge for physical moves, a rear-back with squash and stretch for special moves, and a spin for status moves;
- a backward tilt for hits;
- slow breathing while asleep;
- tipping over and sinking for fainting, instead of fading.

Flying types hover and bob throughout. The layer advances per video frame at the clips' speed, so it freezes in hit-stop and slows in slow motion.

### 7.5 Quality checks

A QA pass over every roster species reports:

- clips that leave the model in its rest pose;
- feet sinking below the floor;
- wrong facing;
- unknown Molang;
- missing clips.

The report feeds the roster flags (§8). The QA runs locally, and its reports stay in the cache.

## 8. Roster and species identity

- **Roster:** every species that has both a Cobblemon model and Showdown data. For Cobblemon 1.8.4 that's 1,005 entries: all 905 species, each matching a Showdown species by normalised name, plus 100 forms that Showdown lists as separate species (regional forms, Rotom's appliances, female forms and others).
- **Identity:**
  - Species are identified by Showdown ID (`charizard`, `ninetalesalola`).
  - Each ID maps to a Cobblemon species folder plus a list of aspects (`ninetales` + `alolan`).
  - The mapping is generated by name matching: a Showdown forme ("Alola") matches the Cobblemon form of the same name, whose aspects select the model through the species' resolver variations. No overrides table has been needed so far.
  - Battle-only forms (Mega, Gigantamax, Primal, Crowned, Zen and similar) are excluded.
- **Missing models:** species without a Cobblemon model are left out of play, clips and rankings. There are no placeholders, because a stand-in model would look broken in a posted clip.
- **Size:** in the data, heights run from under 0.5 m (82 species) to 6.5 m.
  - Each species' size comes from Cobblemon's own gameplay hitbox (`hitbox` width and height, a form's own when it has one) multiplied by its `baseScale`. Rest-pose model bounds turned out to be unreliable for coiled or stretched-out models (Seviper measures 11.7 m), so they're used only for the 3 entries without a hitbox.
  - The height is clamped into a band of 0.5–3 m, and the same factor scales the model and the hitbox radius, so a giant isn't trivially easy to hit.
  - The hitbox is a vertical capsule of the scaled height, with a radius of half the scaled hitbox width, clamped to 0.25–1.5 m.
  - For 1.8.4 the median height is 1.05 m and the median radius 0.38 m.
- **Roster file:** the pipeline writes one entry per species:
  - Showdown ID, Cobblemon folder and aspects;
  - scaled height and capsule;
  - available clips and whether a poser exists;
  - QA flags and licence.

  Headless simulation reads only this file and never loads models.
- **QA report:** `report.json` counts species per flag: missing clip roles (`no_idle`, `no_faint`, …), `no_poser`, `no_hitbox`, `no_licence_file` (410 entries whose model folder has no licence file), Molang and bone problems, and `bounds_mismatch` (73 entries whose rest-pose height disagrees with their hitbox by more than 2×, often a sign the converter poses the model wrong).
- **Caching:** each converted model has a key over its input files and the converter scripts. Rebuilds reuse models whose key still matches, from the previous build or an interrupted one.

## 9. Battle rules

### 9.1 Format

- One-on-one, in a round arena with walls (no ring-outs).
- The simulation runs at a fixed 30 ticks per second.
- **Length:** battles should last 30–45 seconds. At 90 seconds the battle ends in a draw.
- **Controls:** both fighters are controlled through the same intents:
  - a movement direction;
  - dodge;
  - use move 1–4.

  The AI and the player produce identical intents.

### 9.2 Fighters

- **Stats:** level 50, all IVs 31, no EVs and a neutral nature, so stats come from the species alone.
- **HP:** the HP stat times a global HP multiplier. Tuning the multiplier sets battle length.
- **Speed:** the Speed stat maps into a band of movement speeds. It also sets how quickly dodges recharge.
- **Dodges:** each fighter has 2 dodge charges, each recharging in 3 s (slowest) to 1.5 s (fastest, by Speed). A dodge is a 2.5 m dash over 0.2 s, invulnerable throughout: projectiles fly on through and melee strikes whiff. A fighter can't dodge while winding up or recovering, so attacking commits it.
- **Movement:** fighters walk at their speed, can't pass through each other (they slide around) and stay inside the wall.
- **Flying:** Flying-type species hover above the ground.

All constants in this section are starting points for tuning (§9.7).

### 9.3 Moves

Every move becomes one of a small set of **move kinds**, derived from Showdown's data (category, contact flag, target, multi-hit, charge and recharge flags, boosts, status and heal fields).

Counts are for the 685 standard Gen 9 moves, excluding Z-moves and Max moves:

| Kind | How it plays | Moves |
|---|---|---|
| Melee | Dash and strike at close range | 189 |
| Projectile | Fired at the target from mid or long range | 171 |
| Area | Ring or wave around the user | 54 |
| Multi-hit | Melee or projectile, several hits | 22 |
| Charge or recharge | Longer wind-up or recovery | 21 |
| Self-buff | Raises the user's stats | 32 |
| Debuff | Projectile that lowers the target's stats | 30 |
| Heal | Restores the user's HP | 17 |
| Status | Projectile that inflicts a status condition | 13 |

In the code, multi-hit, charge and recharge are properties of the melee, projectile and area kinds rather than kinds of their own, so a multi-hit kick and a multi-hit projectile share one implementation:

- **Area:** hits the opponent if it's within 3 m of the user when the move releases (0.45 s wind-up). Dodging through it still works.
- **Multi-hit:** strikes 0.12 s apart. Moves that hit 2–5 times use the main-series weights (2 and 3 hits 35% each, 4 and 5 hits 15% each). Cooldowns use the move's total expected power.
- **Charge:** 0.9 s longer wind-up. **Recharge:** 1 s longer recovery. Fly and Dig's semi-invulnerable charge turn isn't modelled.
- **Fixed damage** (Seismic Toss, Night Shade, Dragon Rage, Sonic Boom) deals its main-series amount, unscaled, like every other move's damage, so it keeps its balance against them.
- **Self-destructing moves** (Explosion, Self-Destruct, Misty Explosion) faint the user.

For the 850 standard moves, 616 are playable: 243 melee, 238 projectile, 64 area, 26 self-buff, 18 debuff, 17 status and 10 heal. The rest are field moves, special cases and moves whose power is computed in code.

**Not in the first version:**
- 30 field moves: weather, terrain, hazards and screens.
- 106 special-case moves, such as Protect, Substitute, Counter and Transform.

**Phases.** Every move has a wind-up, an active window and a recovery.

**Properties:**

- **Cooldown:** set from PP and power, so strong, scarce moves recharge slowly.
- **Range:** set by the move kind. Melee moves start from up to 3 m between hitboxes and dash in at 10 m/s during the wind-up; projectiles start from up to 7 m. Showdown targets that mean "one opponent" in a one-on-one battle (`normal`, `any`, `adjacentFoe`, `randomNormal`) all count as single-target.
- **Accuracy:** sets hit size or projectile speed instead of rolling for a miss. Misses come from dodging and positioning.
- **Priority:** shortens the wind-up.
- **Secondary effects** roll on hit using the battle's random stream.
- **Data effects:** drain, recoil and stat changes come straight from the data.
- **Moves with extra code:** Showdown implements extra effects in code for 91 damaging moves. Most play as plain hits. Those whose condition or cost would otherwise make them free strong hits are left out: Focus Punch, Last Resort, Future Sight, Doom Desire, Dream Eater, Synchronoise, Belch, Steel Beam, Mind Blown, Shell Trap, Beak Blast, Water Spout, Eruption, Dragon Energy, Steel Roller and Poltergeist.

### 9.4 Damage

The main-series formula:

```
damage = ((2 × Level / 5 + 2) × Power × A / D / 50 + 2) × STAB × Type × Crit × Roll
```

- **A and D** are the attacker's Attack and the target's Defense for physical moves, or Sp. Atk and Sp. Def for special moves, after stat-stage multipliers.
- **STAB** is 1.5 when the move matches one of the user's types.
- **Crit** is 1.5, with a 1-in-24 chance.
- **Roll** is uniform between 0.85 and 1.00, drawn from the battle's random stream.

Type effectiveness is compressed:

| Main series | Cobbleseum |
|---|---|
| ×4 | ×1.6 |
| ×2 | ×1.3 |
| ×1 | ×1.0 |
| ×0.5 | ×0.8 |
| ×0.25 | ×0.6 |
| ×0 (immune) | ×0.25 |

Full ×4 hits would end real-time fights instantly, and immunities would make some matchups unwinnable.

### 9.5 Stat changes and status conditions

- **Stat stages** use the main-series multipliers, from −6 to +6, and last the whole battle for now. Whether they should wear off after a set time is still an open question (§19).
- **Status conditions:**

  | Status | Effect |
  |---|---|
  | Burn | 12 s; 1/80 of max HP per second; halves physical damage dealt |
  | Poison | 12 s; 1/64 of max HP per second |
  | Bad poison | 12 s; 1/320 of max HP times a level that rises every second |
  | Paralysis | 12 s; halves movement speed; a 25% chance each second of a 0.5 s stun |
  | Sleep | 1.5–3 s, or until hit; can't act |
  | Freeze | 1.5 s, or until hit by a Fire move; can't act |
  | Confusion | 6 s; each move has a 1-in-3 chance of becoming a 40-power self-hit |

  A fighter has at most one major status, plus confusion. Fire, Electric, Poison and Steel, and Ice types are immune to burn, paralysis, poison and freeze respectively. All values are starting points for tuning.
- **Effects from the data:** drain, recoil, the user's own stat changes (Close Combat, Draco Meteor) and secondary effects (a chance of a status, confusion or stat changes on hit) all come from Showdown's move data. Flinching isn't modelled.
- **Status-category moves:** self-buffs and heals apply on release; debuffs and status moves fly as projectiles. They wind up and recover in 0.4 s and have a 6 s base cooldown, so they can't be chained. Moves whose real effect lives in Showdown's code (Clangorous Soul, Fillet Away, Geomancy, Memento, Captivate) are left out, and four heals that Showdown computes in code (Morning Sun, Synthesis, Moonlight, Shore Up) get their amounts from a small override table. For the 850 standard moves this gives 26 self-buffs, 18 debuffs, 17 status moves and 10 heals.

### 9.6 Movesets

Every species gets one deterministic standard moveset, generated from its learnset (all generations) by a single policy:

- two attacks of its own types, using its better attacking stat;
- one coverage attack;
- one utility move: a buff, status move, heal or third attack.

Only playable moves are eligible. Details (`game/sim/movesets.gd`, report via `tools/movesets.gd`):

- **Learnable moves:** the species' learnset in every generation, plus its pre-evolutions', plus its base species' for forms with fewer than 25 moves of their own (Rotom's appliances, cosmetic forms).
- **Attack value:** power × expected hits × accuracy. Using the weaker attacking stat costs 40%; charge, recharge, recoil and self-destruct are discounted; fixed damage counts as 80 power.
- **Coverage:** an attack of another type gains 25% for each type it hits super effectively that the first two don't.
- **Utility:** sleep, paralysis, burn, poison, a buff to the species' attacking stat (more for more stages, Speed included), a heal, confusion or a debuff, scaled by accuracy. It's used if it scores at least 80, otherwise a third attack.
- **Ties** break by move ID, so the same data always gives the same moveset.
- A battle spec without `moves` uses the species' standard moveset.

Results for 1.8.4 and Showdown 0.11.11: 1,001 of the 1,005 roster entries get a moveset. Ditto, Wobbuffet, Wynaut and Pyukumuku learn no playable attack, and Magikarp and Unown get fewer than four moves. For the 381 species that have random-battle sets, 47% of the generated moves appear in those sets' movepools.

Using one policy for every species keeps rankings comparable. Showdown's Gen 9 random-battle sets cover only 338 of the 905 roster species, so they serve as a sanity check, not the source.

### 9.7 Balance

All rules constants live in one committed data file. Batch simulation (§13) reports:

- median battle length;
- draw rate;
- win rate for the side with type advantage;
- how often each move kind is used.

Constants are tuned against targets for these numbers.

## 10. Simulation and determinism

**Principles:**

- **No scene nodes or physics engine.** The simulation core is plain GDScript objects.
- **Simple geometric hit tests:**
  - capsules for fighters;
  - spheres, capsules, cones and rings for attacks;
  - swept tests for fast projectiles;
  - a circle for the arena wall.
- **Time is counted in ticks** at a fixed 30 Hz. The simulation never reads frame time or the clock.
- **Each tick:** read both sides' intents, apply them, then resolve hits in a fixed order. The order of sides alternates every tick, so neither side always goes first.
- **Randomness** comes from our own small pseudo-random generator, implemented in GDScript and checked against published test vectors. Replays therefore never depend on engine internals.
  - Separate streams are derived from the battle seed: battle (crits, damage rolls, secondary effects), AI side A, AI side B, and cosmetics.
  - Changing the AI or the visuals never shifts battle luck.
- **Animation never affects gameplay.** Hit timing comes from move data. Every species plays correctly whatever clips it has, and headless runs never load models.

**Battle spec** (input):
- rules version and data versions (manifest hashes);
- the two roster entries and their movesets;
- the AI profile for each side;
- the seed.

Battles with a player also record the intents on every tick.

**Battle record** (output):
- the spec;
- the result and length in ticks;
- an event log of hits, crits, status changes, dodges and knockouts;
- a checksum of the final state.

**What's guaranteed:**
- The same spec produces the same battle on the same Godot build and platform.
- Functions such as sin, cos and atan2 may give slightly different results on different operating systems or CPUs, so identical results across platforms aren't promised.
- A replay whose checksum doesn't match fails loudly instead of rendering a different battle.

**Run modes:**

| Mode | How the simulation advances |
|---|---|
| Interactive | One tick per 1/30 s of real time. Visuals interpolate between ticks at the display rate. |
| Headless batch | As fast as possible, with no rendering (`--headless`) |
| Recording | Under Movie Maker, a fixed number of ticks per video frame. Fewer ticks per frame gives slow motion; many ticks in one frame, without drawing, skips ahead. |

## 11. AI

The AI is a utility AI. At each decision step it scores every candidate action and picks one.

- **What it sees:**
  - its own state;
  - the opponent's state as it was one reaction delay ago, read from a buffer of recent states;
  - incoming hits: a projectile's predicted closest approach, or an opponent winding up a move that's in range.
- **Candidate actions:**
  - approach to a move's range, back off, or circle;
  - use move N;
  - dodge;
  - hold.
- **Considerations:**
  - Each consideration maps one input to a score from 0 to 1 through a `Curve` resource. Examples: target within this move's range, expected damage as a share of the target's HP, type effectiveness, own HP, time until an incoming hit, move ready, dodge charges left.
  - Hard vetoes, such as a move on cooldown, score 0.
- **Combining scores:**
  - An action's score is the product of its considerations, with a compensation factor so actions with more considerations aren't unfairly penalised.
  - The current action gets a commitment bonus, plus a minimum hold time, so the AI doesn't flip between choices every tick.
- **Choosing:** the highest score wins. Exact ties are broken by the side's AI random stream, never by list order.
- **Difficulty profiles** are resources. Each sets reaction delay, aim error, decision interval and mistake chance.
- **Rankings** use one fixed "ranked" profile on both sides.
- **Debugging:** an overlay shows each candidate's per-consideration scores.
- **Tests:**
  - unit tests per consideration;
  - scenario tests, such as "dodges a telegraphed projectile" and "doesn't use a melee move out of range".

## 12. Presentation and recording

The battle simulation is the source of truth, and presentation only reads it. Everything in this section can be as elaborate as we like without changing outcomes or determinism:

- the presentation never feeds back into the simulation;
- it draws its randomness from the battle's cosmetic stream.

### 12.1 Formats

- **Play is landscape** (1920×1080). Playing on a monitor wants 16:9, and one-on-one fights fill a wide frame naturally.
- **Clips come in either format.** Battles are deterministic, so one battle renders identically in every format.
  - Vertical 1080×1920, for Shorts, Reels and TikTok.
  - Landscape 1920×1080, for longer videos.
- **Everything visual is aspect-aware.**
  - Each shot type defines its framing for both orientations.
  - The HUD has a portrait layout, with HP bars at the top and bottom.
  - It also has a landscape layout, with bars top-left and top-right and fighter A always on screen-left.
- **How formats are rendered.** Milestone 1 confirmed two constraints:
  - Movie Maker fixes its output size at startup, before any script runs.
  - `--resolution` doesn't apply in `viewport` stretch mode.

  So for each render, the recorder writes a temporary `override.cfg` with the format's viewport size, then deletes it afterwards.

### 12.2 Presentation time

Presentation time is counted separately from simulation ticks. That makes timing effects possible without touching the battle:

| Mode | How the simulation advances |
|---|---|
| Normal play | One tick per frame, at 30 fps. |
| Hit-stop | On heavy hits, frames keep rendering for a few frames while the simulation holds still. |
| Slow motion | Fewer ticks per rendered frame, for knockouts and near-misses. |
| Skip ahead | Many ticks in one frame without drawing, to start a clip mid-battle. |

Recording runs the battle headless first, which produces the full event log. So the presentation knows in advance where every big moment is, including the knockout, and can build up to it.

### 12.3 Camera director

The camera director picks from a set of shot types based on battle events:

| Shot | When |
|---|---|
| Wide establishing | At the opening, and as the default between moments |
| Over-the-shoulder | When one fighter is closing in on the other |
| Attacker close-up | During the wind-up of a strong move |
| Projectile tracking | While a projectile is in flight |
| Impact punch-in | On a heavy hit, critical hit or super-effective hit |
| Low angle | On big hits from large fighters |
| Knockout orbit | Around the faint, in slow motion |

- **Cuts:** timed to events, with a minimum shot length so the edit never jitters.
- **Repeatability:** shot choices draw from the cosmetic random stream, so re-rendering a battle produces the same edit.
- **Readability:** every shot keeps both fighters readable, and no shot lets one fighter hide the other.

### 12.4 Impact frames and hit feedback

- **Hit-stop:** a few frames long, scaled with damage.
- **Impact frames:** on critical and super-effective hits, one or two full-screen high-contrast frames (a flash or silhouette) at the moment of contact.
- **Screen shake:** scaled with damage, and capped so it never obscures the action.
- **Speed lines:** on dashes and big wind-ups.
- **Hit flash:** on the defender's model, with a short knockback.
- **Callouts:** "Critical hit!", "It's super effective!", and damage numbers.

### 12.5 Move visuals, sound and HUD

- **Move visuals:** every damaging move has one of 20 visual styles, drawn in its type colour from simple meshes animated per video frame. Converting Cobblemon's own move particle effects (129 moves in 1.8.4) comes later.
  - Melee: strike (crescent), punch (shockwave star), kick (low arc), bite (closing fangs), slash (claw marks), rush (speed lines and dust).
  - Ranged: orb, bullet, beam, bolt (lightning), stream (breath and spray), pulse, sound, wind, powder, skyfall (drops onto the target), erupt (spikes from the ground), quake (ground wave), mind (glow on the target), explosion.
  - **Choosing a style:** the committed table `game/data/move_styles.json` (274 moves Showdown's flags don't describe, such as beams, breath and meteors), then Showdown's flags (punch, bite, slicing, bullet, pulse, sound, wind, powder), then strike for contact moves and orb for the rest.
  - Flat effects face the camera, so no shot sees them edge-on. A ranged move that hits as it fires gets a short point-blank version of its style.
  - `tools/preview_moves.gd` renders every style under a fixed camera for review.
  - Rings and waves for area moves and glows for buffs come with those kinds.
- **Sound:**
  - Cobblemon cries, impact sounds and whooshes, synced to events.
  - No music unless it is original or properly licensed.
- **HUD:**
  - Animated HP bars that drain with a lagging "damage taken" segment and shake on big hits.
  - Names and move-name callouts.
  - Intro and outro cards. Every clip ends with the credits card (§14).

### 12.6 Recording flow

**Movie Maker facts** (Godot 4.7 documentation):

- **Formats:**
  - OGV (Theora video, Vorbis audio). Available only in editor builds, so recordings run the Godot editor binary. The recorder renders OGV, then encodes it to MP4.
  - MJPEG AVI, capped at 4 GB.
  - PNG sequence plus WAV.
- **Command line:** `--write-movie <file>` with `--fixed-fps 30` gives exact frame pacing, whatever the hardware speed.
- **Audio:** the mix rate must be divisible by the frame rate. The project uses 48 kHz, which works at 30 fps.
- **Finishing:** quit through `get_tree().quit()` so the file is finalised; don't kill the process.
- **No headless rendering:** recording opens a window.

**Flow** (implemented in `tools/record.gd`):

1. Choose a matchup and seed, which gives a battle spec.
2. Run it headless to get the battle record.
3. Choose the clip window from the event log: at most 60 seconds, usually ending shortly after the knockout. `Highlights` scores events (hits by damage share, plus crits, super-effective hits and comebacks; misses a little; the faint or time-up a lot) and keeps the best-scoring window of the requested length. A window ends either a short linger after a hit or at the end of the plan, and one that reaches the faint always plays the whole knockout.
4. For each requested format, start a second Godot process under Movie Maker with that format's `override.cfg`. The process:
   - skips ahead to the window's start without drawing;
   - renders the window;
   - prints the final checksum.

   A frame limit makes sure it always exits.
5. Accept the movie only if its checksum matches the headless run.
6. Encode with ffmpeg to H.264 MP4 (yuv420p) with AAC audio.
7. Write the output to `recordings/<date>_<a>-vs-<b>_<seed>/`, which is git-ignored:
   - a `clip_<format>.mp4` for each format;
   - `battle.json`;
   - `credits.txt`.

## 13. Ranking (later)

- **Storage:** raw battle records go into an append-only JSON Lines store under `results/`, which is git-ignored. Ratings are always derived from the records, never stored on their own.
- **What a rating means:**
  - A species with its standard moveset, at level 50, under one rules version and the ranked AI profile.
  - A new rules version starts a new ranking.
- **Method:**
  - A Bradley–Terry model is fitted to all results, with each draw counting as half a win for both sides.
  - Unlike Elo, the fit doesn't depend on the order games were played. It uses every result and copes with incomplete schedules.
  - Glicko-2 can be added later to show uncertainty.
  - A matchup matrix of head-to-head win rates is published next to the ratings, because one-on-one matchups are often non-transitive.
- **Fairness:**
  - Every pairing is played from both sides with the same seeds.
  - An AI-sensitivity check re-ranks with a second AI profile and compares the rank correlation. A large change means the AI, not the Pokémon, is driving results.
- **Scale:** 905 species make about 409,000 pairings, or about 819,000 battles played from both sides.
  - Throughput is measured in milestone 1.
  - If a full round-robin is too slow, pairings are sampled adaptively, with more games where ratings are uncertain.
  - Headless processes run in parallel.
- **Balance tool:** the same machinery tunes the rules (§9.7).

## 14. Licensing and attribution

- **Repository:** original code and data only, under the MIT licence.
- **Cobblemon assets:**
  - Each model folder in the jar carries a Creative Commons licence matching Attribution-NonCommercial 3.0.
  - Until confirmed otherwise, textures and animations are treated the same way.
  - Cobblemon's code is MPL-2.0, but we don't use it.
- **Showdown data:** MIT.
- **Pokémon IP:** names and designs belong to Nintendo, Creatures Inc. and GAME FREAK. Cobbleseum is an unaffiliated fan project.
- **Consequences:**
  - The repository never redistributes assets.
  - Every clip credits Cobblemon on its end card and in generated description text.
  - Commercial use of clips needs permission. Whether clips will be monetised is an open question (§19).

## 15. Proposed project layout

```
project.godot
sources.json            pinned asset sources
game/
  sim/                  battle rules and simulation (no scene nodes)
  ai/
  presentation/         arena, fighters, camera, HUD, effects
  data/                 rules constants and override tables (original data)
tools/
  assets.gd             pipeline entry point
  sources/              one script per source
  convert/              Bedrock geometry, animation and Molang
  batch.gd              headless batch simulation
  record.gd             clip recording driver
tests/
  fixtures/             original, hand-made Bedrock files
cache/                  git-ignored; contains .gdignore
recordings/             git-ignored
results/                git-ignored
```

## 16. Testing

- **Unit tests** run in headless Godot, covering:
  - manifest and stamp logic, and the tar reader;
  - the Molang evaluator and Catmull-Rom sampling;
  - geometry conversion, against original fixtures with known expected vertices;
  - rules: the damage formula and the type table;
  - PRNG test vectors;
  - AI considerations.
- **Determinism tests:**
  - The same spec run twice gives the same checksum.
  - A different seed gives a different battle.
- **Real-asset QA** (§7.5) runs locally, because it needs the cache. No screenshots or renders of converted Pokémon are committed, since they would be derived from Cobblemon's assets.
- **CI** runs the unit tests and the asset guard without downloading any sources.

## 17. Milestones

**M1: vertical slice. Done (2026-11-09).**

- **Pipeline:** fetches, verifies and extracts Cobblemon 1.8.4 and Showdown 0.11.11, exports Showdown's data to JSON, and checks both layouts.
- **Converter:** Blastoise and Cinderace convert with working clips, and all 905 species pass a dry run.
- **Simulation core:**
  - Fixed tick, melee and projectile moves, the damage formula, cooldowns and knockouts, with a placeholder AI.
  - About 37 ms per battle headless, with identical checksums across processes.
- **Recording:** checksum-verified 10-second clips in vertical and landscape, encoded to MP4.

So far M1 has been tested on Windows only. macOS and Linux get checked before M2 ends.

**M2: rules and roster.**

- All supported move kinds, stat changes, status conditions and dodging. Movement, melee dashes, dodging, stat stages, status conditions and every move kind are done; the stand-in AI dodges about half the threats it sees while it can act, keeps a range suited to its ready moves, and circles.
- The moveset generator. Done.
- Full roster conversion with per-species caching, a QA report and the roster file. Done; the 73 `bounds_mismatch` species still need a converter QA pass.
- The procedural animation layer. Done.
- Batch simulation with a balance report, and a first tuning pass.

**M3: presentation** (everything in §12.2–§12.5):

- Presentation time: hit-stop and slow motion.
- The camera director and its shot list, framed for both formats.
- Impact frames, screen shake, speed lines, hit flashes and callouts.
- Type-themed move effects and sound.
- The animated HUD, with intro, outro and credits cards.
- Highlight selection for clip windows.

M2 and M3 don't depend on each other, so their order can swap if watchable clips matter sooner.

**M4: AI and play.**

- The utility AI, with profiles and a debug overlay.
- Player-vs-AI controls (keyboard and gamepad) and a player camera.

**M5: rankings.**

- The results store.
- The Bradley–Terry fit, matchup matrix and ranking report.
- The AI-sensitivity check.

**Later:**

- Cobblemon's move effects.
- Guarding.
- Field moves.
- Abilities and items.
- Shiny and form variants in clips.

## 18. Risks

| Risk | Mitigation |
|---|---|
| Licence and IP: Cobblemon assets are non-commercial, and Pokémon designs belong to their owners | No assets in git; attribution on every clip; monetisation decided explicitly |
| Conversion rules (axes, rotation order, UVs) are wrong in some cases | Golden tests on original fixtures; `.glb` debug export; QA pass over the whole roster |
| Most species lack attack, hit or faint clips | Procedural animation layer from M2 |
| Per-aspect bone visibility (hats, form-specific parts) handled wrong | Investigate with full roster conversion in M2 (§19) |
| GDScript simulation too slow for full round-robins | M1 measured about 37 ms per battle (roughly 1 hour for a full round robin on 8 processes); re-measure as rules grow; sample pairings before considering other options |
| Replays differ across platforms | Guarantee replays per platform only; checksums fail loudly |
| Real-time balance is our own design | Rankings are framed as "under Cobbleseum's rules"; batch-simulation tuning; AI-sensitivity check |
| A new Cobblemon release changes the layout | The pinned version never changes silently; layout checks give clear errors |
| Recording needs a window, and each format is a separate render | Clip windows of at most 60 s; skip ahead before the window; render only the formats needed |

## 19. Open questions

1. Will clips be monetised? Cobblemon's assets are non-commercial (§14).
2. How does Cobblemon hide bones per aspect (hats, form-specific parts)? The converter must reproduce it, or the wrong parts will show.
3. Starting values for the tuning constants: HP multiplier, cooldown formula, speed band, dodge charges and status durations.
4. Should stat stages wear off after a set time?
5. Cobblemon's per-model licence files cover models, animations and textures. The jar states no separate licence for its sounds, so the credits assume the same CC BY-NC 3.0 terms. Confirm with the Cobblemon team before any wider release.

Resolved in milestone 1: tests use a small in-house runner (`tests/run_tests.gd`) instead of an add-on; recordings use OGV from Movie Maker, encoded to MP4.
