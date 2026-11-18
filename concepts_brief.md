# Cobbleseum concept brief

Status: living document. First draft 2026-11-08; presentation section and milestones revised 2026-11-09; milestones M11–M17 added from a battle review 2026-11-17.

## 1. Summary

Cobbleseum is a local-first 3D Pokémon battle game built with Godot 4.

- **Battles:** two Pokémon fight in real time in a small arena. They are rendered with the models, textures and animations of the Cobblemon mod.
- **Modes:** player-vs-AI and AI-vs-AI.
- **Clips:** AI-vs-AI battles can be recorded as video clips: vertical 1080×1920 for short-form posts, or landscape 1920×1080, from the same battle.
- **Rankings:** many battles are simulated to keep a local ranking of every Pokémon.

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
4. Simulating many battles and keeping a local ranking per Pokémon.

Non-goals:

- **Out of scope for the project:**
  - Online multiplayer, mobile builds and a hosted website.
  - **Main-series accuracy.** Cobbleseum borrows stats, types, moves and the damage formula, but its real-time rules are its own. Rankings measure strength under these rules, not competitive strength in the main-series games.
  - Pokémon GO as an asset source.
- **Left out of the first version:**
  - Terastallization, Mega Evolution and Gigantamax.
  - Abilities and held items beyond M9's first sets (§9.9, §9.10).
  - Arena moves such as weather, Pokémon's terrains, entry hazards and screens. Weather, surges (Pokémon's terrains) and screens came in M10 (§9.11); entry hazards wait for team battles.

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
| Particle effects | `assets/cobblemon/bedrock/particles/**/*.json`, Bedrock particle format 1.10.0 | 1,114 (617 in 128 move folders) |
| Particle textures | `assets/cobblemon/textures/particle/**/*.png` | 548 |
| Scripted move effects | `data/cobblemon/action_effects/**/*.json` | 156 (138 for moves) |
| Species data | `data/cobblemon/species/generationN/<name>.json` | 1,025 |
| Model licences | `assets/cobblemon/bedrock/pokemon/models/NNNN_name/license` | one per model folder |

**Terms used below:**

- A **poser** says which animations a species plays in each pose, such as standing or flying in battle. It also lists one-off animations (physical attack, special attack, cry), head-tracking bones and idle quirks like blinking.
- A **resolver** lists a species' visual **variations**. Each variation is selected by **aspects** (shiny, female, Alolan, …) and names a model, a texture, a poser and optional extra texture layers.

**What we use:** geometry, animations, textures, posers, resolvers, cries, move sounds, and the particle effects with their textures (as pieces of our own move sequences, §12.5; the scripted move effects only as a reference). From the species data we use only the `implemented` flag and `baseScale`. All battle data comes from Showdown, so stats and moves have a single source of truth.

**Facts that shape the design:**

- **Missing models:** 905 of the 1,025 species are implemented with a model. The 120 without include many legendary and mythical Pokémon, such as Celebi, Entei, Raikou, Suicune, Deoxys, Groudon, Kyogre, Jirachi, Arceus and Darkrai.
- **Forms:** regional forms exist as resolver variations: 66 Alolan, 43 Hisuian, 40 Galarian and 12 Paldean variation entries. There are no Mega or Gigantamax forms. Cosmetic forms are variations too: 153 female entries, plus patterns, colours, trims, seasons and letters (§12.8).
- **Shinies:** every one of the 905 species has a shiny variation (1,179 shiny variation entries, counting forms), and none of their textures is missing. Most swap only the texture; three change the model or poser too (Gastly, Slugma, Magcargo).
- **Animation coverage is uneven.** Of the 904 species with animation files:

  | Animation | Species with it |
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
  - 316 species have no walk, run or fly animation.
- **Posers:** 248 species have no JSON poser. Their pose logic is compiled into the mod's code, which we can't use.
- **Molang:** 714 of the 1,010 animation files contain Molang expressions, Bedrock's small expression language.
  - Almost all of them are functions of animation time: `q.anim_time` with `math.sin`, `math.cos` and `math.clamp`.
  - `math.random` appears 244 times.
  - All 206,054 keyframes in the jar use Catmull-Rom interpolation.
- **Geometry** uses only "box UV" texture mapping, with no per-face UVs. Inflated, rotated and mirrored cubes are common. Models have a median of 57 cubes, with a maximum of 566. Textures are between 64×64 and 256×256 pixels.
- **Hitbox data is unreliable.** One species has a height of 0. Hitboxes therefore come from converted model bounds (§8).
- **Move effects:** the jar ships 617 Bedrock particle effects for 128 moves, 138 scripted move effects and 390 move sounds. Only 43 of the 246 moves in our movesets have an effect of their own (about 28% of move slots).
  - The particles use billboards (517 with flipbooks), gradient tints, `math.random`, ground collision, sub-effect events, and Cobblemon's `v.target_deltax/y/z` and `v.target_distance` for aiming.
  - The scripts are timelines of pauses, particles on the user or target, sounds and animations, about 2.7 s per move and turn-based; none moves the camera.
  - Eight referenced textures are Minecraft's own or broken paths, and four referenced effects are missing from the jar.

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

**Credits.** The pipeline collects the licence of every converted model into a credits file. The game's credits screen and every clip's credits card use it.

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
  - Back faces are culled. A zero-thickness plane's two faces face opposite ways, so each side shows its own texture (Charizard's wings: orange outside, teal inside); drawing both sides of every face put the two in the same place, and they flickered as they fought over each pixel. Inverted (negative-size) cubes, such as the inside of a cap, face inward and show from inside. The roster has about 33,000 zero-thickness cubes and 425 inverted ones.
  - Glowing and translucent layers come from the resolver.
  - Animated layers (a list of texture frames plus a frame rate) become flipbooks.

### 7.3 Animations

**The format.** An `.animation.json` file holds animations named `animation.<species>.<name>`. Each animation has:

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
3. `math.random` gets a fixed seed per animation, so converted animations are deterministic.

**Molang.** A small parser and evaluator covers the subset found in the jar:

- **Syntax:** numbers, arithmetic, comparisons, logical operators, the ternary operator and parentheses.
- **Functions:** `math.sin` and `math.cos` (in degrees), plus `clamp`, `abs`, `mod`, `round`, `pow`, `min`, `max`, `sqrt`, `ceil`, `exp`, `random` and `random_integer`.
- **Time:** `q.anim_time` and `query.anim_time`.

Unknown queries and variables, such as riding yaw and a few custom variables, evaluate to 0 and are reported. Asset text is never evaluated as code.

**Posers:**

- For the 657 species with a JSON poser, the converter reads:
  - the animations for each battle pose;
  - the named one-off animations: physical, special, status, cry and recoil;
  - head-tracking bones and their limits;
  - quirks such as blinking.
- **Blinks:** the standing pose's blink quirks, which can be several where each head or eye blinks on its own (Maushold's mice); without a poser, every animation named `blink`, `blinkN` or `blink_N` (Doduo's and Dodrio's heads, Mr. Rime). The game picks one at random for each blink.
- The 248 species without a poser use a name-based fallback: `battle_idle`, else `ground_idle`, with `air_idle` for species that fly. Other roles also fall back on names, including Cobblemon's variants that are real animations: `battle_sleep` and `ground_sleep` (Garchomp's own sleep pose uses `battle_sleep`), `battle_faint` and `physical_attack`. Unfinished ones (`faint_WIP`, `ground_walk_placeholder`) are left out.
- **Air animations and parts:** the hover pose's animation fills the `air_idle` role and the fly pose's animation fills `air_fly` (about 120 species), falling back to animations of those names. Poses also show or hide parts (`transformedParts`), mostly open or folded wings on about 40 birds; the standing pose's set and the hover (else fly) pose's set are stored as the model's `parts`. In the game, a `PartSwap` skeleton modifier scales the hidden parts' bones to zero after the animation has posed them, so either stance works with any animation. Before this, both sets of wings showed at once.

**Resolvers:** the converter takes the base variation (no aspects) or the requested aspects (shiny, female, regional form). Shinies and cosmetic forms are converted as their own looks (§12.8).

### 7.4 Playback

Animations play in three layers:

