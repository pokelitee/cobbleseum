# Cobbleseum

A local-first 3D Pokémon battle game built with Godot 4. Two Pokémon fight in real time in a small arena, rendered with Cobblemon's models and animations and driven by Pokémon Showdown's data. Battles can be player-vs-AI or AI-vs-AI, AI-vs-AI battles can be recorded as vertical 1080×1920 clips, and many simulated battles feed a local ranking of every species.

The repository contains only original code and data. Third-party assets are downloaded into a local, git-ignored cache and never committed.

Status: early development. See the [concept brief](concepts_brief.md).

## Getting started

Prerequisites:

- [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) (standard build, not .NET). Put it on your `PATH` as `godot`, or substitute its full path below.
- Node.js 20 or later, for the asset pipeline's Showdown data export.
- ffmpeg, for encoding recorded clips to MP4 (coming in milestone 1).

Fetch and prepare the assets (about 157 MB to download the first time):

```bash
godot --headless --path . --script res://tools/assets.gd
```

This downloads the pinned sources listed in [sources.json](sources.json), verifies their size and SHA-256, extracts the parts the game uses into `cache/`, checks their layout, exports Showdown's data to JSON, and converts every Pokémon with a Cobblemon model (1,005 species and forms) to a Godot scene. It also writes the roster (`cache/build/cobblemon/<version>/roster.json`: model, scale, height, hitbox, clips, QA flags and licence per species) and a QA report (`report.json`). Extracting Cobblemon's roughly 12,000 files and the first conversion take a few minutes each (about 7 minutes to convert on a desktop PC). Re-running skips finished steps; models are cached per species, so a rebuild converts only species whose inputs changed, and an interrupted build picks up where it stopped. Pass `-- --offline` to fail instead of downloading when something isn't cached, or name sources to process only those (`-- showdown`).

Print species' standard movesets, or generate them all into `cache/build/movesets.json` with a summary (failures, common moves, agreement with Showdown's random-battle sets):

```bash
godot --headless --path . --script res://tools/movesets.gd -- garchomp breloom
```

Run a battle headless (prints the result, length and a checksum per seed). In a battle spec, a fighter without `moves` uses its species' standard moveset, and `"ai"` picks its controller (`easy`, `normal`, `hard`, `ranked` (the default) or `simple`):

```bash
godot --headless --path . --script res://tools/battle.gd -- game/data/battles/showcase.json --seeds=10
```

Run a balance report: seeded random pairings of the whole roster with standard movesets. It prints battle length, draw rate, how often type advantage wins, move-kind use and side bias, and writes everything to `results/`:

```bash
godot --headless --path . --script res://tools/batch.gd -- --battles=500 --seed=1
```

Pit two AIs against each other over random pairings (side A's win rate shows which is stronger):

```bash
godot --headless --path . --script res://tools/batch.gd -- --battles=300 --ai-a=hard --ai-b=easy
```

Rank the species: play a sampled round robin (every species meets 20 random others, from both sides) over parallel processes, then fit Bradley–Terry ratings. `report` writes `results/rank/v<rules>/<profile>/ranking.md`. `matrix` plays the top 24 against each other (5 seeds per pairing) for the matchup matrix, and `compare` checks how much the ranking depends on the AI profile (after a `run --profile=hard`). `--limit=60` runs a small pilot:

```bash
godot --headless --path . --script res://tools/rank.gd -- run --jobs=8
godot --headless --path . --script res://tools/rank.gd -- report
godot --headless --path . --script res://tools/rank.gd -- matrix --jobs=8
godot --headless --path . --script res://tools/rank.gd -- run --jobs=8 --profile=hard
godot --headless --path . --script res://tools/rank.gd -- compare --against=hard
```

Record a battle as video clips (needs a display and ffmpeg; output goes to `recordings/`). The clip is the most exciting stretch of about `--seconds` (usually ending on the knockout), with hit-stop, slow motion and camera shots planned from the battle's events. `--format` is `vertical` (1080×1920, the default), `landscape` (1920×1080) or `both`; every format shows the same battle. A render fails if it doesn't match the headless run or logs a script error:

```bash
godot --headless --path . --script res://tools/record.gd -- game/data/battles/showcase.json --seconds=10 --format=both
```

Instead of a spec file, flags can describe an AI-vs-AI battle, here and in the window below: `--watch=<species>` against `--vs=<species>` (default Blastoise), with `--ai=<profile>` for the first and `--vs-ai=<profile>` for the second (default: the same as `--ai`). `--seed=N` picks the battle; without it, each run is a new one:

```bash
godot --headless --path . --script res://tools/record.gd -- --watch=garchomp --vs=hydreigon --ai=hard --vs-ai=easy --seed=7
```

Play against the AI (keyboard: WASD or arrows to move, Space to dodge, J K L I or 1–4 for moves; gamepad: left stick, A to dodge, X Y B RB for moves). R starts a rematch and Esc quits. Each battle's replay is saved to `recordings/replays/`, and `tools/record.gd` can render one like any spec:

```bash
godot --path . -- --play=cinderace --vs=blastoise --ai=normal
```

Watch the showcase battle in a window: `godot --path .`, or any AI-vs-AI battle with the flags above: `godot --path . -- --watch=garchomp --vs=hydreigon --ai=hard`. Add `--arena=grassland|beach|volcano|snowfield|cave|stadium` to pick the arena; otherwise the seed picks one that suits the fighters' types. Press F3 to show the AI debug overlay (each side's candidate actions and their scores); `godot --path . -- --ai-debug` starts with it on, and `tools/record.gd -- <spec> --ai-debug` records it.

