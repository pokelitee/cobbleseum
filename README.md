# Cobbleseum

A local-first 3D Pokémon battle game built with Godot 4. Two Pokémon fight in real time in a small arena, rendered with Cobblemon's models and animations and driven by Pokémon Showdown's data. Battles can be player-vs-AI or AI-vs-AI, AI-vs-AI battles can be recorded as vertical 1080×1920 clips, and many simulated battles will feed a local ranking.

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

This downloads the pinned sources listed in [sources.json](sources.json), verifies their size and SHA-256, extracts the parts the game uses into `cache/`, checks their layout, exports Showdown's data to JSON, converts the showcase Pokémon to Godot scenes and writes a conversion report for every Cobblemon species (`cache/build/cobblemon/<version>/report.json`). Extracting Cobblemon's roughly 12,000 files can take a few minutes. Re-running skips finished steps. Pass `-- --offline` to fail instead of downloading when something isn't cached, or name sources to process only those (`-- showdown`).

Run a battle headless (prints the result, length and a checksum per seed):

```bash
godot --headless --path . --script res://tools/battle.gd -- game/data/battles/showcase.json --seeds=10
```

Record a battle as video clips (needs a display and ffmpeg; output goes to `recordings/`). The clip is the most exciting stretch of about `--seconds` (usually ending on the knockout), with hit-stop, slow motion and camera shots planned from the battle's events. `--format` is `vertical` (1080×1920, the default), `landscape` (1920×1080) or `both`; every format shows the same battle:

```bash
godot --headless --path . --script res://tools/record.gd -- game/data/battles/showcase.json --seconds=10 --format=both
```

Watch the showcase battle in a window: `godot --path .`

Run the tests:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

Preview converted models (opens a window; images go to `cache/previews/`):

```bash
godot --path . --script res://tools/preview_model.gd -- 0009_blastoise --clip=physical
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
