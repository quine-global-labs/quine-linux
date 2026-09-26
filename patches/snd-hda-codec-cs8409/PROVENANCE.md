# Provenance: vendored `snd-hda-codec-cs8409` source

## Origin

- Upstream project: [`egorenar/snd-hda-codec-cs8409`](https://github.com/egorenar/snd-hda-codec-cs8409)
  (out-of-tree Linux HDA codec driver adding Apple Cirrus CS8409/CS42L42/CS42L83
  support beyond what's in mainline).
- Actual source vendored here comes from a fork/branch with Linux 6.17+ HDA
  API compatibility work, not yet merged upstream:
  [`daviddoll/snd-hda-codec-cs8409`](https://github.com/daviddoll/snd-hda-codec-cs8409),
  branch `kernel-6.17-hda-compat`, submitted as
  [PR #30](https://github.com/egorenar/snd-hda-codec-cs8409/pull/30)
  ("Port out-of-tree CS8409 driver for Linux 6.17+ HDA API") — open, unmerged
  as of the date below.
- **Pinned commit:** `14e00de4290e090afd7632bc6d5c724131a19e7b`
  (2026-04-04, "Port for Linux 6.17+ HDA codec API and modpost fixes").
- **Date vendored:** 2026-09-26.

## Why vendored instead of fetched at build time

This is an unmerged personal-fork branch, not a stable upstream release —
it can be force-pushed, renamed, or deleted with no notice. Vendoring a
verbatim copy here (original SPDX headers untouched) makes the quine-linux
build offline-capable, immune to that repo's fate, and keeps the
corresponding source actually present in this repo's own git history
alongside the binary it produces, which is the most direct way to satisfy
GPL-2.0-or-later's source-availability obligation.

## What's in `vendor/`

All 16 files from the pinned commit, unmodified:

```
Makefile, README.md, .gitignore,
hda_auto_parser.h, hda_generic.h, hda_jack.h, hda_local.h,
patch_cirrus_apple.h, patch_cirrus_boot84.h, patch_cirrus_hda_generic_copy.h,
patch_cirrus_new84.h, patch_cirrus_real84.h, patch_cirrus_real84_i2c.h,
patch_cs8409-tables.c, patch_cs8409.c, patch_cs8409.h
```

## License

`GPL-2.0-or-later` (verified directly from the SPDX headers present in the
vendored files, e.g. `patch_cs8409.c`, `patch_cirrus_apple.h`,
`patch_cs8409.h`, `hda_generic.h`). One file, `patch_cs8409-tables.c`, carries
`GPL-2.0-only` specifically — the combined work is distributed here under
`GPL-2.0-or-later` for the files that specify it, and `GPL-2.0-only` for that
one file, matching each file's own original header.

## Our changes

The actual functional fix lives as a separate patch, applied on top of this
vendored tree at image-build time, not folded into the vendored copy:

- `0001-imac19-2-force-intmike-adc-nid-fallback.patch` — see
  `../../docs/imac19-2-mic-fix.md` for the full root-cause writeup.

Keeping "what upstream wrote" (this directory) and "what we changed" (the
`.patch` file) separate makes it trivial to re-diff against a future upstream
merge of PR #30, and to drop this vendoring entirely once/if that lands.