Run the tests:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

Preview converted models (opens a window; images go to `cache/previews/`):

```bash
godot --path . --script res://tools/preview_model.gd -- 0009_blastoise --clip=physical
```

Preview roster species as they appear in battle, for converter QA (opens a window; writes a contact sheet to `cache/previews/`). Name species, or pass a QA flag from `report.json`:

```bash
godot --path . --script res://tools/preview_roster.gd -- --flag=pose_mismatch
```

Preview every move style (opens a window; images go to `cache/previews/move_<style>.png`):

```bash
godot --path . --script res://tools/preview_moves.gd
```

Check that no third-party assets are tracked:

```bash
tools/check_no_assets.sh
```

## Architecture

The design is described in the [concept brief](concepts_brief.md). In short:

- An asset pipeline (`tools/assets.gd`, `tools/pipeline/`, one build script per source in `tools/sources/`) fetches pinned releases of Showdown's data and Cobblemon's jar, verifies them by SHA-256, extracts and checks them, and builds what the game needs in `cache/`. Cobblemon's Bedrock models and animations become Godot scenes (`tools/convert/`): a skeleton with one rigidly skinned mesh and clips baked at 60 Hz.
- A deterministic, fixed-tick battle simulation written in plain GDScript (`game/sim/`) runs headless for batch simulation and drives the 3D presentation. Rules constants live in `game/sim/rules.gd`; randomness comes from seeded mulberry32 streams, so a battle replays exactly from its spec.
- A utility AI controls fighters through the same intents a player uses.
- The battle view (`game/presentation/`) replays the simulation with the converted models, a portrait camera and HP bars. `tools/record.gd` runs a battle headless, picks the clip window from its events, renders it with Godot's Movie Maker mode in a second Godot process, checks that the rendered battle's checksum matches, and encodes an MP4 with ffmpeg.

## Documentation

- [concepts_brief.md](concepts_brief.md): goals, decisions, asset sources, rules, architecture, milestones and open questions.

## Contributing

- Branch from `main` and open a pull request. `main` is protected and merges are squash-only.
- Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages and PR titles.
- Add or update tests with behaviour changes. Tests live in `tests/` as `test_*.gd` scripts that extend `TestCase`.
- Never commit downloaded, extracted or converted third-party assets, or screenshots and videos made from them. To run the asset check before each commit:

  ```bash
  git config core.hooksPath .githooks
  ```

## License

The code and original data in this repository are licensed under the [MIT License](LICENSE).

Assets fetched by the pipeline keep their own licences: Pokémon Showdown is MIT, and Cobblemon's models and animations are Creative Commons Attribution-NonCommercial. Pokémon names and designs belong to Nintendo, Creatures Inc. and GAME FREAK. Cobbleseum is an unaffiliated fan project.
