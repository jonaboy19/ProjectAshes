# licensed_local: Sonniss GDC bundle sounds (local only, never committed)

Everything in this folder except this README is ignored by git (`.gitignore`). The repository is public, and the
licence for these sounds forbids redistributing the raw files.

- **Source:** the Sonniss #GameAudioGDC bundles 2015-2019, taken from the official mirror `ftpmirror.your.org/pub/misc/sonniss*/`
  listed on https://sonniss.com/gameaudiogdc. Only selected files were extracted from the zips, using HTTP range reads.
  Downloads live outside the repo in `Documents/ProjectAshes_art_staging/downloads/audio/sonniss/`, with `picked.json`
  listing each file's bundle part and library.
- **Licence:** https://sonniss.com/gdc-bundle-license/ (version 2.0, effective 27 August 2026; the bundle page and
  `License_2018.pdf` in the staging folder state the same terms). Commercial use in games is allowed, with no attribution required.
- **Not allowed:**
  - **No redistribution** of the sounds as sound effects. That covers the original files and edited or re-designed versions,
    so these `.ogg` files must never be pushed, attached to an issue, or shared outside the team.
    Shipping them inside the exported game is allowed.
  - **No AI or ML training** on these sounds.
- **Build:** `py tools/audio/build_licensed.py` reads the staging WAVs, then trims, slices, makes loops and loudness-matches
  them to the same targets as `tools/audio/build_audio.py`. It writes the OGG files here.
- **Runtime:** `scripts/audio/audio_director.gd` indexes this folder like the rest of `assets/audio`. A sound name with
  files here drops its CC0 variants (`_prefer_licensed`), and an ambience bed with the same name overrides the CC0 bed.
  A clone without this folder plays the CC0 set, so nothing breaks.
