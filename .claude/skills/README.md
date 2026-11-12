# Agent skills

Claude Code project skills, copied unchanged from [mattpocock/skills](https://github.com/mattpocock/skills) at commit `5863806dd4e15c63174bee4e7515a4256792ecfa` (MIT, see `LICENSE-mattpocock-skills`). The Codex-only `agents/openai.yaml` files are left out.

| Skill | Invoked by | Use |
| --- | --- | --- |
| `grill-with-docs` | you | Design interview that records terms in `GLOSSARY.md` and decisions in `docs/adr/` |
| `grill-me` | you | The same interview, without writing docs |
| `grilling` | you or Claude | The interview loop the two above run |
| `domain-modeling` | you or Claude | Sharpen domain terms, maintain `GLOSSARY.md` and ADRs |
| `tdd` | you or Claude | Red-green loop at agreed seams, against `tests/run_tests.gd` |
| `diagnosing-bugs` | you or Claude | Build a failing loop first, then hypothesise, fix and add a regression test |
| `codebase-design` | you or Claude | Deep-module vocabulary: module, interface, seam, depth |
| `improve-codebase-architecture` | you | Survey recently changed code for deepening candidates |
| `research` | you or Claude | Background agent writes a cited Markdown note |
| `retro` | you | Suggest improvements to the agent environment after a session |
| `writing-for-agents` | you or Claude | Style guide for skills and `CLAUDE.md` |
| `wait-what` | you | Ask for the last message again in plain English |
| `handoff` | you | Write a handoff document to the OS temp directory |

Upstream `code-review`, `implement` and the issue-tracker skills are left out: `code-review` clashes with the built-in `/code-review`, and the others assume a different commit and branch workflow. To update, copy the newer upstream folders over these and bump the commit above.
