# Cobbleseum

A local-first 3D Pokémon battle game built with Godot 4. Two Pokémon fight in real time in a small arena, rendered with Cobblemon's models and animations and driven by Pokémon Showdown's data. Battles can be player-vs-AI or AI-vs-AI, AI-vs-AI battles can be recorded as vertical 1080×1920 clips, and many simulated battles will feed a local ranking.

The repository contains only original code and data. Third-party assets are downloaded into a local, git-ignored cache and never committed.

Status: early development. See the [concept brief](concepts_brief.md).

## Getting started

Prerequisites:

- [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) (standard build, not .NET). Put it on your `PATH` as `godot`, or substitute its full path below.
- Node.js 20 or later, for the asset pipeline's Showdown data export (coming in milestone 1).
- ffmpeg, for encoding recorded clips to MP4 (coming in milestone 1).

Run the tests:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

Check that no third-party assets are tracked:

```bash
tools/check_no_assets.sh
```

## Architecture

The design is described in the [concept brief](concepts_brief.md). In short:

- An asset pipeline fetches pinned releases of Showdown's data and Cobblemon's jar, verifies them by SHA-256, and converts Cobblemon's Bedrock models into Godot scenes in `cache/`.
- A deterministic, fixed-tick battle simulation written in plain GDScript runs headless for batch simulation and drives the 3D presentation.
- A utility AI controls fighters through the same intents a player uses.
- Godot's Movie Maker mode records clips; ffmpeg encodes them.

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
