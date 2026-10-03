# Resurgence for CoD: Ghosts (IW6)

Warzone-style Resurgence as a server-side GSC mod, layered on free-for-all.

- Design: [docs/superpowers/specs/2026-10-02-resurgence-design.md](docs/superpowers/specs/2026-10-02-resurgence-design.md)
- Sources: `src/data/` mirrors the game's `data/` layout
- Deploy: `./deploy.sh` — **not written yet**; overrides the install path with `GHOSTS_DIR=...`

Nothing is implemented yet — the repo currently holds the design only.

Once built, enable in the server config:

    g_gametype dm
    scr_friendlyfire 0
    scr_resurgence_enabled 1