1. **Base loop:** an idle or locomotion animation, crossfaded between states in 0.15 s. Walk and run animations play faster or slower to match movement speed (normal speed at 2.5 m/s walking and 4.5 m/s running for a 1.5 m fighter, scaled by the square root of its height, between 0.6× and 1.7×). A walk or run that is only a held pose (Bulbasaur's, among others) is treated as missing, so the procedural hop moves the fighter instead of sliding a statue. Base animations are padded so that bones they don't key hold the idle pose; otherwise a crossfade passes through the rest pose and the model briefly looks like it's in a T-pose. They also put back, at its rest pose, every bone that only other animations move (eyelids, mouths, a fidget's paw): Godot leaves a bone no playing animation tracks where it was last put, so eyes closed by a hit stayed closed.
2. **One-off actions** on top: attack animations, applied only to the bones they key, crossfaded in 0.05 s so they answer the battle at once. An attack is fitted to its wind-up so its strike lands as the move goes off: the strike is where its bones turn fastest (`AnimationTiming`; Cobblemon's 3 s attack animations strike about 1.2 s in), and the animation plays up to 2× faster and starts partway in to reach it on the release. They play once: Cobblemon loops many of its hurt, angry, sad and shocked animations (about 400 species), which would otherwise never end.
3. **Additive reactions:** hit recoil, cries and blinking, applied as offsets from rest and faded in and out.

**Procedural layer.** Most species lack attack, hit or faint animations, so a procedural layer on the model root fills the gaps:

- a hop, bob or glide for movement;
- a lunge, spin or squash-and-stretch for attacks;
- a tilt and knockback for hits;
- a tip-over and fade for knockouts.

Implemented in `game/presentation/procedural_motion.gd`, as a transform on a node between the fighter and its model, so it stacks with animations, knockback and the hit flash. It fills in only the animation roles a species has no animation for:

- a hop while walking (408 entries have no walk animation);
- a lunge for physical moves, a rear-back with squash and stretch for special moves, and a spin for status moves; the lunge reaches furthest and the rear-back springs forward as the move goes off;
- a backward tilt for hits;
- slow breathing while asleep, and gentler breathing with a slight bob at rest when the idle is a held pose (786 of 1,005 converted species, many of them standing still in Cobblemon too, from the Eevee line and Gengar to the legendary birds) or missing;
- tipping over onto its side for knockouts, instead of fading. It's lifted as it tips so the body comes to rest on the ground (only a twentieth of the silhouette, such as an outstretched fin or wing, may dip into it) rather than through it.

Species with a faint animation of their own drop out of a hover to the ground, and are lifted wherever the animation would sink them into it (Tinkaton, Clefairy, Jigglypuff and Raichu sink by 10–40% of their height).

Flying types that can really fly hover and bob throughout: those Cobblemon lets fly (its species' `canFly`, listed in the roster as `flies`) or that have a flying animation, plus any species whose idle is its air idle. Flightless Flying types (Doduo, Dodrio, Natu, Mantine, Mantyke, Archen, Hawlucha) walk. Hovering is presentation only; the simulation's gliding and climbing still follow the Flying type. Serpents whose animations hold their body still (Rayquaza, whose only animation is a held pose, plus Seviper, Silicobra and Eternatus) get a travelling wave down their `segment` bones (`BodyWave`): gentle at rest, stronger and faster when moving, frozen in hit-stop. They slither instead of hopping, and on a knockout drop to the ground without tipping over, which would stand their coils on end. The layer advances per video frame at the animations' speed, so it freezes in hit-stop and slows in slow motion.

Since M6 it also adds life on top of every animation, for every species:

- leaning into movement: pitched forward by forward speed and banked by sideways speed, twice as much for fliers;
- fliers swooping low when moving faster than walking (from 4 m/s, fully at a 10 m/s melee dash);
- a squash on landing from a dodge;
- head tracking: models with a `head` bone (about three in four) turn it up to 60° toward the foe, eased, through a small skeleton modifier (`HeadTurn`); past 110° off to the side the head turns back to centre.

Knockback is the simulation's own since rules version 9, so the view no longer fakes it.

**More of Cobblemon's animations** (presentation only):

- **Cries:** each fighter plays its cry animation when the battle opens, in time with its cry sound.
- **Blinks and fidgets:** a second animation player layers the blink animation (about 940 species; one of several where heads or eyes blink separately), and now and then one of the standing pose's idle quirks (look around, sniff, tail twitch; about 200 species, only while idling), every 2–6 s. It's seeded by the model, so renders repeat exactly, and it only touches the bones those animations move.
- **Emotions:** a crit or super-effective hit plays `shock` (falling back to `surprised`) instead of the hit animation, a stat drop while ready plays `angry`, the winner loops `happy`, and a time-up draw plays `sad` on both (about 100–210 species each).
- **Running:** grounded fighters with a `ground_run` animation run above 3.5 m/s.
- **Sleeping in the air:** hovering species with `air_sleep` sleep in mid-air.

### 7.5 Quality checks

A QA pass over every roster species reports:

- animations that leave the model in its rest pose;
- feet sinking below the floor;
- wrong facing;
- unknown Molang;
- missing animations.

The report feeds the roster flags (§8). The QA runs locally, and its reports stay in the cache.

**Visual review.** `tools/preview_roster.gd` renders roster species as they appear in battle: at roster scale, partway into the idle animation, beside their hitbox capsule. It writes a contact sheet, either for named species or for every species with a QA flag. The first pass, in M2, covered every flagged species and all 100 forms, and found:

- **Rest poses aren't real faults.** Comparing rest-pose height with the hitbox flagged 73 species, but rest poses are often stretched out (Seviper's is 10.6 m tall), and every one looked right in its idle pose. The QA now samples the idle animation instead (`pose_mismatch`, 33 species). These are models that are genuinely bigger than their hitbox because of wings, flames, claws or tails, and they also look right.
- **Missing texture layers.** Resolver variations can add texture layers over the model: emissive eyes, flames and markings, Vivillon's wing patterns, manes and translucent parts. 186 roster entries use them. The converter now draws them as extra material passes: emissive layers unshaded, the rest shaded with alpha.
- **Animations in the wrong group.** Forms with a poser of their own (Gourgeist's sizes) still use the species' animations, and some species' idle animations are named `air_idle`, `water_idle` or `idle`. Animation lookup now searches the poser's group, then the species', then any other group in the files. It accepts those names, and uses a non-battle standing pose when there's no battle one. Species without an idle animation went from 58 to 7.

## 8. Roster and species identity

- **Roster:** every species that has both a Cobblemon model and Showdown data. For Cobblemon 1.8.4 that's 1,005 entries: all 905 species, each matching a Showdown species by normalised name, plus 100 forms that Showdown lists as separate species (regional forms, Rotom's appliances, female forms and others).
- **Identity:**
  - Species are identified by Showdown ID (`charizard`, `ninetalesalola`).
  - Each ID maps to a Cobblemon species folder plus a list of aspects (`ninetales` + `alolan`).
  - The mapping is generated by name matching: a Showdown forme ("Alola") matches the Cobblemon form of the same name, whose aspects select the model through the species' resolver variations. No overrides table has been needed so far.
  - Battle-only forms (Mega, Gigantamax, Primal, Crowned, Zen and similar) are excluded.
  - Forms that change nothing in battle (East Sea Gastrodon, Vivillon's patterns, female models) aren't species: they're cosmetic forms of one, shown only by the presentation (§12.8).
- **Missing models:** species without a Cobblemon model are left out of play, clips and rankings. There are no placeholders, because a stand-in model would look broken in a posted clip.
- **Size:** in the data, heights run from under 0.5 m (82 species) to 6.5 m.
  - Each species' size comes from Cobblemon's own gameplay hitbox (`hitbox` width and height, a form's own when it has one) multiplied by its `baseScale`. Rest-pose model bounds turned out to be unreliable for coiled or stretched-out models (Seviper measures 11.7 m), so they're used only for the 3 entries without a hitbox.
  - The height is clamped into a band of 0.5–3 m, and the same factor scales the model and the hitbox radius, so a giant isn't trivially easy to hit.
  - The hitbox is a vertical capsule of the scaled height, with a radius of half the scaled hitbox width, clamped to 0.25–1.5 m.
  - For 1.8.4 the median height is 1.05 m and the median radius 0.38 m.
- **Roster file:** the pipeline writes one entry per species:
  - Showdown ID, Cobblemon folder and aspects;
  - scaled height and capsule;
  - available animations and whether a poser exists;
  - QA flags and licence;
  - its shiny and its cosmetic forms, each with its own model and shiny (§12.8).

  Headless simulation reads only this file and never loads models.
- **QA report:** `report.json` counts species per flag: missing animation roles (`no_idle`, `no_faint`, …), `no_poser`, `no_hitbox`, `no_licence_file` (410 entries whose model folder has no licence file), Molang and bone problems, and `pose_mismatch` (33 entries whose height in their idle pose differs from their hitbox by more than 2×; reviewed in M2 and all correct, see §7.5).
- **Caching:** each converted model has a key over its input files and the converter scripts. Rebuilds reuse models whose key still matches, from the previous build or an interrupted one.

## 9. Battle rules

### 9.1 Battle setup

- One-on-one, in a round arena with walls (no ring-outs), 14 m in radius since rules version 13 (8 m until version 11, then 11 m), with fighters starting 10 m apart. Once fighters kept their distance (version 9), 8 m was cramped: they spent 11% of the time within a metre of the wall, 6% at 11 m. With terrain (§9.8) the extra room holds plateaus and cover; fighters don't use all of it at once, and needn't. Rankings use this one size.
- The simulation runs at a fixed 30 ticks per second.
- **Teams** (M15, rules version 24): a side brings a team of 1–6 Pokémon, one out at a time (`Battle.teams`; `fighters` holds each side's one out). After a knockout with more of the team to come there's a 2 s lull, then the next is sent out at its side's start spot, taking 1 s to land, unhittable throughout; until it lands the fighter left standing can only walk, and projectiles in flight vanish. The battle ends when a side has no one left. Abilities that act on entry act on every send-out (weather and surge setters; Intimidate on its first tick). A battle of one Pokémon a side plays exactly as before.
- **Pace** (rules version 28): in a team battle every fighter's HP is multiplied by 1/√n, n the larger team's size (×0.71 for 2, ×0.58 for 3, ×0.41 for 6), so a full 6v6 lasts about 2.5–3 minutes, around 20 s a knockout. The overtime clock restarts at each send-out after a knockout: each stretch between knockouts gets the one-on-one clock (overtime from 60 s, the cap at 90 s). At the cap a team battle goes to the side with more Pokémon left, then to the higher share of its team's HP left, and is a draw only if both are even; one-on-one time-up stays a draw.
- **Switching** (rules version 25): whenever its fighter could act, a side can switch it for a healthy bench member. The fighter is recalled and the incoming one lands where it stood over 1 s, open to hits and unable to act. Stat stages, confusion, bad poison's count and ability timers clear on the way out; HP, major status and its timer and move cooldowns stay with the Pokémon, frozen on the bench, and nothing reaches a benched Pokémon (recoil or drain from its own projectiles still in flight included). Every send-out, a switch, the one after a knockout or the leads' at the start (since rules version 29), starts a side-wide 5 s switch cooldown. During the lull after a knockout, the side's switch intent picks who comes out (else the first left). In play, Q (D-pad left and right) cycles the highlighted bench member on a bar above the moves and E (D-pad up) switches to it; after a knockout the highlighted one comes out.
- **Doubles** (M17, rules version 30): a spec's `"doubles": true` sends out the first two of each side's team of 2–6 at once, each in a **place** (0 or 1) 2.5 m either side of its side's start spot, across from the foe in the same place. Each fighter is locked onto one foe's place (a `"target"` intent changes it whenever the fighter could act): its facing, melee dash, projectiles, feints and guards follow that foe, and while that foe is down the lock passes to the other until a newcomer takes its place. Area moves are **spread moves**: they hit every foe in their ring, and the ally too for Showdown's `allAdjacent` moves (Earthquake, Surf, Explosion), at ×0.75 each when they hit more than one; spread status and debuff moves fire a projectile at each foe in range. Single-target moves never touch the ally, and allies can't pass through each other. After a knockout the place is refilled after the usual lull while the other three fight on (nobody can only walk), projectiles aimed at the fallen fighter vanish, and once the bench is empty the side fights on alone. Either fighter can switch, under the side's one switch cooldown. Each fighter out has its own controller and AI stream. Singles plays exactly as before. **Pace** (rules version 34): in doubles every fighter's HP takes a team of two's factor (×0.71) whatever the team size, since each fighter takes hits from two foes; a 2v2 lasts about 54 s, a 4v4 about 95–100 s and a 6v6 about 2.5 minutes, the overtime clock restarting at each send-out after a knockout as in singles.
- **Length:** battles should last 30–45 seconds. From 60 seconds, **overtime** raises hit damage by 10% per second (×4 by the cap), so slow matchups finish. At 90 seconds the battle ends in a draw.
- **Controls:** both fighters are controlled through the same intents:
  - a movement direction;
  - dodge;
  - use move 1–4;
  - feint move 1–4 (§9.2);
  - guard (§9.2);
  - switch to team member N (team battles, below).

  The AI and the player produce identical intents.

### 9.2 Fighters

- **Stats:** level 50, all IVs 31, no EVs and a neutral nature, so stats come from the species alone.
- **HP:** the HP stat times a global HP multiplier (22 after the first tuning pass, 19 since held items in rules version 19, §9.7). Tuning the multiplier sets battle length.
- **Speed:** the Speed stat maps into a band of movement speeds. It also sets how quickly dodges recharge.
- **Dodges:** each fighter has 2 dodge charges, each recharging in 3 s (slowest) to 1.5 s (fastest, by Speed). A dodge is a 2.5 m dash over 0.2 s, invulnerable throughout: projectiles fly on through and melee strikes whiff. A fighter can't dodge while winding up or recovering, so attacking commits it.
- **Feints** (rules version 16): a fighter can fake the wind-up of a ready melee or area move that's in reach. A melee feint dashes in like the real thing. The feint breaks off, unreleased, with 3 ticks of the wind-up left, so to the foe it looks like a strike until its last moments, and both AIs dodge it as one. It deals no damage and spends none of the move's cooldown, but the fighter can't feint again for 3 s, and it can't dodge while feinting. The point is to draw a dodge, ideally the foe's last charge, and strike while the foe can't dodge. Projectile, heal and status wind-ups can't be feinted: nothing reacts to them before the release. In play, hold Shift (or LB) with a move key.
- **Guarding** (rules version 17): a fighter can raise a guard, a short parry that holds its ground where a dodge moves it. For 0.35 s it blocks every hit whose source is within 90° of its facing (the attacker for melee and area moves, where a projectile came from), and it turns to face the foe at the wind-up rate. A blocked hit deals no damage and has no secondary effects, drain or recoil.
  - **Parry:** blocking a melee strike staggers the attacker: its recovery lasts at least 0.5 s and its remaining multi-hit strikes are lost, so the guard opens a window to punish.
  - **Whiff:** if nothing was blocked, the guard ends in a 0.3 s recovery in which the fighter can't act or dodge. A guard that blocked something stays up for its 0.35 s, then skips the recovery.
  - **Cost:** a 3 s cooldown from when it's raised. It can't be raised while winding up, recovering or dodging, and the fighter can't move or dodge while guarding.
  - **Against feints:** a feint baits a guard just as it baits a dodge: the guard whiffs into its recovery and the real strike lands. The AI's feint opening widens to match (§11).
  - In play, G (or RT).
- **Movement:** fighters walk at their speed, can't pass through each other (they slide around) and stay inside the wall. Since rules version 9 they speed up and slow down (14 m/s²) rather than starting and stopping instantly, and the slide out of a dodge carries on briefly.
- **Facing:** fighters turn at 360° a second (900° while winding up, to aim). Walking, they face between the foe and where they're going, so they turn away to run and square up to fight, instead of always staring at each other.
- **Agility** (rules version 10): acceleration and turning scale with body, by the square root of the Speed stat over 120 (a base-100 species) times (50 kg / weight)^0.15, within ×0.6 to ×1.5. Heavy, slow species lumber; light, fast ones dart, and the utility AI switches strafe direction more often for them. Flying types brake at half their acceleration, so they glide to a stop.
- **Knockback:** a hit pushes the defender away at up to 5 m/s (at 8% of max HP or more, less for smaller hits), scaled by weight: lighter species fly further, heavier ones barely move (within ×0.5 to ×1.5 of a 50 kg species).
- **Flying:** Flying-type species, and species whose only idle is an air idle, hover above the ground. Hovering species with air animations play `air_idle` and `air_fly` instead of idle and walk, with their air parts (open wings). Species with air animations only for being ridden in flight (Blastoise, Garchomp) stay grounded. This is presentation only.

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
- **Self-destructing moves** (Explosion, Self-Destruct, Misty Explosion) knock out the user.

For the 850 standard moves, 628 are playable: 243 melee, 238 projectile, 64 area, 26 self-buff, 18 debuff, 17 status, 10 heal and 12 arena moves (§9.11). The rest are other arena moves, special cases and moves whose power is computed in code.

**Not in the first version:**
- The side and field conditions besides weather, surges, screens and entry hazards (§9.11) are special cases.
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

- **Stat stages** use the main-series multipliers, from −6 to +6. They wear off: every 6 seconds without a change, each stage moves one step back toward 0, so a +2 lasts about 12 seconds and a −6 recovers in about 36.
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
- **Status-category moves:** self-buffs and heals apply on release; debuffs and status moves fly as projectiles. They wind up and recover in 0.4 s and have a 6 s base cooldown, so they can't be chained.
- **Heals are a channel** (rules version 7): a 1.2 s wind-up that any hit cancels (the cooldown is still spent), restoring half the main-series amount (Roost and Recover heal 25% of max HP). In the main series a heal costs a turn in which the opponent hits freely; in real time an uninterruptible 0.4 s heal of 50% cost almost nothing, so species with one won about 34 points more often than without it, and the first ranking was topped by Flying types carrying Roost. Under version 7 the edge is about 10 points (77% vs 67% for 12 healers against 41 opponents), and the utility AI heals only when the opponent can't land a hit before the channel ends (its `cover` consideration). Movesets still value heals at the main-series amount, so they pick the same moves. Moves whose real effect lives in Showdown's code (Clangorous Soul, Fillet Away, Geomancy, Memento, Captivate) are left out, and four heals that Showdown computes in code (Morning Sun, Synthesis, Moonlight, Shore Up) get their amounts from a small override table. For the 850 standard moves this gives 26 self-buffs, 18 debuffs, 17 status moves and 10 heals.

### 9.6 Movesets

Every species gets one deterministic standard moveset, generated from its learnset (all generations) by a single policy:

- two attacks of its own types, using its better attacking stat;
- one coverage attack;
- one utility move: a buff, status move, heal or third attack.

Only playable moves are eligible. Details (`game/sim/movesets.gd`, report via `tools/movesets.gd`):

- **Learnable moves:** the species' learnset in every generation, plus its pre-evolutions', plus its base species' for forms with fewer than 25 moves of their own (Rotom's appliances, cosmetic forms).
- **Attack value:** power × expected hits × accuracy, times what the standard ability (§9.9) always adds to that move (Technician, Iron Fist, Sheer Force, Skill Link's five hits; Rock Head and Magic Guard drop the recoil discount). Using the weaker attacking stat costs 40%; charge, recharge, recoil and self-destruct are discounted; fixed damage counts as 80 power. A drop to the stat the move attacks with is charged twice at the stage multiplier (Superpower's −1 halves the value, Draco Meteor's −2 leaves a third): with no switching, the drop weakens every later attack on that stat until it wears off. Probes showed species carrying Draco Meteor, Overheat or Superpower winning 17–30 points less than with the next-best pick.
- **Coverage:** an attack of another type gains 25% for each type it hits super effectively that the first two don't.
- **Utility:** sleep, paralysis, burn, poison, a buff to the species' attacking stat (more for more stages, Speed included), a heal, confusion or a debuff, scaled by accuracy. It's used if it scores at least 80, otherwise a third attack.
- **Ties** break by move ID, so the same data always gives the same moveset.
- A battle spec without `moves` uses the species' standard moveset.

Results for 1.8.4 and Showdown 0.11.11: 1,001 of the 1,005 roster entries get a moveset. Ditto, Wobbuffet, Wynaut and Pyukumuku learn no playable attack, and Magikarp and Unown get fewer than four moves. For the 381 species that have random-battle sets, 48% of the generated moves appear in those sets' movepools (47% before movesets weighed abilities).

Using one policy for every species keeps rankings comparable. Showdown's Gen 9 random-battle sets cover only 338 of the 905 roster species, so they serve as a sanity check, not the source.

### 9.7 Balance

All rules constants live in one committed data file. Batch simulation (§13) reports:

- median battle length;
- draw rate;
- win rate for the side with type advantage;
- how often each move kind is used.

Constants are tuned against targets for these numbers. `tools/batch.gd` runs seeded random matchups of every roster species with its standard moveset and writes the report to `results/`.

**First tuning pass** (rules version 6, including stage decay; 500 battles each, two seeds; about 57 ms per battle):

| | Before | After | Target |
|---|---|---|---|
| Median length | 14.1 s | 36.8–37.5 s | 30–45 s |
| 10th–90th percentile | 8.2–28.5 s | 17.7–76.6 s | |
| Draws | 2.5% | 3.8–4.4% | under 5% |
| Type-advantaged side wins | 56.6% | 56.7–59.1% | no target yet |

- **Changes:** the HP multiplier went from 8 to 22, which put the median in range. That pushed the slowest 10% (resisted matchups and weak unevolved species) into the 90 s cap, so overtime was added to finish them.
- **Move use:** melee 43–44%, projectile 35%, area 12–13%, self-buff 7%, heal 1%, status 1%. Debuffs are almost never in a generated moveset.
- **Side bias:** with every matchup run both ways round, side A wins 49.2% of 571 decided battles.
- **AI fix:** the stand-in AI weighs its own attacking stat stage, charges moves that lower it (Overheat, Draco Meteor) for the drop, and won't use them below −2, waiting for the stage to wear off instead. Since rules version 8 the utility AI honours that veto (its damage curve's floor used to turn it into a usable score) and adds a `stage_cost` consideration when the drop would weaken its other attacks on that stat, a boost thrown away included.
- **Remaining draws:** mostly mutually resisted matchups with many dodged hits, such as Charizard vs Noivern.
- **Rules version 7** (heal channel, 1,000 battles): median 30.7 s, 10th–90th percentile 16.5–64.3 s, draws 1.4%, heals 1.1% of move uses.
- **Rules version 34** (doubles pace, §9.1): singles and singles team battles play exactly as before (the 1v1 and 3v3 batches matched version 29 battle for battle). Under the singles team factor (1/√n) doubles ran short: 2v2 54 s, 4v4 75 s, 6v6 96 s (80 random battles each, seed 43). With every doubles fighter at a team of two's factor (×0.71): 2v2 54 s, 4v4 102 s and 94 s (seeds 43 and 44, 10th–90th percentile 65–145 s), 6v6 145 s and 151 s (98–240 s), 5.3–5.5 and about 8 knockouts a battle, side A 42–58%, no time-ups or draws. One factor for every size keeps the rule simple; a 6v6 lands at the low end of its 2.5–3-minute target.
- **Rules version 33** (abilities in doubles, §9.9): singles and singles team battles play exactly as before (the 1v1 and 3v3 batches matched version 29 battle for battle). 31 of the 100 standard 4v4s of seed 41 changed (Intimidate reaching both foes, the rod abilities drawing moves); seeds 41 and 42: medians 74.8 s and 75.8 s (73.5 s under version 32 for seed 41), side A 56% and 51.5%, abilities 2.9 and 3.6 times a battle (2.8), no time-ups.
- **Rules version 32** (ally moves, §9.11): singles, singles team battles and the standard doubles batch play exactly as under version 31 (standard movesets never pick ally moves). Paired probe (60 random 4v4s per move, seed 61, side A's second member carrying the move in place of its last standard move against the same battles without it): side A wins 33% without; with Helping Hand 53% (used 3.9 times a battle), Life Dew 50% (4.3), Coaching 47% (5.1), Follow Me 43% (0.9), Wide Guard 37% (1.1). Small samples, so roughly: a support move is worth about an attack or more to a doubles team, Helping Hand most.
- **Rules version 31** (the doubles AI, §11): singles and singles team battles play exactly as before (the same two batches matched version 29 battle for battle). Doubles batch (100 random 4v4s, seed 41): median 73.5 s (62.3 s under version 30), 10th–90th percentile 48–111 s, 5.3 knockouts and 4 switches a battle, side A 54%, no time-ups; fighters dodge and guard more now that they watch both foes.
- **Rules version 30** (doubles, §9.1): singles and singles team battles play exactly as before (the 300-battle one-on-one batch, seed 5, and the 150-battle 3v3 batch, seed 31, matched version 29 battle for battle, events included). A first doubles batch (100 random 4v4s, seed 41, before the doubles AI and pace) ran a median 62 s (42–89 s), with 4.9 knockouts and 4 switches a battle and no time-ups.
- **Rules version 29** (the leads' send-out starts the switch cooldown, §9.1; 150 random 3v3s, seed 31): median 98.9 s (101 s under version 28), 3.5 switches a battle (2.9), side A 47.3% (54%). Until then the AI could switch on the first tick, before anything had happened. One-on-one has no switching, so it plays as before.
- **Rules version 28** (pace, §9.1; team batches of random teams, seeds 31 and 32): 3v3 median 101 s and 96 s (10th–90th percentile 54–151 s), 6v6 165 s and 175 s (106–245 s), 7.9 knockouts a 6v6, about 21 s each; time-ups 7% and 1.5% of 3v3s, 3% and 7% of 6v6s (won on Pokémon left); side A 54% and 52.5% of 3v3s, 59% and 47% of 6v6s (100 battles each, so noise). A first version also scaled the per-knockout clock by the HP factor; its short stretches ended 36% of 3v3s and 75% of 6v6s at time-up. One-on-one battles play exactly as before (the 300-battle batch matched version 23 battle for battle).
- **Rules version 27** (entry hazards, §9.11): one-on-one battles play exactly as before (the 300-battle batch matched version 23 battle for battle; standard movesets never pick hazards). Paired probe over 150 random 3v3 battles each, side A's lead carrying the hazard in place of its last standard move against the same battles with its standard set: with Spikes side A wins 54.7% of decided battles (54.4% without), laying 2.6 layers a battle; with Stealth Rock 51.0% (54.4%), laid once a battle. A hazard is worth about the attack or utility move it replaces.
- **Rules version 26** (the utility AI switching, §11): one-on-one unchanged (no bench, so no switch is ever weighed or rolled). Paired probe over 800 random 3v3 battles (seeds 21 and 22, each played with switching on side A and on side B against the same profile without it): the switching side wins 50.8% of decided battles (52.0%, 53.8%, 47.5%, 49.7%), switching 1.8 times a battle; median 157–168 s at one-on-one HP. Switching adds a visible tactic without being a dominant one.
- **Rules version 25** (switching, §9.1): one-on-one battles play exactly as before (the 300-battle batch matched version 23 battle for battle).
- **Rules version 24** (teams, §9.1; 300 battles, seed 5, against a version 23 batch of the same seed): one-on-one battles play exactly as before, every battle's summary matching. Team battles keep the one-on-one HP until the pace tuning (§17): a 3v3 of standard sets ran 134 s.
- **Rules version 23** (spacing by style, §11; 1,000 battles, seed 1, against a version 22 batch run the same day): median 41.8 s (42.2 s), 10th–90th percentile 21.2–80.6 s (21.1–79.3 s), draws 4.3% (5.3%), side A 47.8% (47.6%), hits 52.3 a battle (52.6), misses 12.2 (11.5); projectiles 40.4% of move uses (39.2%), melee 38.1% (38.6%). Paired probes over the matchups the change touches (1,600 random battles over two seeds, each played both ways round, the same battles under both versions): where the side leaning ranged still carries a close move, it wins 54.0% of decided battles (52.3%), spends 44% of the time within 3 m (46%), and draws are 5.2% (4.2%); a kiter (lean under 0.35) against a brawler (over 0.65) wins 71.3% (71.5%) with draws 3.7% (3.5%), since the brawler's pressing makes up for the kiting. Without the overtime rule, the first version drew 6.3% of the batch and 6.1–7.0% of the first group. Working out the lean each decision costs about 7% more time per battle (measured on a busy machine, so roughly).
- **Rules version 22** (screens, §9.11; 1,000 battles, seed 1): median 42.2 s (42.0 s under version 21), 10th–90th percentile 21.1–79.3 s, draws 5.3% (5.3%), side A 47.6% (47.4%). Six standard movesets carry Aurora Veil (the Snow Warning species) and none Reflect or Light Screen. The paired probe over every arena-move carrier (weather, surge or screen in its standard moveset) puts the arena move at +6 points of win rate (32.5% against 26.3%, 400 battles).
- **Rules version 21** (surges, §9.11; 1,000 battles, seed 1): median 42.0 s (42.2 s under version 20), 10th–90th percentile 21.1–79.3 s, draws 5.3% (5.1%), side A 47.4% (47.4%). 15 standard movesets carry Grassy Terrain and none another surge move; the same paired probe puts Grassy Terrain at +1.6 points of win rate (32.1% against 30.5%, 400 battles). Surges mostly come from the surge abilities.
- **Rules version 20** (weather, §9.11; 1,000 battles, seed 1, against a version 19 batch run the same day on the same machine): median 42.2 s (42.0 s), 10th–90th percentile 21.0–78.1 s, draws 5.1% (5.1%), side A 47.4% (46.9%), hits 52.5 a battle (52.1). Few standard movesets carry a weather move (8 Rain Dance, 2 Snowscape, 1 Sandstorm), so weather comes up 0.1 times a battle, mostly from abilities. A paired probe (400 battles whose side A carries a weather move, each played again with it swapped for its best other attack) puts the move at +9 points of win rate (24.6% against 15.3%; the carriers are mostly weak Water types). Before the arena moves' 30 s cooldown and the halved chip, the same probe gave +23 points, with Sandstorm in 87 movesets and kept up all battle.
- **Rules version 19** (held items, §9.10; 1,000 battles, same seed as the version 18 batch). With the HP multiplier left at 22, items stretched battles to a median of 47.1 s with 6.4% draws: Eviolite, the standard item of 470 roster entries, makes unevolved species half again as bulky. The multiplier went to 19, which gives a median of 42.5 s (41.3 s under version 18), 10th–90th percentile 21.6–78.6 s, draws 4.5% (2.9%), side A 49.9%, hits 53.0 a battle. Hard against ranked: median 48.8 s, draws 7.3% (4.8%), hard wins 54.5%; its draws gather where Eviolite is (7–8% of battles in which either side holds one, 5% otherwise). Standard items: Eviolite 470, Expert Belt 208, Life Orb 124, Leftovers 92, Rocky Helmet 54, Sitrus Berry 29, Assault Vest 22, Black Sludge 2. A paired probe (400 random matchups, side A's item on and off) puts an item at about 10 points of win rate (42.0% to 51.9%), Eviolite and Leftovers most.
- **Rules version 18** (abilities, §9.9; movesets now weigh the standard ability, §9.6; 1,000 battles, same seed as the version 17 batch): median 41.3 s (41.2 s), 10th–90th percentile 20.7–74.7 s, draws 2.9% (2.5%), side A 48.5% (48.2%), hits 51.4 a battle (51.3); abilities announce themselves 0.9 times a battle (most act quietly on damage). Hard against ranked: hard wins 54.4% (55.3%). A paired probe (400 random matchups whose side A has an ability, each played with and without it, same seeds) puts an ability at about 2 points of win rate (48.1% to 50.1%); Overgrow, Flash Fire and Thick Fat moved most, while most matchups end the same either way.
- **Rules version 17** (guarding, §9.2; 1,000 battles, same seed as a version 16 batch): median 41.2 s (41.8 s under version 16), 10th–90th percentile 22.1–73.6 s, draws 2.5% (2.9%), side A 48.2% (49.3%), hits 51.3 a battle (51.4), dodges 8.4 (8.8). The ranked AI guards 0.6 times a battle, blocking 0.5 hits, 0.1 of them parries; its reaction delay leaves it too late for most melee strikes, so it mostly guards projectiles and area moves. Hard against ranked (1,000 battles): hard wins 55.3% of decided battles (53.9%), guarding 1.7 times a battle with 0.5 parries, and a fifth of its foe's feints now draw a guard. Guarding adds a visible answer without moving balance.
- **Rules version 16** (feints, §9.2; 1,000 battles, same seed as a version 15 batch): median 41.1 s (40.0 s under version 15), 10th–90th percentile 21.2–75.3 s, draws 2.4% (2.8%), side A 48.2% (50.3%), hits 50.8 a battle (50.3), dodges 8.5 (8.5). The ranked AI feints 0.54 times a battle. 20% of feints draw a dodge, and half of those dodges are punished by a hit. Openings are rare: the foe has to be down to its last dodge charge while a melee or area move is ready and in reach. Hard against ranked (1,000 battles): hard wins 58.6% of decided battles, against 58.3% under version 15, with 1.1 feints a battle. Feints add a tactic you can see without moving results.
- **Rules version 15** (arena presets): three new arenas join the seed's choice, so a seed can land in a different arena; fields play as before, and coliseums around terrain flatten at the wall. No new batch.
- **Rules version 14** (the continuous landscape and features; 1,000 battles): median 40.4 s, 10th–90th percentile 20.9–76.0 s, draws 3.0%, side A 48.8%.
- **Rules version 13** (a 14 m arena, more cover, the utility AI's terrain tactics; 1,000 battles): median 40.3 s, 10th–90th percentile 20.1–74.9 s, draws 3.0%, side A 48.0%.
- **Rules version 12** (terrain, §9.8; 1,000 battles): median 40.3 s, draws 2.6%, side A 48.6%. Over 100 battles across fields, 3% of shots were blocked and fighters spent 3% of the time on raised ground; terrain is mild until the AI uses cover on purpose.
- **Rules version 11** (an 11 m arena, fighters starting 10 m apart; 1,000 battles): median 39.7 s, 10th–90th percentile 20.7–72.9 s, draws 2.2%, side A 48.8%, melee 38% and projectiles 40% of move uses (unchanged). The average gap went from 3.5 m to 3.8 m.
- **Rules version 10** (agility and gliding, 1,000 battles): median 38.0 s, 10th–90th percentile 20.2–71.9 s, draws 1.8%, side A 48.8%.
- **Rules version 9** (facing, acceleration, knockback, and the utility AI's wider, varied spacing; 1,000 battles): median 37.8 s, 10th–90th percentile 20.1–70.9 s, draws 2.2%, side A 50.4%, misses up from 5.7 to 10 per battle. The average gap between fighters went from 1.6 m to 3.4 m, and the share of time more than 3 m apart from 13% to 51%.
- **Rules version 8** (self-lowering moves discounted in movesets, the AI's veto fixed, Showdown's stat overrides, 1,000 battles): median 30.2 s, 10th–90th percentile 16.8–57.9 s, draws 0.5%, type-advantaged side wins 56.1%.
- **Stat overrides:** damage reads Showdown's `overrideOffensivePokemon`, `overrideOffensiveStat` and `overrideDefensiveStat`, so Foul Play uses the target's Attack, Body Press attacks with Defense, and Psyshock and Psystrike hit Defense. Foul Play had used the user's own Attack, which helped Kingambit to a 94% win rate.

### 9.8 Terrain

Since rules version 12 the arena has ground the battle uses (`game/sim/terrain.gd`). The battle is still played on the floor plane, with a height for every 1 m cell on top:

- **Generation** (since rules version 14): one continuous landscape from the battle seed for the arena's field, a height per 1 m cell in 0.5 m steps. Inside the arena, noise mounds (half the ground stays low, the rest rises up to about 2 m by field) whose contours become terraces: walkable where neighbouring cells differ by a step, cliffs where they differ more. Beyond the wall the land eases into hills over 14 m (into the sea at the beach), so the battle area is part of the world, not a disc cut out of it. In a coliseum (an enclosed field, rules version 15) the mounds ease down to flat ground over the last 3 m inside the wall instead, and nothing rises beyond it.
- **Features** stand on the ground, by field: rock clusters (a 2–3 m centre with lower stones around it), trees, pines and palms (trunks block), fallen logs (low enough to step onto), basalt column clusters, stalagmites, ice spikes and crystals; 5–17 per arena, at least 2.5 m apart.
- **Fairness:** each starting spot is level and open for 2.5 m, blending back into the land over 2 m, and the two starts are always connected by walkable ground (checked both ways; otherwise the land and features are toned down and regenerated, falling back to flat ground). The stadium is flat.
- **Cost:** the battle only generates the arena and a 5 m margin; the presentation extends the same noise to the rest of the world. Creating a battle takes about 25 ms.
- **Arena:** the arena preset (§12.7) is chosen in the simulation (the spec's `"arena"`, else the seed from the presets that suit the fighters' types), since its field and venue decide the terrain.
- **Moving:** a fighter stands at the height of the cell under its centre and can step up 0.5 m (fliers 1.5 m); stepping down is free. Higher ground is a wall it slides along.
- **Projectiles** leave from and aim at chest height (0.8 m above the ground), rising or falling to reach the foe, and stop where the ground rises above them. They hit within 1 m of the target's chest height.
- **Melee and area moves** only reach across height differences of 1 m and 1.5 m.
- **AI:** both AIs only use a move that can connect (a clear line for projectiles and status moves, a small enough height difference otherwise), and steer around ground they can't climb. The utility AI also has two terrain tactics where the ground rises at least 1 m somewhere: with no attack ready while the foe can see it and has a ranged attack coming, it heads for the nearest spot out of sight; with a ranged move ready and in range but no clear line, it heads for the nearest spot with one (spots are tried 16 ways at 1.5 and 3 m). They're chosen about 3–4% of the time in caves; their main effect is not getting stuck without a line of sight.
- **Effect** (rules version 14, 60 battles per field): 6% (beach) to 14% (cave) of shots hit rock, the fighters are out of each other's sight 10–26% of the time and on raised ground 14–20% of it.
- **See-through:** in the view, anything between the camera and a fighter (above that fighter's ground) dissolves with a screen-door dither, so cover never hides the battle.
- **Cost:** each cell keeps the highest ground within 3 cells, so collision and sight checks stop early where nothing rises; battles take about 20% longer to simulate.

### 9.9 Abilities

Since rules version 18 (M9). Showdown implements abilities in code, so its data gives only each species' list of abilities (1–3, 264 across the roster). The effects are our own table, `game/data/abilities.json`, keyed by Showdown's ability IDs: each entry lists its effects as keys that `Abilities` (`game/sim/abilities.gd`) reads, and only effects with a clear real-time reading are in it.

- **Which ability:** each species gets a **standard ability** by one policy, like its standard moveset: the highest-valued ability on its list that the table implements, ties broken by ID. A species with none implemented has no ability. A battle spec can name another with `"ability"` (`""` for none).
  - For 1.8.4 and Showdown 0.11.11, 781 of the 1,005 roster entries get an ability; the rest have only abilities about weather, switching, accuracy and the like.
- **Open sheets:** both fighters' abilities are known from the start, to the AI as to the player.
- **Real-time readings:**
  - A main-series immunity from an ability plays like a type immunity (§9.4): the move hits at ×0.25, with no secondary effects. An absorb also restores 1/16 of max HP or raises a stat.
  - Effects per turn run at a fifth of their amount per second, as burn does (§9.5).
  - Effects per hit that take or restore a share of max HP are scaled down, since a fighter takes about six times as many hits as in the main series: Rough Skin and Iron Barbs take 1/50 of the attacker's max HP rather than 1/8.
  - Effects that last "until switched out" last 12 s, like a status condition.
- **First set** (78):
  - **Immunities and absorbs:** Levitate (Ground), Flash Fire (Fire, then its own Fire moves ×1.5 for 12 s), Water Absorb and Volt Absorb (heal), Dry Skin (Water heals, Fire ×1.25 taken), Earth Eater (Ground heals), Sap Sipper (Grass, +1 Attack), Lightning Rod and Storm Drain (Electric and Water, +1 Sp. Atk), Motor Drive (Electric, +1 Speed), Well-Baked Body (Fire, +2 Defense), Bulletproof (ball and bomb moves), Soundproof (sound moves).
  - **Damage dealt:** Blaze, Torrent, Overgrow and Swarm (×1.5 to their type at 1/3 HP or less), Huge Power and Pure Power (Attack ×2), Adaptability (STAB ×2), Technician (moves of 60 power or less ×1.5), Iron Fist, Strong Jaw, Mega Launcher, Sharpness and Tough Claws (punch, bite, pulse, slicing and contact moves), Reckless (recoil moves ×1.2), Sheer Force (moves with secondary effects ×1.3, without them), Guts (Attack ×1.5 with a status, no burn halving), Hustle (Attack ×1.5, physical projectiles 20% slower), Tinted Lens (resisted hits count as neutral).
  - **Damage taken:** Thick Fat (Fire and Ice ×0.5), Heatproof (Fire ×0.5), Filter, Solid Rock and Prism Armor (super-effective ×0.75), Multiscale and Shadow Shield (×0.5 at full HP), Fur Coat (Defense ×2), Marvel Scale (Defense ×1.5 with a status).
  - **Contact punishers**, on a melee hit taken: Static, Flame Body, Poison Point and Effect Spore (a 30% chance of a status), Rough Skin and Iron Barbs (the attacker loses a share of its max HP).
  - **Status:** Limber, Insomnia, Vital Spirit, Immunity, Water Veil, Magma Armor, Own Tempo and Oblivious (immune to one condition), Early Bird (sleep half as long), Shed Skin (a chance each second to shake off a status), Poison Heal (poison heals instead), Quick Feet (Speed ×1.5 with a status), Synchronize (passes a status back).
  - **Stat changes:** Intimidate (−1 Attack to the foe at the start, and every 12 s), Clear Body, White Smoke, Full Metal Body, Hyper Cutter and Big Pecks (the foe can't lower its stats, or one stat), Defiant and Competitive (+2 Attack or Sp. Atk when the foe lowers a stat), Justified (+1 Attack when hit by a Dark move), Weak Armor (−1 Defense, +2 Speed when hit by a physical move, at most every 3 s), Speed Boost (+1 Speed every 10 s, up to +2), Inner Focus (immune to Intimidate).
  - **Other:** Sturdy (the first knockout blow leaves 1 HP), Rock Head (no recoil), Magic Guard (no damage except from hits), Serene Grace (secondary chances ×2), Skill Link (2–5-hit moves always hit 5 times), Shield Dust (no secondary effects taken), Prankster (status moves wind up like priority moves).
- **Doubles** (M17, rules version 33): Intimidate lowers both foes up (each can be immune); Lightning Rod and Storm Drain draw a foe's single-target Electric or Water projectile aimed at the holder's ally to the holder (which then absorbs it); two abilities that only act on an ally join the table, never as a standard ability (so singles keeps every standard ability): **Friend Guard** (hits on the ally ×0.75) and **Telepathy** (the ally's spread moves pass it by). The utility AI weighs a drawn move against the foe that would take it, and leaves a Telepathy ally out of a spread move's cost.
- **Left out:** (weather and surge abilities are in §9.11), abilities about switching, items, accuracy or flinching, allies' abilities beyond doubles' first four (above), and ones that would need new systems (Disguise, Imposter, Wonder Guard).
- **Details:** Flash Fire's boost and Intimidate's repeat both run 12 s; Speed Boost raises Speed every 10 s while it's below +2, and the stage wears off like any other; Shed Skin has an 8% chance each second; Poison Heal restores 1/40 of max HP a second; Weak Armor triggers at most every 3 s; Prankster's status moves wind up like priority moves, but heals stay a channel. Fixed-damage moves ignore abilities.
- **Battle spec:** a fighter's `"ability"` names an ability from the table, or `""` for none; without it the fighter gets its standard ability. A name outside the table is an error.
- **AI:** expected damage includes both fighters' abilities (`Battle.damage_parts`, shared with the battle). Neither AI attacks into an absorb, throws a status move at a fighter immune to it or a stat drop at one that blocks it; the utility AI discounts melee moves against a contact punisher.
- **Presentation:** an ability that takes effect shows its name over the fighter (`ability` events), and a contact punisher's damage shows like recoil.

### 9.10 Held items

Since rules version 19 (M9). Like abilities, item effects are our own table, `game/data/items.json`, keyed by Showdown's item IDs and read only by `Items` (`game/sim/items.gd`).

- **Which item:** each species gets a **standard item** by one policy on its base stats, types and standard moveset, the first that fits of: Eviolite if it can still evolve; Assault Vest if HP, Defense and Sp. Def add up to 280 or more and its moveset has no status-category move; Life Orb if its better attacking stat is 110 or more and that bulk is under 260; Rocky Helmet if its Defense is 110 or more and 20 above its Sp. Def; Expert Belt if it attacks with three types or more; Sitrus Berry if its HP is 100 or more; Black Sludge for a Poison type; Leftovers otherwise. Shell Bell, Muscle Band, Wise Glasses, the type boosters, Focus Sash and Lum Berry are never standard; a battle spec can give them. A battle spec can name any item with `"item"` (`""` for none), and an item outside the table is an error. Items are known to both sides, like abilities.
- **First set** (31, 18 of them type boosters), with the readings of §9.9:
  - Leftovers and Black Sludge (restore a share of max HP each second; Black Sludge hurts non-Poison types), Shell Bell (restores a share of damage dealt);
  - Life Orb (damage ×1.3, a small share of max HP lost per hit), Expert Belt (super-effective ×1.2), Muscle Band and Wise Glasses (physical or special ×1.1), type boosters such as Charcoal (×1.2 to one type);
  - Assault Vest (Sp. Def ×1.5, status-category moves can't be used), Eviolite (Defense and Sp. Def ×1.5 for a species that can evolve), Rocky Helmet (a melee attacker loses a share of its max HP);
  - Focus Sash (from full HP, the first knockout blow leaves 1 HP), Sitrus Berry (restores 1/4 of max HP once, at half HP or less), Lum Berry (cures the first status condition or confusion).
- **Left out:** Choice items (locking into one move has no clear real-time reading), Mega Stones and Z-Crystals, and items about switching or accuracy. Weather items are in §9.11.
- **Amounts:** Leftovers and Black Sludge move 1/80 of max HP a second (Black Sludge hurts a holder that isn't Poison); Shell Bell restores 1/8 of damage dealt; Life Orb costs 1/170 of max HP a hit (a probe found 1/60 and 1/100 left its holders no better off than without it) and Rocky Helmet takes 1/33 from a melee attacker (Magic Guard ignores both); type boosters are ×1.2. Focus Sash, Sitrus Berry and Lum Berry are used once.
- **AI:** expected damage includes items (`Battle.damage_parts`), an Assault Vest's status moves never count as ready, and the utility AI discounts melee moves against a Rocky Helmet as against a contact-punishing ability.
- **Presentation:** an item that takes effect or is used up shows its name over the fighter (`item` events); Life Orb's and Rocky Helmet's damage shows like recoil; the steady healing of Leftovers is a quiet `regen` event, seen only on the HP bar.

### 9.11 Arena moves

Arena moves set a condition on the whole arena or on one side for a while instead of hitting a fighter (`game/sim/arena_conditions.gd`). Three families, one pull request and rules version each: **weather** (rules version 20), **surges** (21) and **screens** (22), all done in M10. Entry hazards (Stealth Rock, Spikes, Toxic Spikes, Sticky Web) came with team battles (M15, rules version 27, below): they punish switching in.

- **Playing one:** an arena move is a status-category move applied on release, like a self-buff: the same 0.4 s wind-up and recovery, and it can't be feinted. It needs no range or line of sight. Its cooldown is 30 s, longer than its condition lasts: casting costs under a second, so with a status move's cooldown a weather stayed up all battle, and a paired probe put carrying one at +23 points of win rate.
- **Durations:** a turn reads as about 5 s, as for per-turn effects (§9.9), so the main series' five turns become 20 s for weather and surges, and its eight with an extending item (Damp Rock, Heat Rock, Smooth Rock, Icy Rock, Terrain Extender) 32 s. Screens are shorter (below). Using a weather or surge move while the same one is up renews it.
- **One at a time:** one weather and one surge at once, battle-wide; a new one replaces the old. Screens are per side.
- **Readings** follow §9.9, except that per-turn damage and healing is a tenth of the amount per second (1/160 of max HP for the main series' 1/16), half Leftovers' rate, since it comes on top of a held item. Multipliers keep their main-series values.
- **Standard movesets** weigh arena moves in the utility slot (§9.6) by fit: a weather or surge by how much it helps the species' own types, attacking stat and standard ability, and a screen by the share of a typical foe's hits it softens over a battle at its uptime (so a single screen rarely makes the cut; Aurora Veil does for species that bring their own snow). The utility threshold decides, as for buffs and heals.
- **Standard abilities** that only work in a weather or surge are valued low, so a species keeps an ability that always works when it has one; setters are valued high.
- **AI:** expected damage includes the weather, surge and screens (`Battle.damage_parts`), so both AIs aim with them. The utility AI values an arena move by the difference it makes: its own expected damage gained against the foe's, chip damage, and its ability's triggers, so it sets a weather that helps it, replaces one that helps the foe, and never renews a condition with more than a third of its time left. Screens are raised against a foe whose attacks are mostly of that category. The stand-in AI uses the same value with its own threshold.
- **Presentation:** each condition shows on the field and in the HUD in both clip formats: a pill at the top centre with the condition's name and a draining timer, a callout when one starts ("It started to rain!"), and the field's look changing (below). A condition that ends fades out.
- **Determinism:** conditions and their timers are part of the hashed state (§10). The battle spec can name a starting weather (below); saved specs keep it.

**Weather** (rules version 20):

| Weather | Moves | Effects |
|---|---|---|
| Rain | Rain Dance | Water moves ×1.5, Fire moves ×0.5; Thunder and Hurricane fly at full accuracy's speed |
| Sun | Sunny Day | Fire moves ×1.5, Water moves ×0.5; Solar Beam and Solar Blade skip their charge; nobody freezes |
| Sandstorm | Sandstorm | 1/160 of max HP a second to fighters that aren't Rock, Ground or Steel; Rock types' Sp. Def ×1.5 |
| Snow | Snowscape, Chilly Reception | Ice types' Defense ×1.5; Blizzard flies at full accuracy's speed |

- Morning Sun, Synthesis and Moonlight heal more in sun (2/3 of the main-series amount before the heal factor) and less in other weather (1/4).
- **Abilities:** Drizzle, Drought, Sand Stream and Snow Warning set their weather when the battle starts, for the usual 20 s (32 s with the matching rock); if both fighters have one, the slower one's weather wins, as in the main series. Swift Swim, Chlorophyll, Sand Rush and Slush Rush double Speed in their weather. Rain Dish and Ice Body heal 1/160 of max HP a second in rain and snow; Dry Skin heals that in rain and loses it in sun; Solar Power raises Sp. Atk ×1.5 in sun and loses 1/160 a second; Sand Force powers Rock, Ground and Steel moves ×1.3 in sand. Sand Force, Overcoat and the sand types take no sandstorm damage. Hydration ends a status condition at the next second in rain; Leaf Guard blocks major status in sun.
- **Items:** Damp Rock, Heat Rock, Smooth Rock and Icy Rock lengthen their weather from moves and abilities. Utility Umbrella keeps rain and sun off its holder (its own moves and hits taken). A species whose standard ability or moveset sets a weather gets the matching rock as its standard item, after Eviolite.
- **Arena presets** may name a starting weather (`"weather": "rain"`), and a battle spec can too (`"weather"`, `""` for none), overriding the preset's. A starting weather lasts the whole battle unless another replaces it. None of the presets the seed picks from has one, so type-suited arenas never hand those species a free boost; it's for staging a battle on request.
- **Look:** rain falls in streaks under a darker, cooler sky with denser fog; sun brightens and warms the sun light and the sky; a sandstorm blows sand across a tan haze, its dust lifting the ambient light rather than dimming it much, so the fighters stay readable; snow falls under a pale sky. Field particles reuse the presets' sand and snow, and a preset's own particles give way while a weather is up. A weather thickens the fog to at most 0.024 (about 17% at 8 m), since fog covers the fighters too, and leaves an arena's own thicker fog (the cave's) as it is: a sandstorm used to multiply the cave's fog fourfold and turn the fighters into murky shapes.

**Surges** (rules version 21): Electric, Grassy, Misty and Psychic Terrain (the moves keep Showdown's names) cover the ground and affect **grounded** fighters only: not Flying types or Levitate.

| Surge | Effects on grounded fighters |
|---|---|
| Electric | Electric moves ×1.3; can't fall asleep |
| Grassy | Grass moves ×1.3; heal 1/160 of max HP a second; Earthquake, Bulldoze and Magnitude deal ×0.5 to them |
| Misty | can't get a major status or confusion; Dragon moves deal ×0.5 to them |
| Psychic | Psychic moves ×1.3; priority moves aimed at them lose their quick wind-up |

- **Abilities:** Electric Surge, Grassy Surge, Misty Surge and Psychic Surge set theirs when the battle starts; Surge Surfer doubles Speed in an electric surge; Grass Pelt raises Defense ×1.5 in a grassy one.
- **Items:** Terrain Extender lengthens them. A species whose standard ability or moveset sets a surge holds one as its standard item (after Eviolite and the weather rocks).
- **Starting:** if both fighters set a weather or surge at the start, the slower one's goes last, as for weather. A surge and a weather can be up together; one surge at a time.
- **Look** (`ArenaSurge`): the field inside the wall takes a light tint of the surge's colour, a stepped glowing band along its edge, and a pattern of its own in eighth-metre pixels (the arena's surface shader), each chosen to read from the battle's low cameras: pulses running along a 1.5 m grid of lines (electric), grass in two darker greens in broad mown stripes (grassy), drifting cloud patches with dithered edges (misty) and rings rippling out from the centre (psychic). Particles drift low over the ground: bright sparks, leaves, pink motes kept under 0.8 m, or a violet shimmer. `tools/preview_surges.gd` renders each surge in both formats. The first look (a colour wash with random flickering cells, and large flat mist squares) read as a grading glitch from low angles, and misty and psychic looked alike. The HUD shows a second pill under the weather's, and callouts announce it starting and ending.

**Screens** (rules version 22): Reflect and Light Screen halve physical and special damage to the user's side; Aurora Veil halves both and can only be used in snow. A screen lasts 8 s (13 s with Light Clay), and the move's cooldown is 14 s, so a screen is up at most a little over half the time. Brick Break, Psychic Fangs and Raging Bull shatter the foe's screens before they hit. Infiltrator's attacks ignore screens. Critical hits ignore them, as in the main series. The look (`ScreenPanes`) is a translucent pane with a pixel-art border in the screen's colour (pink Reflect, gold Light Screen, cyan Aurora Veil) between the fighter and its foe, and a timed badge in the effect row of the side's name plate (§12.5); a shattered screen gets a callout. A species carrying a screen holds Light Clay as its standard item.

**Entry hazards** (team battles, rules version 27): Stealth Rock, Spikes, Toxic Spikes and Sticky Web lay a hazard on the foe's side, which acts on each of its send-outs (a switch or the one after a knockout) until it's cleared.

| Hazard | Layers | On send-out |
|---|---|---|
| Stealth Rock | 1 | 1/8 of max HP times Rock's compressed effectiveness (§9.4), so 10–20% |
| Spikes | 3 | 1/8, 1/6, 1/4 of max HP by layers; grounded only |
| Toxic Spikes | 2 | poison (two layers: bad poison); grounded only; a grounded Poison type absorbs them |
| Sticky Web | 1 | −1 Speed; grounded only |

- Laying one is an arena move like the others (0.4 s wind-up, no range), with a 12 s cooldown between layers; a layer past the most fails. Magic Guard takes no hazard damage. Rapid Spin and Mortal Spin clear the user's side when they hit; Defog clears both sides and the foe's screens, and Tidy Up both sides (with +1 Attack and Speed). Defog and Tidy Up became playable for this.
- **Standard movesets never pick them**, nor Defog or Tidy Up, so one-on-one movesets, battles and rankings are unchanged; specs, `--moves` and the setup screen give them.
- **AI:** both AIs value a layer by what it takes from each send-out still to come on the foe's side (its healthy bench, plus half a switch): 1/8 of HP for Stealth Rock, the next Spikes layer's step, poison 8% (bad poison 4% more), a Speed drop 4%. Clearing is worth the hazards on its own side less those on the foe's. Nothing to send out, or the most layers already, is worth nothing.
- **Presentation:** a badge per hazard in the effect row of its side's plate (ROCK, SPK×2, TSPK, WEB, with icons drawn in-house, no timer since they last), low-poly pieces around that side's start spot (pointed stones hovering and turning, grey and purple spikes, more each layer, a pale web lying flat), and callouts when one is laid, cleared, absorbed or bites.
- **Determinism:** each side's layers are part of the hashed state in team battles.

**Ally moves** (doubles, M17, rules version 32): moves that help the ally rather than hit a foe. Standard movesets never pick them (like hazards), so singles and the ranking are unchanged; specs, `--moves` and the setup screen give them. Without an ally up they fail ("But it failed!").

| Move | Effect |
|---|---|
| Helping Hand | The ally's next damaging move, if it starts within 4 s, deals ×1.5 (every hit of it) |
| Coaching, Aromatic Mist, Howl | The ally's stat stages (+1 Attack and Defense, +1 Sp. Def, +1 Attack); Howl raises the user's too |
| Dragon Cheer | The ally's critical-hit chance is 1 in 8 for 12 s |
| Life Dew, Jungle Healing, Lunar Blessing | A heal channel (§9.5) healing the user and the ally a quarter of max HP times the heal factor; the last two also cure a status condition |
| Follow Me, Rage Powder | For 4 s every foe's attacks go for the user, whatever it's locked onto (Grass types and Overcoat ignore Rage Powder); 12 s cooldown; it ends early if the user faints or is recalled |
| Wide Guard | For 1 s spread moves (area moves, spread status moves) don't touch the user's side; 12 s cooldown |

- **AI:** the utility AI values each by what it gains: Helping Hand at half what the ally's best ready move would take from its target (only while the ally is ready and not already helped), ally boosts and Dragon Cheer as a buff while the ally can use one, Follow Me while its ally is below half HP and it is above, Wide Guard while it sees a foe winding up a spread move that reaches its side, team heals by the HP both have lost. The stand-in AI never uses them.
- **Presentation:** callouts ("Helping Hand!", "Pumped up!", "Center of attention!", "Wide Guard!", "Protected!") with a glow on the fighter helped and the guard's look on both of a Wide Guard's side.
- **Determinism:** the timers and the side's pull and Wide Guard are hashed in doubles.

- **Left out:** Tailwind, Safeguard, Mist, Trick Room, Magic Room, Wonder Room, Gravity, Quick Guard, Wide Guard and Fairy Lock (special cases, §9.3); Weather Ball, Terrain Pulse, Rising Voltage, Expanding Force, Grassy Glide and Steel Roller's surge readings; the seeds, Protosynthesis, Quark Drive and other abilities of species missing from the roster; Sand Veil and Snow Cloak (accuracy).

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
- **Animation never affects gameplay.** Hit timing comes from move data. Every species plays correctly whatever animations it has, and headless runs never load models.

**Battle spec** (input):
- rules version and data versions (manifest hashes): `"rules_version"`, and `"data_versions"` with the SHA-256 that `sources.json` pins for each source. Saved specs always have them; a hand-written spec may leave them out and then plays under any;
- each side's team: one entry per side, which is the fighter itself (a roster entry with its moveset, ability and held item, §9.9, §9.10) or holds `"team": [members like that]`, 1–6 of them, with the side's `"ai"` and, for a player's side, `"intents"`;
- `"doubles": true` for two out a side (§9.1); a side's second fighter then runs on its `"ai"` (or `"ally_ai"` when the first is the player's) and a saved player battle records its `"ally_intents"`;
- the AI profile for each side (`"ai"` per fighter; default `ranked`);
- the seed;
- how each fighter looks: `"shiny"` and `"form"` per fighter (§12.8). The simulation never reads them, so they change neither the battle nor its checksum.

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
- A spec that names another rules or data version stops with an error before it plays.

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
  - feint move N;
  - dodge;
  - guard;
  - hold.
- **Considerations:**
  - Each consideration maps one input to a score from 0 to 1 through a `Curve` resource. Examples: target within this move's range, expected damage as a share of the target's HP, type effectiveness, own HP, time until an incoming hit, move ready, dodge charges left.
  - Hard vetoes, such as a move on cooldown, score 0.
- **Combining scores:**
  - An action's score is the product of its considerations, with a compensation factor so actions with more considerations aren't unfairly penalised.
  - The current action gets a commitment bonus, plus a minimum hold time, so the AI doesn't flip between choices every tick.
- **Choosing:** the highest score wins. Exact ties are broken by the side's AI random stream, never by list order.
- **AI profiles** are resources. Each sets reaction delay, aim error, decision interval, mistake chance, dodge chance, feint chance and guard chance.
- **Rankings** use one fixed "ranked" profile on both sides.
- **Debugging:** an overlay shows each candidate's per-consideration scores. It's implemented in `game/presentation/ai_overlay.gd`: a panel per side listing the last decision's candidates, best first, each with a score bar and its considerations, and the chosen action highlighted. F3 toggles it in the window, and `--ai-debug` shows it from the start or records it (`tools/record.gd -- … --ai-debug`). It only reads scores the AI keeps when asked, so it never changes a battle.
- **Tests:**
  - unit tests per consideration;
  - scenario tests, such as "dodges a telegraphed projectile" and "doesn't use a melee move out of range".

**Implementation (M4)** in `game/ai/utility_ai.gd`. A battle spec names each fighter's AI (`"ai": "hard"`); the default is `ranked`, and `stand_in` selects the stand-in AI.

- **Profiles** (`game/ai/profiles/*.tres`):

  | Profile | Reaction delay | Decision interval | Mistake chance | Dodge chance | Feint chance | Guard chance | Switch chance |
  |---|---|---|---|---|---|---|---|
  | easy | 12 ticks (0.4 s) | 6 | 25% | 30% | 0% | 0% | 10% |
  | normal | 8 | 4 | 10% | 50% | 0% | 30% | 30% |
  | hard | 4 | 2 | 2% | 80% | 40% | 90% | 70% |
  | ranked | 6 | 3 | 5% | 60% | 25% | 60% | 50% |

  The dodge chance is rolled once per threat, the guard chance once per threat it may react to, the feint chance once per opening, and the switch chance once per chance to switch.
- **Perception:** the AI sees the opponent's position and wind-ups one reaction delay late, and notices a projectile only once it has flown that long. After noticing an attack, it judges the time left correctly.
- **Considerations:**
  - moves: in range (a veto), expected damage as a share of the foe's max HP (power, STAB, stats, stages and type at once), finishing potential, and whether it's safe to commit while an attack it could dodge is incoming; non-damaging moves use the stand-in AI's situational value;
  - dodges: urgency, charges left and danger;
  - movement: distance outside the band its style and ready moves want (spacing by style, below);
  - feints (rules version 16): an opening comes when the foe is down to its last dodge charge and a melee or area move is ready and in reach. The AI rolls its feint chance once for the opening, as soon as a move could be feinted (since rules version 23, before it's in reach, so a kiter knows to close in for it). If the roll succeeds, the feint outscores every attack (it is still weighed against an incoming attack, like committing to a move), and once the foe has dodged, the AI's usual scoring picks the real strike against a foe with no dodge left. The feinted move is never spent, so it can be that strike. The stand-in AI never feints.
  - guards (rules version 17): a guard is a candidate against a threat the AI may react to (its dodge roll succeeded) when its guard roll for that threat also succeeded, the guard is ready, and the hit would land inside the guard's active window from the front. It scores by timing (best a few ticks before the hit), danger, the reward (a parry against a melee wind-up is worth more) and how few dodge charges are left, so it is weighed against dodging. The AI won't commit a move into a foe it sees guarding. The feint opening widens to a foe on its last dodge charge, or with no dodge charge but a guard ready. The stand-in AI never guards.

  Scores are products with the compensation factor. Movement scores sit below any usable attack's. The commitment bonus and minimum hold time apply only between ways of moving.
- **Switching** (team battles, M15, rules version 26): a switch to a bench member is another candidate. A fighter's **trade** against the foe is the log of how much faster it wears the foe down than the foe wears it down: its expected damage a second (each damaging move at the rate its wind-up, recovery and cooldown allow) as a share of the foe's HP, over the foe's against it plus its own status damage as a share of its HP, so stat stages, HP lost and status all count. A bench member's trade is worked out with the HP it would lose while landing taken off. Once one beats the fighter out by 0.4 (about a 1.5 times better trade) and the switch is allowed, the AI rolls its profile's switch chance for that chance, once per pairing; if it succeeds the switch scores from 0.6 up with the gain (capped at 0.95), weighed against an incoming attack like committing to a move. After a knockout the AI sends out the member with the best trade against the foe. The stand-in AI never switches and sends out the next in order.
- **Spacing by style** (M14, rules version 23): the distance a fighter keeps comes from its whole moveset and stats, not only from which moves are ready.
  - **Melee lean**, from 0 to 1: its melee and area moves' share of the expected damage per second of all its damaging moves, ready or not, against this foe (a move's expected damage over its wind-up, recovery and cooldown). Expected damage covers its attacking stats, STAB, the foe's defences and type, and stat stages, so the lean is worked out each decision and shifts as boosts and drops come and go: a special attacker with one physical punch leans ranged, until Swords Dance. Self-destructing moves don't count; a fighter with no damaging move sits at 0.5.
  - **With a melee or area move ready**, a fighter leaning melee (0.5 or more), a **brawler**, keeps 1.8–2.8 m as before, just outside the foe's reach and inside dash range. A **kiter** (under 0.5) keeps its ranged or waiting band and goes in only on an **opening**: the foe (as seen) recovering, asleep, frozen or stunned, or out of dodges with its guard on cooldown, or its own feint roll succeeded, so it closes in to feint. It still uses a melee move if the foe comes into reach.
  - **Otherwise** the band is blended by lean: with projectiles ready, from 3.5–6 m (lean 0) to 2.5–4.5 m (lean 1); waiting on cooldowns, from 3–5 m to 2.2–3.5 m, so brawlers press in. Each strafe still shifts the band by up to 0.5 m.
  - **Overtime:** from 60 s every fighter closes in for a ready melee move, so kiting doesn't run out the clock. A first version without it, and with kiters waiting at 4–6.5 m, raised draws from 5.3% to 6.3%; moving the waiting band back alone didn't help, since the draws came from kiters declining melee and trading dodgeable shots at range.
  - Every utility profile spaces this way: style is the species', and the profiles still differ in reactions, mistakes, dodges, feints and guards. The stand-in AI keeps its ready-move spacing. Guarding, terrain tactics and arena moves are unchanged.
- **Doubles** (M17, rules version 31): each fighter still decides on its own but sees its ally. On each decision it picks its target: a foe's appeal is the share of its HP left that the fighter's best move would take (up to all of it), less 0.03 a metre of gap, plus 0.15 if its ally is on that foe (focus fire) and 0.1 for the foe it's already locked onto, so the lock doesn't flicker. It watches every foe's wind-ups (each with its own reaction-delayed history), not just its target's, ignoring melee strikes and projectiles aimed at its ally. A spread move is worth the shares of max HP it would take from every foe in its ring (×0.75 when it hits several) less 1.5 times the share it would take from the ally, and is vetoed when that comes to nothing. Within 3 m of its ally it edges away while moving. The stand-in AI goes for the nearest foe. A paired probe (200 random 4v4s over seeds 51 and 52, each played with the doubles play on side A and on side B against the same AI playing each foe as if alone): the doubles side wins 60.5% of decided battles, both its fighters are on one foe 93% of the time (9% without), and it hits its ally 1.1 times a battle (1.2).
- **Not modelled:** aim error. The sim aims projectiles itself.
- **First results** (300 random matchups each, corrected for side order):
  - hard beats easy about 55% of the time;
  - the ranked utility AI is about level with the stand-in AI.

  AI skill moves results only a little, because species and movesets dominate. That suits rankings (§13).
- **Balance with ranked on both sides** (rules version 6): median 31.9–34.5 s, draws 3.8–4.0%.
- **Speed:** about 95–105 ms per battle, against about 57 with the stand-in AI.

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

**Smooth motion in the window** (`SmoothMotion`): the presentation steps 30 times a second, so a display refreshing faster would show some steps twice and none in some frames, which reads as jitter. Each display frame instead draws the fighters (their place, facing and procedural motion), the camera (with its field of view), projectiles and the particle effects riding them part of the way from the step before last to the last one. That draws them up to one step (33 ms) behind, in exchange for even motion; camera cuts and the cuts into and out of the instant replay jump instead. Animations already play in real time. Steps always see things where the steps left them, so the battle and the edit don't change, and recordings, which draw exactly one step per frame, don't use it at all.

Recording runs the battle headless first, which produces the full event log. So the presentation knows in advance where every big moment is, including the knockout, and can build up to it.

### 12.3 Camera director

The camera director picks from a set of shot types based on battle events:

| Shot | When |
|---|---|
| Wide establishing | At the opening, and as the default between moments |
| Over-the-shoulder | When one fighter is closing in on the other |
| Attacker close-up | Into the release of a strong move |
| Projectile tracking | While a projectile is in flight |
| Impact punch-in | On a heavy hit, critical hit or super-effective hit |
| Low angle | On big hits from large fighters |
| Knockout orbit | Around each knockout, in slow motion (in a team battle, for at most 1.5 s before one that isn't the last) |
| Instant replay | After the final knockout's linger and before the victory: that knockout again, from 24 ticks before it (or the finishing move's wind-up, if later) to 12 ticks after, at 2 frames per tick (at most about 2.5 s). A low over-the-shoulder shot from behind the attacker into the hit, then a punch-in on the loser through the faint. A white flash covers the cut in and out, a "REPLAY" tag with a blinking red dot sits top-left, and the name plates fade out (the victory card follows). Move sounds and the faint cry play again under a smaller cheer, and the music stays cut until the sting. The pictures come from a second copy of the battle, replayed from its spec and skipped ahead, so the battle itself, its checksum and the rules are untouched. |
| Victory | After the final knockout (2.5 s at normal speed): in front of the winner, a little to one side, slowly pushing in. The winner celebrates, the crowd cheers again, and the HUD's victory card slides in below: "WINNER", the name outlined in its side's colour, its HP left and the battle's length, while the name plates fade. Play mode keeps the plain "wins!" line, since a live battle has no planned ending. |

- **Cuts:** timed to events, and calm (`Director._calm`):
  - every shot holds at least a second (30 ticks). A shot asked for sooner waits until the current one has held that long, if enough of it is left by then, and is dropped otherwise; a more important shot (in the table's order, lowest first: wide, over-the-shoulder, tracking, close-up, punch-in) doesn't wait, and the short shot before it gives its time to the shot before that. The knockout and the victory always cut in on time. Battles open on a wide shot of at least a second;
  - an attacker's close-up covers the second before its strong move goes off, starting before the wind-up when that is shorter, and waits two seconds after the last close-up or punch-in; a punch-in lasts a second; projectiles get a tracking shot when they fly at least half a second;
  - wide and over-the-shoulder shots alternate every 5 to 9 seconds;
  - a new shot whose camera would sit near the current one (within 3 m for fighters of reference height, looking within 40° of the same way) eases over in 0.4 s instead of cutting, and tracking whips into its punch-in in 0.2 s.
- **Doubles** (M17): the line of action runs between the two sides' middles. Wide shots frame all four fighters (their middle, pulled back by the widest gap between any two), and the base over-the-shoulder shot looks from behind a side's pair across at the other. Close-ups, tracking shots, punch-ins, knockout orbits and the instant replay are on one fighter (the shot names its team slot) and look at it or from it to its target. If another fighter would stand between the camera and the shot's pair (a big ally such as Charizard filling the frame), the camera swings 30° or 60° around the target, or else rises, until the view is clear.
- **Repeatability:** shot choices draw from the cosmetic random stream, so re-rendering a battle produces the same edit.
- **Readability:** every shot keeps both fighters readable, and no shot lets one fighter hide the other.

### 12.4 Impact frames and hit feedback

- **Hit-stop:** a few frames long, scaled with damage.
- **Impact frames:** on critical and super-effective hits, one or two full-screen high-contrast frames (a flash or silhouette) at the moment of contact.
- **Screen shake:** scaled with damage, and capped so it never obscures the action.
- **Speed lines:** on dashes and big wind-ups.
- **Hit flash:** on the defender's model, with a short knockback.
- **Callouts:** "Critical hit!", "It's super effective!", damage numbers, stat changes, statuses, and ability and item names. Each one follows its fighter (over 0.9 of its height, every display frame), rising and fading over 40 frames. Callouts over one fighter stack, the newest at the bottom (those of one hit in the order made: damage, then critical, then effectiveness), pushing older ones up instead of overlapping them; a stack stays on screen and out of the HUD's bands. Move banners and captions stay in screen space on the HUD.

### 12.5 Move visuals, sound and HUD

- **Move visuals in Cobblemon's style:** one consistent pixel-art look for every move, drawn by default in battles and recordings. `--mesh-fx` draws the mesh styles below instead, and the game falls back to them, with a warning, when the native runtime or the cached effects are missing. The credits name Cobblemon's move effects only when they were drawn.
  - **Pieces, not scripts:** Cobblemon's particle effects (dust, sparks, shards, quake rings, beams) are reusable pieces. Each move has a `MoveSequence` script (`game/presentation/move_sequences/<move>.gd`) that plays pieces at our real-time phases: windup, fire, flight (riding the projectile), hit and blast. Cobblemon's 2–3 s turn-based scripts are only a reference for which pieces a move uses; a sequence's speed squeezes the pieces into our 0.25–0.45 s windups.
  - **Runtime:** a native GDExtension (`native/`, C++ on godot-cpp, built by `tools/native/build.sh`) compiles the effects' Molang to bytecode and runs their emitters: shapes, rates, motion, ground collision, flipbooks, tints, curves and sub-effect events, all seeded so renders match. Two overlapping moves cost about 1.3 ms in the worst frame. The game runs without it, drawing our own styles.
  - **Look:** nearest filtering like Cobblemon; camera-facing pieces are capped at a quarter of the view's height so close-ups don't fill with pixels; glowing (blend and additive) pieces bloom while cut-out ones (rocks, debris) stay flat; a piece borrowed from another type can be palette-swapped to the move's type colour.
  - **Our own sprites** (`tools/sprites/`): recipes draw pixel-art particle textures in Cobblemon's style into the build's `move_fx/` (opaque or clear pixels only, one to six flat colours, white and light grey for pieces effects tint, DawnBringer-32 colours otherwise; fixed seeds, so every build draws the same pixels).
    - They replace the 14 Minecraft textures Cobblemon ships in `textures/particle/vanilla/` (generic, critical_hit, small_explosion, smoke, bubbles, spiral, gust, flash, lava and others), keeping each one's size and flipbook layout, so effects index them unchanged. The Minecraft files are deleted from the build.
    - They also fill three textures effects name that the jar lacks (white wool, `particle/flash`, `charge_orb`). Four misspelled paths that clearly mean real Cobblemon textures (the thunder bolts and the fire impact) get copies of those.
    - `tools/preview_sprites.gd` draws them all on one sheet, and `tools/preview_moves.gd -- --pieces=<effect,...>` plays single effects for authoring sequences.
  - **Our styles in Cobblemon's look:** each of the 20 styles below, plus `status` for moves that deal no damage, has a style sequence (`StyleSequence`, `move_sequences/styles/<style>.gd`), which every move without a sequence of its own plays. So every move has a pixel-art look.
    - **Hits:** Cobblemon's own impact for the move's type (`impact_<type>`, in that type's colours; Normal's for any other type).
    - **Borrowed pieces:** pieces from moves that look the part, palette-swapped to the type colour. For example a bullet punch's fist for `punch`, bite fangs for `bite`, Aurora Beam's beam for `beam`, Thunderbolt's bolt for `bolt`, the flamethrower for `stream`, and Mystical Fire's shot plus a flaring glow riding the projectile for `orb`.
    - **Area moves** add a quake ring and sparks sweeping out from the user (plus bolts for `bolt`, a blast for `explosion`).
    - **Melee accents** are drawn 1.6× and nudged toward the camera, since our closer spacing and the foe's own body otherwise hide them.
    - **Palette swap:** it lifts dark pixels to a shade of the type colour, so dark pieces read as their type rather than black.
    - **Non-move cues:** stat rises and drops, heals and dodges use Cobblemon's `statup`, `statdown`, `heal_*` and dash-line pieces.
    - The mesh styles below stay as the fallback when the native runtime or the cached effects are missing.
  - **Moves with Cobblemon effects** get sequences of their own, which play Cobblemon's own pieces for that move and extend the move's style sequence, so a phase Cobblemon has no pieces for (often the projectile's flight) keeps the style's.
    - Cobblemon's timeline sets which phase each piece belongs to. User pieces before the move goes off are the windup (the whole sequence, kept running, for self-buffs). Pieces aimed at the foe are the fire, or the blast for area moves. Pieces on the foe are the hit, with Cobblemon's gaps between them squeezed by the sequence's speed and capped at 0.6 s.
    - Damaging hits without a Cobblemon impact piece add the type's impact, since many of Cobblemon's own hit sparks are a few centimetres across and vanish at our camera distance. Melee pieces on the foe are nudged toward the camera like the style accents.
    - Drains (Absorb, Mega Drain, Giga Drain) aim their pieces from the foe back to the user on the hit, so they skip the style's shot at the foe.
    - Where Cobblemon's timing or framing doesn't fit, a sequence is hand-tuned (Thunder's storm cloud gathers over the foe on release rather than a second before the bolt; Psychic's burst follows its grip quickly; String Shot drops a thread centred on the mouth that would trail behind the user; Draco Meteor's meteors fall straight onto the foe, the first two from the release, and three rather than four to stay within the frame budget).
    - Hidden Power keeps its style's sequence, since Cobblemon's effect for it is only the generic Normal impact.
    - Every move Cobblemon has an action effect for and our sim supports now has one, done by type batch: Fire, Water, Electric and Ice; Grass, Poison, Bug, Psychic and Fairy; Normal, Fighting, Flying, Dark, Ghost, Dragon, Ground, Rock and Steel.
  - **Pieces on a fighter follow it:** a wind-up's and a hit's pieces sit on the user's or foe's body (Swords Dance's swords, charge glows, hit sparks), as do stat cues, heals, guards and the shiny sparkle, so the fighter carries each of them, particles already out included, by as much as it has moved since the piece started (`CARRIED_PHASES`). Pieces on the ground (floor scorches, quake and ground rings, powder settling, dust: `GROUND_PIECES`), a dodge's dash lines, shots fired at the foe and blasts stay in the world, and projectiles' pieces ride their projectile. Our mesh styles' glows, auras, bursts, shields and glints are carried the same way.
  - Effects still in flight end with the battle, and nothing here touches the simulation.
- **Battlefield marks** (`BattleMarks`, `MarkTextures`): hits leave marks on the arena's ground, so an arena shows the fight by the knockout. Presentation only: the simulation, checksums and rules version are untouched.
  - **What marks:** every damaging hit, once per move use (a multi-hit move marks once), under the defender, sized by the share of HP taken (a radius of 0.45–1.3 m, 15% larger for critical and super-effective hits); an area move's blast around its user (cracks or a crater ring over 70% of its reach); a projectile stopped by the terrain, a small mark where it struck. The instant replay adds none.
  - **Kinds,** by style then type: area moves and ground styles (quake, erupt) crack the ground (Ground, Rock, Steel, Fighting, and those styles) or leave a crater ring; skyfall and explosion styles crater; otherwise scorch (Fire, Electric and the energy types: Dragon, Psychic, Fairy, Ghost, Dark), frost (Ice), splash stains (Water, Poison, Grass, Bug), cracks (ranged Ground, Rock, Steel, Fighting) and scuffs turned along the blow (Normal, Flying, and earthy melee).
  - **Look:** pixel art drawn in-house at load from fixed seeds (opaque or clear pixels, a few flat colours, three drawings a kind), at about the arena's 16 pixels per metre, with nearest filtering. Marks of earth (cracks, craters, scuffs, a scorch's edge) are shaded from the field's ground colour (the paving in a stadium), stains and frost take the type's colour. Fresh embers, sparks and an energy burn's rim glow and cool over 2 s in steps.
  - **Drawn by the ground:** marks are painted into a canvas over the field, 16 pixels a metre on the ground's own pixel grid, which the arena's surface shader draws on its upward faces over any surge's tint (`Arena.set_marks`); glowing pixels sit in a second canvas whose alpha holds the frame they were made on, so the shader cools them without repainting. So marks never land on fighters, effects or the crowd, and cost one texture read per pixel of ground however many there are. Projected decals were tried first and cost about 4 ms of GPU time a frame at the cap on the development machine's GPU (a Quadro P2000, 1080p); the canvas costs nothing measurable there, and about 0.2 ms of CPU a frame, 0.4 ms per new mark. Each battle draws its moves' marks at load (about 0.1 s).
  - **Debris:** area moves and ground, skyfall and explosion styles fling 8–13 low-poly chunks (the field's ground, a third in the type's colour: ice for Ice, cinders for Fire) that bounce once and lie half sunk where they land, from one pooled MultiMesh of 120 chunks (the oldest reused).
  - **Cap:** up to 40 marks; past that the oldest dissolves over a second in four steps (a fixed quarter of its pixels at a time, never semi-transparent), its debris shrinking with it. Nothing else ages them, and they stay across send-outs, since they belong to the ground.
  - **Repeatable:** each mark's drawing, turn and debris come from the battle seed (a stream of its own) and the event's tick and side, so a clip that starts mid-battle shows the marks made before its window, already settled, exactly as the whole battle would.
  - `tools/preview_marks.gd` renders one of each kind on any preset (`--worn` fills to the cap; `--weather`, `--surge`) in both formats.
- **Move visuals (our styles):** every damaging move has one of 20 visual styles, drawn in its type colour from simple meshes animated per video frame.
  - Melee: strike (crescent), punch (shockwave star), kick (low arc), bite (closing fangs), slash (claw marks), rush (speed lines and dust).
  - Ranged: orb, bullet, beam, bolt (lightning), stream (breath and spray), pulse, sound, wind, powder, skyfall (drops onto the target), erupt (spikes from the ground), quake (ground wave), mind (glow on the target), explosion.
  - **Choosing a style:** the committed table `game/data/move_styles.json` (274 moves Showdown's flags don't describe, such as beams, breath and meteors), then Showdown's flags (punch, bite, slicing, bullet, pulse, sound, wind, powder), then strike for contact moves and orb for the rest.
  - Flat effects face the camera, so no shot sees them edge-on. A ranged move that hits as it fires gets a short point-blank version of its style.
  - `tools/preview_moves.gd` renders every style under a fixed camera for review.
  - Rings and waves for area moves and glows for buffs come with those kinds.
- **Sound:**
  - Cobblemon cries, impact sounds and whooshes, synced to events.
  - **Music** (`BattleMusic`): original tracks only, never official, ripped or remixed Pokémon music. Each track is a score in `tools/music/scores/` (tempo, scale, chords, melodies and intro), in the style of fast handheld-era battle themes: driving 16th-note ostinatos, 3-3-2 brass stabs, call and response, timpani into the loop's return. The asset pipeline renders the scores with the GeneralUser GS SoundFont's General MIDI instruments (`tools/music/`, about 2 minutes a track, only when a score or the music scripts change) into layers: drums and lead in two variants each, bass, harmony, and a climax layer.
    - Three tracks: Clash (D minor, 184 BPM), Overdrive (E minor, 192 BPM, rock-leaning) and Summit (C minor, 176 BPM, brass-forward). The battle's seed picks the track and its drum and lead variants on a random stream of its own.
    - A track's intro plays once and the rest loops seamlessly: the loop is rendered twice and the second pass kept, so it starts with the end of the first still ringing, as every repeat does. Every track gets the same tone shaping and is matched to the same weighted loudness. Clips start it from the top, fading in.
    - Cues: overtime fades in the climax layer; a knockout cuts the music within 0.3 s, leaving the cry and the crowd for the slow-motion shot and the instant replay; the victory gets a short original sting (in play, as "wins!" shows), which fades over the credits; a time-up draw fades out.
    - In a team battle (M15) the music runs through the knockouts before the last, under their orbit and the crowd's roar; only the final knockout cuts it, and the replay, victory and sting follow it alone. Picking a track by occasion is left for later.
  - **Buses** (`default_bus_layout.tres`): Music, Crowd and Effects (cries and move sounds). The music ducks gently under the Effects bus through a side-chained compressor (a few dB, not out of the way), and the master adds 4 dB of make-up gain before its limiter. Fades move evenly in amplitude.
- **HUD:**
  - A name plate per fighter: dark and rounded, with a stripe in the side's colour (red for side A, blue for side B), the name, and a rounded pill per type, filled in its type colour.
  - **Effect row** (`PlateEffects`, `HudBadge`): under each HP bar, starting at the portrait's end, square dark badges edged in the effect's colour, each with an icon drawn in-house as pixel art, a short code and a timer draining along its bottom: the status condition (BRN, PAR, PSN, TOX, SLP, FRZ), confusion (CNF) and the side's screens (REFL, LSCR, VEIL). Then a badge per changed stat stage: the stat (ATK, DEF, SPA, SPD, SPE), an up or down arrow and the count, green for a rise and red for a drop, with no timer since stages wear off a step at a time (§9.5); it goes once the stage is back to 0. They're read from the battle every video frame, so a clip that starts mid-battle shows what's already on, part-drained. A timer's full length is the effect's standard one, or more when more is left (a rolled sleep, Light Clay's screens). The row shrinks to fit the bar's width; portrait's bottom plate sits higher to keep it clear of the credit line, and move banners sit under it.
  - A portrait on each plate's outer end, on a rounded tile in the side's colour (`FighterPortrait`): a second copy of the fighter's model in a world of its own, held in its idle pose's first frame and drawn once at load from a three-quarter angle, so no image is stored. It is framed as a head-and-shoulders bust, like a character select's: a square on the posed head (the head bone's cuboids and those of the bones under it), sized mostly by the head's height, since ears, crests and fins stretch heads sideways, and with the outlying tenth of its points at each end left out so whiskers and horns don't size it. The square starts a little above the skull and stays within the silhouette, so a low head (a grazing pose) never shows empty ground. Small round species, whose head is most of them (Jigglypuff, Ditto), and species without a head bone (Voltorb, Gengar, Magikarp) show the whole body. Species whose head carries a big mane (Rapidash's flames) count it as head and show the whole body too. The right-hand plate's portrait is mirrored to face the middle. Without a model the tile shows the name's initial. `tools/preview_portraits.gd` renders a grid of them for review, by default a spread of body shapes.
  - **Doubles** (M17): four plates, two stacked per side at 0.68 of the size (top-left and top-right in landscape; side B's pair at the top and side A's at the bottom in portrait, place 0 nearer the edge), each with its fighter's portrait, name, types, HP bar and effect row; move banners gather beyond the pair. The team balls show once per side, on the pair's inner plate, with both fighters out raised. The intro card names both of a side's fighters ("Garchomp & Charizard"), shrunk to fit, as do the coliseum's screens and the victory card (with the pair's HP left). In play, a ring in the player's colour marks the player's target.
  - **Team balls** (`TeamBalls`, team battles): at the inner end of the effect row under the HP bar, one pixel-art ball per member in team order, as in the games: red and white while healthy, tinted in its status's colour, dark grey once fainted, the one out raised; the effect badges keep the rest of the row. (At the end of the name's row they crowded out two-type pills.) A plate's name, types, portrait, shiny mark and effect row follow each send-out, and the intro card names the fighters out when a clip starts.
  - A rounded HP bar under the name with a light band along its top, its percentage (rounded up, so a fighter with HP left never shows 0%), and a lagging "damage taken" segment. Bars drain and shake on big hits; side B's mirrors in landscape so both drain toward the middle.
  - Move-name banners in the move's type colour, and callouts over the fighters.
  - **Fonts** (`UiFonts`, `game/presentation/fonts/`, SIL Open Font License with the licences beside them): Lilita One, a chunky display face, for names, titles, banners, callouts and the coliseum's screens; Nunito ExtraBold for everything else. The body font is set at startup, not as the project's custom font, because Godot loads that before a fresh checkout has imported the font files.
  - The intro card puts the two names, outlined in their sides' colours, either side of a gold "VS" (stacked in portrait), with the arena's name under them, plus "· Overtime" when a clip starts after overtime began. The winner's line sits on a dark band.
  - **Captions** (planned battles only): a lower-third band edged in a side's colour, sliding in for 1.5 s, on a few big beats. "COMEBACK!" on each fighter's first hit while at 30% HP or less (the rule Highlights scores comebacks by), never once the knockout's slow motion has begun, and "FINAL BLOW" on the finishing move's wind-up. None during the instant replay.
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
3. Choose the clip window from the event log: at most 60 seconds, usually ending shortly after the knockout. `Highlights` scores events (hits by damage share, plus crits, super-effective hits and comebacks; misses a little; the knockout or time-up a lot) and keeps the best-scoring window of the requested length. A window ends either a short linger after a hit, after an earlier knockout's slow-motion orbit (team battles), or at the end of the plan, and one that reaches the final knockout always plays the whole knockout and the victory after it. Windows are weighed across the whole battle, so a team battle's clip lands on its most exciting stretch, which may close on an earlier knockout. The instant replay and the victory come on top of the requested length, so they never push the knockout out of the window; a default 10-second clip that ends on a knockout runs about 17 seconds with them and the credits.
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

### 12.7 Arenas

An arena is a preset (`Arenas`): one JSON file in `game/data/arenas/`, named after the arena, so adding one is adding a file. A preset combines:

- a **field** (`Terrain.FIELDS`), the ground the battle is fought on, which is the simulation's (§9.8): grassland, beach, volcano, snowfield, cave, or flat paving. `ArenaFields` holds each field's colours, props and details;
- a **venue**: `open` (the field's own landscape all around) or `coliseum` (`Coliseum`, around any field), with an optional **theme** for the coliseum's colours (stone, paving, apron, seats, trim, outside ground, a banner colour per side, moss);
- its **look**: sky, sun, ambient light, fog and particles (colours as `"#rrggbb"`), with an optional exposure (1 by default; the cave is 0.75) and, for a coliseum, optional floodlights (`{"colour", "energy"}`);
- how a battle without a requested arena may get it: `"always"`, or `"suits"` with a list of types;
- for a coliseum, an optional `"crowd"`: `"fill"`, the share of seats taken (0 for empty stands, 1 for a sell-out; 0.75 by default), and `"watchers"`, how many watchers sit in the front row (0–8; 4 by default). The night stadium is half full, with two.

**Ambience** (`ArenaSound`, on the Crowd bus, from CC0 recordings in `sources.json`): a coliseum's crowd murmurs as loud as its stands are full, cheers that swell and fade with the crowd's excitement, and roars at a knockout and the victory; it dips under the victory sting and fades out with the credits. An open arena plays its field's own sound: wind and birds (grassland), surf (beach), rumble (volcano), wind (snowfield) and drips (cave); paved fields are quiet. It runs in real time, so hit-stop doesn't freeze it.

The presets are grassland, beach, volcano, snowfield, cave and stadium (the open fields and the paved coliseum), plus a night stadium, a garden coliseum (grassland in sandstone stands) and a frost coliseum (snowfield in pale blue stands). Presets evoke kinds of places (a league stadium at night, a gym's battle hall) and never reproduce specific locations from the games or the anime.

- **Style:** low-poly, flat-shaded scenery with pixel textures, which sits next to Cobblemon's blocky models without copying them. Built procedurally, so no outside art or licences are needed:
  - **Ground** (`Arena._ground_cell`): a faceted mesh with a vertex at every cell corner. The four cells around a corner are grouped by height (from the lowest, a group spans at most a 0.5 m step) the same way whichever cell asks, and each cell takes its group's average. So walkable ground slopes smoothly and shares its corners exactly, and the ground only parts at real steps and cliffs, closed by walls built once per edge and seen from both sides (small steps shaded ground, cliffs bare stone). Corners are nudged up to 0.18 m off the grid so it doesn't read as squares. The visible slope stays within a step of the battle's terraces; fighters are drawn on the slope.
  - **Features and props** (`LowPoly`): faceted frustums, cones, balls and logs: irregular six-sided rocks, hexagonal basalt columns, stalagmite and ice cones, faceted canopies, layered pine cones with snowy tips, palms with leaf blades. Bases sink 0.3 m so they sit in the faceted ground.
  - **Coliseum:** exact ring segments (meshes with their own top, underside, curved faces and ends).
  - **Pixel grain:** the surface shader lays 16 pixels per metre on each face (UVs in metres), with grime toward the ground on upright faces (moss in the coliseum). Cobblemon's own pixels are 16 per block before the roster's scale, which puts the models at 15–27 pixels per metre (20 at the median scale of 0.8), close to the arenas'.
  - **Light** (`ArenaLighting`): Cobblemon in Minecraft under a gentle shader pack. It's the same in every arena, so a preset only sets the place:
    - a Filmic tonemap with saturation 1.1, so highlights roll off without washing out type colours;
    - bloom only past an HDR threshold that daylit surfaces never reach. Glowing blocks (floodlights, screens, cracks, mushrooms), move visuals and models' emissive layers draw brighter than their colour, so only they bloom;
    - soft sun shadows that harden toward contact (PCSS, a 1.5° sun), out to 45 m;
    - screen-space ambient occlusion, so creases and the bases of rocks read;
    - MSAA 4× for edges, since TAA and FXAA would blur the pixel textures.

    Screen-space indirect light was tried and left out: it cost live play about a fifth of its frame rate in a full coliseum for a barely visible tint.
  - **Fighters:** lit by the arena but matte (no specular, like Cobblemon's models in Minecraft), with a soft rim in the light's colour so they stand out from busy ground.
- **Layout:**
  - in the open, the battle's own landscape (§9.8) out to 44 m, with its features: no floor or kerb, the arena is part of the land. In a coliseum the field's ground is built only out to the field's edge, with a stone kerb along it and the apron raised a little;
  - the ground coloured by slope (bare stone on steep ground), height and patches (paths, gravel, ash, trampled snow), with small low-poly details the battle ignores, sized to read at the battle camera's distance:
    - grass tufts: five to seven broad blades fanned out from a small mound, from the meadow's green to yellow-green tips. Blades are lit as if they faced up and out like the ground, since a thin blade's own normal shades it into a dark spike;
    - flowers about 0.3 m tall, with a leaf or two and a cupped head of petals around a centre;
    - faceted pebbles, shells, snow drifts, jagged glowing cracks, and glowing mushrooms with wide caps;
    - they gather as clusters in patches over about a quarter of the ground, densest in a patch's core and thinning toward its edge, with bare ground between. Each patch is mostly one kind (a grass patch, a flower bed, a pebble scatter), weighted by the field's details, with a few strays;
  - props on the land beyond the wall, three times as dense in the first 3 m, so a treeline or ring of rocks marks the edge;
  - the sea around the beach.

  Cameras may go 2 m past the wall; see-through keeps the fighters in view if the land is in the way.
- **Look:** each preset sets its sky, sun angle and colour, ambient light, fog and particles (petals, blown sand, rising embers, snow, cave dust).
  - The night stadium is lit by a dim moon and the roof's floodlights: four spotlights aimed at the field, only one with shadows, since each shadowed spotlight cost live play a few frames a second.
  - Day coliseums leave their floodlights off.
- **Choice:** `"arena"` in a battle spec or `--arena=<name>` picks one. Otherwise the battle seed picks from the presets offered always (grassland, stadium) and those that suit one of the fighters' types (Fire → volcano, Ice → snowfield and the frost coliseum, Water → beach and the frost coliseum, Rock, Ground, Ghost and Dark → cave, Dark, Ghost and Electric → the night stadium, and so on). The choice is the simulation's, since the field's terrain is part of the battle (§9.8); the ground and features are built from that terrain, and fighters stand at its height. New presets in the pool change which arena a seed gets, so they bump the rules version.
- **The coliseum** (`Coliseum`) is about 15 m tall and 75 m across:
  - the field (concentric rings of pale paving with painted lines: boundary, halfway line, centre circle; or the preset's field of terrain inside a kerb), then an apron of grey-green paving with a trainer's box at each end;
  - a 2.4 m stone wall with a coping;
  - lower stands, a concourse, upper stands and a parapet, split into 16 sections by pillars, with a tunnel into the lower rows of every other section;
  - a roof ring on posts with a floodlight bank, and banners on the parapet in each side's colour;
  - a big screen set into the upper stands at each end, behind each side's starting point, rising a little above them, with the fighters' names, where the battle's cameras see it;
  - a cool, slightly dim day, so the moves' colours stand out.
- **Cameras** stay inside a limit each arena sets (just inside the coliseum's wall, or where the ground starts to rise elsewhere), so they never end up inside the scenery.
- **Seats:** the arena offers seats facing the floor (on the stands' rows, else on low terrain nearby) for spectators.
- **Crowd** (`Crowd`), in coliseums only (a crowd on an open hillside would look odd):
  - low-poly figures (legs, a shirt in one of eight colours, arms, a head in one of four skin tones) in the preset's share of the stands' seats (three quarters by default), drawn as one MultiMesh and animated in a shader (`crowd.gdshader`), so thousands cost one draw;
  - the preset's number of watchers (four by default) of the arena's types (its `suits`, 0.4–2.2 m tall, never the fighters themselves) spread around the front row, each watching one fighter with its head;
  - they sway while they wait. Hits that take at least 15% of the defender's HP, critical hits and super-effective hits make them cheer: figures hop and raise their arms, more of them the bigger the hit, and the cheer calms over a couple of seconds. A knockout brings everyone to their feet for 3 s, and the Cobblemon cry. Hit-stop freezes the crowd along with the fighters.
- **Determinism:** everything, the particles included (fixed particle seeds), comes from the preset and the battle seed, so every render of a battle is identical.
- **Trainers** (`TrainerView`, M15): a side's `"trainer"` (`--trainer`, `--vs-trainer`, the setup screen; `none` for none) stands in its trainer's box on a coliseum's apron, or on the land just past the wall behind its start spot in the open: the games' sprite (§14), 80 pixels billboarded upright at about 1.75 m, pixel-sharp and unshaded. A team battle made from flags without one gets a generic trainer class from the seed (Ace Trainer, Youngster, Lass, Veteran, Hiker, Swimmer); one-on-one battles have none unless asked. The trainer throws a ball in an arc to send a Pokémon out (at the battle's start too), and the Pokémon appears with a flash where it lands; a switch first calls the Pokémon back with a red beam. It hops at a big hit by its side, slumps when one of its team is knocked out (for good at the last), and hops for joy when its side wins. `--list=trainers` names the 22 available: the generic classes and characters from the games and the anime (Red, Blue, Ash, Misty, Brock, Cynthia, Leon, Lance, Steven, Iris, N, Serena, Hop, Marnie). A trainer whose sprite isn't in the cache isn't drawn. Presentation only: the simulation never reads it.

### 12.8 Shinies and cosmetic forms

A fighter can appear **shiny** (its species' alternate colours) and in a **cosmetic form** (`Appearance`). Both are presentation only: a fighter's spec says `"shiny": true` and `"form": "east"`, the simulation never reads either, and the rules version (19) and checksums are unchanged. Forms that change types, stats or abilities were already species of their own (§8), so nothing here touches battle data. The 13 forms whose types, stats and abilities match their base species (Pikachu‑Partner, Sinistea‑Antique, Tatsugiri's and Maushold's forms and others) stay species too: their learnsets can differ.

- **Cosmetic forms:** for a base species, each Cobblemon form that isn't battle-only and that Showdown lists as no species of its own, or only as a cosmetic forme: Gastrodon's and Shellos' East Sea, Vivillon's patterns, Flabébé's line's colours, Furfrou's trims, Minior's cores, Alcremie's creams, Unown's letters, Deerling's and Sawsbuck's seasons and Burmy's cloaks. For any species Showdown says can be female, the female model, where Cobblemon has one. Forms whose files draw the same as the species' own look (the "Alola-Bias" marker forms) are dropped. For 1.8.4 that's 189 cosmetic forms: 98 on 13 species (Vivillon 20, Unown 27, Furfrou 15, …) and 91 female models (Hisuian Sneasel's among them).
- **Picking:** a battle made from flags (`--watch`, `--play`) rolls each fighter's look from its seed on a random stream of its own, and writes it into the spec, so the saved spec and `battle.json` replay it exactly:
  - a cosmetic form, each one as likely as the species' own look;
  - if it keeps its own look, the female model at Showdown's gender ratio;
  - shiny at 1 in 4096, the main games' odds, so random shinies are a rare treat and `--shiny` is the usual way to get one.

  Each side always takes the same draws, so one fighter's species never changes the other's roll. `--shiny=a|b|both|none`, `--form=<form>` and `--vs-form=<form>` (`base` for the species' own look) set them instead. A spec without them, such as one saved before they existed, shows the species' own look and colours, so it renders as it always did; a form the species doesn't have is an error.
- **Pipeline:** each cosmetic form is converted as a model of its own, `models/<id>@<form>.scn`. Every look (a species' own and each form) gets its shiny: a **skin** (`<look>~shiny.res`, the converter's material with the shiny texture and layers) when the shiny only changes textures, as almost all do, or a model of its own (`<look>~shiny.scn`) when it changes the model or poser (Gastly, Slugma and Magcargo). Both are cached per look by a key over their inputs, like models; converting everything from scratch takes about 6 minutes, and the models folder grows from 528 MB to 684 MB. A look without a shiny texture is flagged `no_shiny` in the QA report (none in 1.8.4). In the game, a shiny or form that isn't in the cache falls back to the species' own look and colours with a warning, so a clip never shows a broken model.
- **Showing a shiny:** it sparkles as the battle opens, with its cry: Cobblemon's own shiny ring and glimmer on the native particle runtime, or gold glints with the mesh move styles (`--mesh-fx`). Its name plate has a gold sparkle after the name, in both formats, and its HUD portrait wears the shiny colours. Forms show only in the model; the name stays the species'.
- **Review:** `tools/preview_roster.gd` takes `species@form`, `species~shiny` and `--forms` (every cosmetic form) with `--shiny`.

## 13. Ranking

- **Storage:** raw battle records go into an append-only JSON Lines store under `results/`, which is git-ignored. Ratings are always derived from the records, never stored on their own.
- **What a rating means:**
  - A species with its standard moveset, at level 50, under one rules version and the ranked AI profile.
  - A new rules version starts a new ranking.
- **Method:**
  - A Bradley–Terry model is fitted to all results, with each draw counting as half a win for both sides.
  - Unlike Elo, the fit doesn't depend on the order battles were played. It uses every result and copes with incomplete schedules.
  - Glicko-2 can be added later to show uncertainty.
  - A matchup matrix of head-to-head win rates is published next to the ratings, because one-on-one matchups are often non-transitive.
- **Fairness:**
  - Every matchup is played from both sides with the same seeds.
  - An AI-sensitivity check re-ranks with a second AI profile and compares the rank correlation. A large change means the AI, not the Pokémon, is driving results.
- **Scale:** 1,005 species make about 504,000 matchups, or about 1,009,000 battles played from both sides.
  - Throughput is measured in milestone 1.
  - If a full round-robin is too slow, matchups are sampled adaptively, with more battles where ratings are uncertain.
  - Headless processes run in parallel.
- **Balance tool:** the same machinery tunes the rules (§9.7).

**Implementation (M5)** in `tools/ranking/ranking.gd` (the maths) and `tools/rank.gd` (the command line).

- **Store:** one JSON Lines file per run and shard in `results/rank/v<rules>/<profile>/`. Each line is one battle: `{a, b, seed, result, ticks, rules, profile}`. Runs resume by skipping battles already stored.
- **Schedule:** a sampled round robin. Every species meets 20 random others (more in practice, as others pick it too), every matchup from both sides with one seed derived from the pair and the schedule seed.
- **Fit:**
  - Bradley–Terry by the MM algorithm, with one virtual draw per species against an average opponent, so an unbeaten species still gets a finite rating.
  - Ratings use an Elo-like scale: 400 points is 10:1 odds, and the mean is 1500.
- **Matchup matrix:** a full round robin among the top 24 species, 5 seeds per matchup, each played from both sides (10 battles per cell).
- **Report:** `ranking.json` and `ranking.md` with ratings, battles, scores and the matrix.
- **AI-sensitivity check:** `compare` ranks the species two profiles both played and prints the Spearman rank correlation.
- **Pilot** (60 species, 10 opponents each, 1,200 battles in 38 s on 11 processes, about 32 battles a second):
  - The ranked and hard profiles agree closely (Spearman 0.971), so species, not the AI, drive results.
  - Mirrored matchups don't show a side bias: the same side won both battles in 37 of 600.
  - A full run of every species with 20 opponents is about 40,000 battles, roughly 20 minutes on 11 processes.

## 14. Licensing and attribution

- **Repository:** original code and data only, under the MIT licence.
- **Cobblemon assets:**
  - Each model folder in the jar carries a Creative Commons licence matching Attribution-NonCommercial 3.0.
  - Until confirmed otherwise, textures and animations are treated the same way.
  - Cobblemon's code is MPL-2.0, but we don't use it.
- **Showdown data:** MIT.
- **Music:** the scores are original and MIT like the rest of the repository. The instruments they are rendered with come from GeneralUser GS (S. Christian Collins), whose licence allows its use in music and software; the rendered audio stays in the local cache.
- **Crowd and ambience recordings:** CC0, from Freesound and OpenGameArt; credited anyway, by title and author, in each clip's credits.txt and the README.
- **Pokémon IP:** names and designs belong to Nintendo, Creatures Inc. and GAME FREAK. Cobbleseum is an unaffiliated fan project.
- **Consequences:**
  - The repository never redistributes assets.
  - Every clip credits Cobblemon on its credits card and in generated description text.
  - Commercial use of clips needs permission. Whether clips will be monetised is an open question (§19).
- **Trainer sprites** (M15): the games' trainer sprites are official art, not openly licensed fan work like Cobblemon's. They come from Pokémon Showdown's sprite server (`sources.json`'s `trainer_<id>` entries, pinned by SHA-256), whose repository (smogon/sprites) states no settled licence for its images and asks to be asked before they're used; the decision to fetch them anyway for local, non-commercial clips was taken knowingly (2026-11-18). They are fetched into the local cache only, never committed or redistributed, every clip with trainers credits them, and like the rest of the Pokémon IP they keep clips non-commercial.

## 15. Proposed project layout

```
project.godot
sources.json            pinned asset sources
game/
  sim/                  battle rules and simulation (no scene nodes)
  ai/
  presentation/         arena, fighters, camera, HUD, effects
  play/                 player controls, battle flags and the command line's help
  setup/                the setup screen and after-battle menu
  data/                 rules constants and override tables (original data)
tools/
  assets.gd             pipeline entry point
  sources/              one script per source
  music/                SoundFont reader, arranger, renderer and the scores
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
- **Converter:** Blastoise and Cinderace convert with working animations, and all 905 species pass a dry run.
- **Simulation core:**
  - Fixed tick, melee and projectile moves, the damage formula, cooldowns and knockouts, with a placeholder AI.
  - About 37 ms per battle headless, with identical checksums across processes.
- **Recording:** checksum-verified 10-second clips in vertical and landscape, encoded to MP4.

So far M1 has been tested on Windows only. macOS and Linux get checked before M2 ends.

**M2: rules and roster.**

- All supported move kinds, stat changes, status conditions and dodging. Movement, melee dashes, dodging, stat stages, status conditions and every move kind are done; the stand-in AI dodges about half the threats it sees while it can act, keeps a range suited to its ready moves, and circles.
- The moveset generator. Done.
- Full roster conversion with per-species caching, a QA report and the roster file. Done, with a converter QA pass (§7.5).
- The procedural animation layer. Done.
- Batch simulation with a balance report, and a first tuning pass. Done.

**M3: presentation** (everything in §12.2–§12.5):

- Presentation time: hit-stop and slow motion.
- The camera director and its shot list, framed for both formats.
- Impact frames, screen shake, speed lines, hit flashes and callouts.
- Type-themed move effects and sound.
- The animated HUD, with intro, outro and credits cards.
- Highlight selection for clip windows.

M2 and M3 don't depend on each other, so their order can swap if watchable clips matter sooner.

**M4: AI and play.**

- The utility AI, with profiles and a debug overlay. The AI, profiles and overlay are done.
- Player-vs-AI controls (keyboard and gamepad) and a player camera. Done: `--play=<species> --vs=<species> --ai=<profile>` runs the battle live (no pre-planned presentation, since a player's choices can't be known ahead), with a camera over the player's shoulder, live hit-stop that pauses the battle itself, a move bar with keys and cooldowns, and each battle saved as its battle spec with every tick's intents, which `ReplayController` replays and `tools/record.gd` can render. AI-vs-AI battles start the same way with `--watch=<species> --vs=<species> --ai=<profile> --vs-ai=<profile>` (`SpecFlags`), in the window and in `tools/record.gd`, without a spec file.

**M5: rankings.**

- The results store, the Bradley–Terry fit, the matchup matrix and the ranking report. Done: `tools/rank.gd` (§13).
- The AI-sensitivity check. Done: `tools/rank.gd -- compare`.

**M6: battle feel.** Battles should read as two creatures fighting, not two models sliding into contact and staring at each other.

- **Facing and momentum:** a turn rate instead of always facing the foe (fighters face where they walk and turn to attack), acceleration and braking, and knockback scaled by damage and the defender's weight.
- **Spacing rhythm:** the AI keeps wider, varied distances, circles in arcs, backs off after a melee exchange, and on harder profiles feints to draw a dodge. Feints are done (rules version 16, §9.2, §11).
- **Movement styles by body:** fliers hover, swoop and dive; heavy species lumber and plant themselves; fast ones dart.
- **Presentation-only life:** leaning into movement, head tracking, squash on landing and recoil.
- Sim changes bump the rules version and get a balance batch and a new ranking.

**M7: arenas.** Arena presets (a field, a venue and a look) are done, with nine presets (§12.7).

- Arenas, each with its own field, props, sky, lighting, fog and particles, picked at random or by the fighters' types. Done as presets: five open fields, the paved stadium, a night stadium and two coliseums around fields of terrain.
- Crowds: cheap animated spectators in a venue's stands (coliseums only), including watchers in the front row, reacting to big hits and knockouts. Done (§12.7).
- Cosmetic first; terrain that affects play (cover, water, elevation) only later, as a rules change the AI understands.
- Environment art comes from openly licensed sets or is made in-house; Minecraft's own textures aren't usable.

**M8: visual polish.**

- Rendering: environment lighting, soft shadows, ambient occlusion, bloom, and shading that matches Cobblemon's look. Done (§12.7): Filmic grading, HDR bloom on glowing things only, soft sun shadows, SSAO, MSAA, matte rim-lit fighters, and a floodlit night stadium. Recording takes about 1.1× as long as before.
- A designed HUD (styled HP bars, type icons, portraits, status badges), intro title cards, and a victory screen with the winner's pose. Done: name plates with portraits (§12.5), type and status pills, rounded HP bars with percentages, the intro card (§12.5), and the victory shot and card (§12.3). Types are text pills rather than icons.
- Openly licensed display and body fonts, never the official Pokémon fonts or logo styling. Done: Lilita One and Nunito.
- Music and crowd sound. Done (§12.5, §12.7): three original tracks rendered from scores with General MIDI instruments, picked by the seed with variants, a victory sting and overtime's climax layer; the crowd's murmur, cheers and roar in coliseums and each field's ambience in the open.
- For clips, title cards, captions and an instant replay of the knockout. Done (§12.3, §12.5): the intro card names the arena (and overtime), "COMEBACK!" and "FINAL BLOW" captions, and an instant replay of the knockout from new angles before the victory.

**M10: arena moves. Done (2026-11-17).** The last planned rules change (§9.11), one pull request and rules version each: weather (20), surges (21) and screens (22), with their abilities and items, the moveset policy and both AIs taught to use them, tests, balance batches and paired probes, and presentation in both clip formats (the sky, field and particles, HUD pills and badges, callouts). Left out on purpose: entry hazards (until team battles have switching), Tailwind, Safeguard, Mist, the rooms, Gravity, Quick Guard, Wide Guard and Fairy Lock, and the moves whose power or type follows a condition (Weather Ball, Terrain Pulse, Rising Voltage, Expanding Force, Grassy Glide, Steel Roller). A fresh ranking (§13) under rules version 22 is still to be run.

**M9: abilities, items and guarding. Done (2026-11-17).** The rules items from "Later" that need no arena moves (§9.2, §9.9, §9.10), one pull request and rules version each, with the AIs taught to use them, tests, a balance batch, and presentation in both clip formats. A fresh ranking (§13) under rules version 19 is still to be run.

- Guarding: a timed parry with a cooldown, which feints can bait. Done (rules version 17, §9.2, §11).
- Abilities: a standard ability per species from a first set of 78. Done (rules version 18, §9.9).
- Held items: a standard item per species from a first set of 31. Done (rules version 19, §9.10).

**Review of an AI-vs-AI battle (2026-11-17).** Watching a full battle raised the milestones below, in this order. Concrete bugs found in the same review (fainting Pokémon sinking through the floor, eyes stuck closed, Rayquaza's movement, the surge look) are fixed as bugs, outside these milestones. The species ranking (§13) is still deferred: it runs once, after M15, when the rules settle.

**M11: battle feel. Done (2026-11-17).** Presentation only; no rules change, and the rules version stays 22. Done as smooth motion (§12.2), a calmer edit (§12.3), time-fitted attacks with quicker crossfades and speed-matched gaits (§7.4), and callouts and body-placed pieces that follow their fighter (§12.4, §12.5), with three leftovers from the review's bug pass: procedural breathing on held-pose idles (§7.4), hovering only for Flying types that can fly (§7.4), and a sandstorm that keeps the fighters readable (§9.11). Rayquaza still lies with its upper body raised after a knockout, since its only pose holds it up. The live play camera wasn't playtested yet.

- **Smooth motion:** fighters, the camera and effects interpolate between ticks at the display rate. Today a window shows the 30 Hz simulation in steps (0 or 2 steps in some display frames), which reads as jitter and lag.
- **A calmer edit:** every shot holds for at least about 1 s, and an overlay shot (close-up, impact, tracking) that can't get that long is dropped or merged with its neighbour, never cut in for a tick or two. Nearby angles blend with a short ease instead of a hard cut, and wide and over-the-shoulder shots alternate less often. Watch mode and recordings keep sharing one director.
- **Responsive animation:** the simulation stays the source of truth and animation follows it. Attack crossfades drop to about 0.05 s; attack animations are time-fitted so the strike pose lands on the release; walking blends by actual speed.
- **Callouts follow their fighter:** damage numbers, stat changes, ability and item names track the fighter's head each frame (still rising and fading, clamped to the screen, stacked so they don't overlap) instead of staying where the fighter was. Move banners and captions stay in screen space on the HUD.
- **Effects follow their fighter:** move-effect pieces placed on a fighter's body (Swords Dance and other buffs, stat cues, heals, status, charge glows, hit sparks) follow that fighter for their life. Ground pieces (quake rings, scorch, blasts) and projectiles stay in the world.

**M12: HUD clean-up. Done (2026-11-17).** Presentation only; no rules change, and the rules version stays 22. Done as an effect row under each HP bar (§12.5): timed square badges for status conditions, confusion and screens, then stat stages as arrows with counts, all with icons drawn in-house, and head-and-shoulders portraits. Type pills are alone on the plate. The live play window wasn't playtested yet.

- **Status reads apart from type:** type pills stay rounded and filled in the type's colour. Status conditions and confusion become square dark badges with an icon, a short code (PAR, BRN) and a draining timer, in a row of their own under the HP bar. Screens move to that row too.
- **Stat stages on the plate:** small ↑ and ↓ arrows with counts per changed stat in the same row, gone once the stage wears off.
- **Head-and-shoulders portraits:** the portrait frames a square on the head (the head bone, or the top of the silhouette where the bone sits mid-body), like a character-select bust. Small round species, whose head is most of them, keep the whole body.

**M13: setup screen and CLI. Done (2026-11-17).** Presentation and tooling only; no rules change.

- **Setup screen:** a plain launch opens it instead of the showcase battle. It sets the mode (watch, play, record), each side's species (searchable, with a model preview; team slots since M15), form and shiny, ability, item and moves (standard by default), the arena and weather, each side's AI profile and the seed. It builds the same battle spec the flags build; Record runs `tools/record.gd`. After a battle: rematch or back to the menu.
- **Doubles** (M17): a Singles/Doubles choice next to the arena (each side then needs 2–6 in its team slots), and `--doubles` on the command line.
- **CLI:** `--help` for the game, `record.gd`, `battle.gd` and `rank.gd`; unknown flags and misspelt species, arenas, moves, abilities and items fail with the nearest matches; `--list=species|arenas|moves|abilities|items|profiles`; the resolved spec (seed, arena, looks) printed at the start, so any run can be repeated.

**M14: spacing by fighting style. Done (2026-11-17).** A rules change (rules version 23, §11, balance batch in §9.7). The utility AI picks its preferred distance from its whole moveset and stats, not only from which moves are ready: species that lean special and ranged kite at range and dash in only for a ready melee opening, and physical brawlers press in. Until then any ready melee or area move pulled a fighter to about 2 m, even when most of its moveset was ranged. In overtime everyone closes in for melee, which keeps draws under target. A fresh ranking (§13) under rules version 23 is still to be run, after M15. The live play camera and spacing weren't playtested.

**M15: team battles (singles). Done (2026-11-18).** One Pokémon out per side, teams of 1–6 (3v3 and 6v6 as the usual sizes), to stage battles like the games' and the anime's, in rules versions 24–29 (teams, switching, AI switching, entry hazards, pace, and the leads' send-out starting the switch cooldown), with team flags, setup slots, trainers and the team HUD between them. One-on-one battles play exactly as under version 23 throughout (300-battle batches matched battle for battle), so the species ranking (§13) still waits only on its own run. A full 6v6 lasts about 2.5–3 minutes. Recreations of real battles stay as local specs in the git-ignored `specs/` folder. Not checked live: play mode's switching (the bench bar and keys) and the setup screen's team slots and trainer choice; clips were rendered and inspected in both formats. Its own rules versions, one pull request each where they split cleanly:

- **N fighters per side in the simulation:** done (rules version 24, §9.1). The battle, AI, director, HUD, highlights and spec stop assuming exactly two fighters. A side has a team and an active fighter; the battle ends when a side has no one left. Doubles (M17) reuse this, so no new one-per-side assumptions.
- **Switching:** done (rules version 25, §9.1). A "switch to N" intent, available whenever the fighter could act. The recall and send-out take about 1 s, in which the incoming Pokémon can be hit; then a switch cooldown of about 5 s. A knockout forces a pick. Stat stages and confusion clear on switching out; major status stays with the Pokémon.
- **Team specs:** done (§9.1, §10). `--team=a,b,c` and `--vs-team` list each side's team (moves, ability, item and look flags go to the first member), the setup screen has six team slots a side (bench members bring their standard sets), and `--help` documents them. Hand-written specs go in the git-ignored `specs/` folder. The battle spec lists each side's team (species, and optionally moves, ability, item, form and shiny per member); quick runs use a flag such as `--team=a,b,c`. Recreations of battles from the games or the anime are hand-written specs kept locally, not committed.
- **AI:** done (rules version 26, §11). Switching is another utility candidate, scored by the matchup gain of a bench member (expected damage dealt against taken), own HP, status and stage losses, minus the send-out risk. Profiles get a switch chance, like the feint and guard chances.
- **Entry hazards** done (rules version 27, §9.11). Stealth Rock, Spikes, Toxic Spikes, Sticky Web right after switching, as their own rules version, acting on send-out.
- **Pace:** done (rules version 28, §9.1). 1v1 tuning is unchanged. A team-battle HP multiplier by team size keeps a full 6v6 around 2–3 minutes (about 20–30 s a knockout), tuned by balance batch; the overtime clock scales with the Pokémon left.
- **Trainers:** done (§12.7, §14). A trainer stands in each side's trainer's box, throws on send-out and recall, and reacts. Its look comes from the games' trainer sprites, billboarded, fetched into the git-ignored cache like other assets and never committed (§14).
- **HUD and clips:** done (§12.5, §12.6). Each side shows its team as six balls (healthy, statused, fainted); clips pick the best window across the whole battle; the music ends only on the final knockout (§12.5).
- **Ranking:** stays one-on-one (§13). Team results don't feed it, since a team win can't be credited to one species.

**M16: battlefield marks. Done (2026-11-17).** Presentation only; no rules change, and the rules version stays 23. Done as described in §12.5 (battlefield marks), checked in previews on every preset, in weather and surges, and in recorded clips in both formats; the live window wasn't playtested. Hits and area and ground moves leave decals by move style and type (scorch, frost, cracks, crater rings, splash stains) and small debris that settles, drawn from the battle seed so renders repeat. They last the whole battle, up to about 40 (the oldest fade), so an arena shows the fight by the knockout. They never touch the simulation; marks that change the ground for play would be a later rules change the AI understands.

**M17: doubles. Done (2026-11-18).** Two Pokémon out per side, after M15, in rules versions 30–34 (two out a side with targeting and spread moves, the doubles AI, ally moves, abilities in doubles, pace) and a presentation pull request between them (the view, director, camera, HUD, `--doubles` and the setup screen). Singles and singles team battles play exactly as under version 29 throughout (the 300-battle one-on-one and 150-battle 3v3 batches matched battle for battle after every rules change), so the species ranking (§13) still waits only on its own run. Doubles clips were rendered and inspected in both formats. Not checked live: play mode in doubles (T to cycle the target, the target ring, the AI ally) and the setup screen's Singles/Doubles choice. Designed 2026-11-18 (a design pass with the user, every choice below the recommended one):

- **Doubles:** a spec's `"doubles": true` (`--doubles`, a Singles/Doubles toggle on the setup screen) sends out the first two of each side's team of 2–6 (2v2 with no bench, 4v4 the usual size, 6v6 the long form); a doubles team of one is an error. Singles specs, battles and checksums are unchanged. The two start 2.5 m either side of their side's singles start spot, inside its level, open ground. Allies can't pass through each other, any more than foes.
- **Targeting:** each fighter locks onto one foe (a `"target"` intent: the foe's place, 0 or 1). Its facing, melee dash, projectile aim, feints and guards follow that target, and it can retarget whenever it could act; the turn rate makes a switch take a moment. A target knocked out (or recalled) passes the lock to the other foe until a newcomer takes its place. A projectile whose target faints vanishes. In play the player drives the first fighter out and the side's AI profile runs its ally; the lock starts on the nearest foe and T (a shoulder button) cycles it.
- **Spread moves:** area moves (Showdown's `allAdjacentFoes` and `allAdjacent` targets) hit every fighter in their ring, at ×0.75 each when they hit more than one, as in the main series; spread status and debuff moves fire one projectile at each foe in range. Single-target moves stay single-target.
- **Friendly fire:** only `allAdjacent` moves (Earthquake, Surf, Explosion, Discharge…) hit the ally in their ring; single-target moves pass through or ignore it.
- **Ally moves** (never in standard movesets; specs and flags give them): ally boosts (Helping Hand: the ally's next move within 4 s ×1.5; Coaching, Howl, Dragon Cheer, Aromatic Mist), team heals (Life Dew, Jungle Healing, Lunar Blessing), Follow Me and Rage Powder (every foe's lock snaps to the user for 4 s, 12 s cooldown) and Wide Guard (blocks spread moves on the user's side for 1 s, 12 s cooldown). Tailwind and Quick Guard stay out: speed order and priority have no clear real-time reading.
- **Abilities:** Intimidate lowers both foes in range; Lightning Rod and Storm Drain pull foes' single-target Electric and Water projectiles to the holder; Friend Guard (the ally takes ×0.75) and Telepathy (no damage from the ally's moves) join the table. Everything else acts on the pair it already does.
- **Knockouts and switching:** the 2 s lull and the shielded 1 s landing stay, but the other three fight on meanwhile (nobody is frozen); with no bench left a side fights on alone. Either fighter can switch whenever it could act, under the side's shared 5 s switch cooldown.
- **Pace:** the team HP factor stays, with a doubles factor tuned by balance batch so a 4v4 lasts about 90–120 s and a 6v6 about 2.5–3 minutes; the overtime clock restarts at each send-out after a knockout and time-up goes to more Pokémon left, then the HP share, as in M15.
- **AI:** each fighter still decides on its own but sees its ally: target choice weighs expected damage, the chance to finish and a focus-fire bonus for its ally's target; it won't throw a spread move that hurts its ally more than it helps, uses ally moves when the ally gains, and keeps apart from its ally. No central planner.
- **Camera:** wide and over-the-shoulder shots frame every fighter out, fitted to the format; close-ups, punch-ins, tracking and knockout orbits stay on the event's attacker and target. No wide shot hides a fighter.
- **HUD:** two slimmer plates stacked per side (top-left and top-right in landscape, top and bottom in portrait), team balls once per side under the pair; play mode marks the player's lock.
- **Ranking:** stays one-on-one (§13).
- **Pull requests:** (1) two out per side in the simulation, targeting, spread moves and ally fire (rules version 30); (2) the AI for doubles (31); (3) `--doubles`, the setup screen, the director, the HUD and clips; (4) ally moves (32); (5) ally and both-foe abilities (33); (6) doubles pace (34), which marks M17 done.

**Later:**

- Arena moves and weather. Done in M10 (§9.11): weather, surges and screens; entry hazards wait for team battles (M15).
- Tournament mode seeded from the ranking. Format not decided.
- Team battles. Done as M15 (singles) and M17 (doubles).
- Shiny and form variants in clips. Done (§12.8): cosmetic forms and shinies, rolled from the seed or set by flags, with a sparkle on entry and on the name plate.

## 18. Risks

| Risk | Mitigation |
|---|---|
| Licence and IP: Cobblemon assets are non-commercial, and Pokémon designs belong to their owners | No assets in git; attribution on every clip; monetisation decided explicitly |
| Conversion rules (axes, rotation order, UVs) are wrong in some cases | Golden tests on original fixtures; `.glb` debug export; QA pass over the whole roster |
| Most species lack attack, hit or faint animations | Procedural animation layer from M2 |
| Forms or species rendered wrong (parts, layers, poses) | M2 review of every flagged species and all 100 forms with `tools/preview_roster.gd` (§7.5); rerun it after converter or source updates |
| GDScript simulation too slow for full round-robins | After M2, about 57 ms per battle with the full rules and 30–45 s battles (a full round robin of about 504,000 matchups is roughly 8 hours, or 1 hour on 8 processes); profiled and optimised once in M2; sample pairings before considering other options |
| Replays differ across platforms | Guarantee replays per platform only; checksums fail loudly |
| Real-time balance is our own design | Rankings are framed as "under Cobbleseum's rules"; batch-simulation tuning; AI-sensitivity check |
| A new Cobblemon release changes the layout | The pinned version never changes silently; layout checks give clear errors |
| Recording needs a window, and each format is a separate render | Clip windows of at most 60 s; skip ahead before the window; render only the formats needed |

## 19. Open questions

1. Will clips be monetised? Cobblemon's assets are non-commercial (§14).
2. Tuning constants beyond the first pass (§9.7), which set the HP multiplier and overtime: the cooldown formula, speed band, dodge charges and status durations are still first guesses.
3. Cobblemon's per-model licence files cover models, animations and textures. The jar states no separate licence for its sounds, so the credits assume the same CC BY-NC 3.0 terms. Confirm with the Cobblemon team before any wider release.
   - **Move effects:** the particle effects (`assets/cobblemon/bedrock/particles/`), their textures (`assets/cobblemon/textures/particle/`) and the scripted move effects (`data/cobblemon/action_effects/`) have no licence file either. The jar's only licences are the root `LICENSE` (MPL-2.0) and the CC BY-NC 3.0 text, which appears only in `assets/cobblemon/bedrock/pokemon/models/` and its model folders.
     - **Our current reading** (not settled): since the CC BY-NC text sits only with the models, the particles, their textures and the scripts may fall under the root MPL-2.0. The credits name the move effects with both licences, and we keep using them non-commercially like everything else from Cobblemon.
     - Ask the Cobblemon team about sounds and move effects in the same question. Minecraft's own textures, which Cobblemon ships for a few particles, are never used: the build deletes them and draws our own in their place (§12.5).

Resolved in milestone 1: tests use a small in-house runner (`tests/run_tests.gd`) instead of an add-on; recordings use OGV from Movie Maker, encoded to MP4. Resolved in milestone 2: stat stages wear off over time (§9.5). Reviewing all 100 forms found no wrongly shown parts; forms differ through their own models, textures and layers (§7.5), not hidden bones. Without that, a species whose attacks all use one stat stalled once moves like Overheat had dropped it to −6.
