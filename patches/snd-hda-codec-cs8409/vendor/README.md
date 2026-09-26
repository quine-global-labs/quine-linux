# snd-hda-codec-cs8409 (out-of-tree)

Out-of-tree Linux kernel module for the **Cirrus Logic CS8409** HD Audio bridge and related fixups (including **Apple** machine quirks). It mirrors the in-kernel ALSA HDA codec driver logic but can be built and updated without rebuilding the whole kernel.

## Requirements

- Linux kernel headers for the kernel you are running  
  (e.g. on Debian/Ubuntu/Pop!_OS: `linux-headers-$(uname -r)`)
- Toolchain able to build external modules (`gcc`, `make`, etc.)
- Build from a shell where `uname -r` matches the target kernel (or set `KVER` — see below)

## Build

Always build **from this directory** using the provided `Makefile` so module C flags are applied correctly:

```bash
cd /path/to/snd-hda-codec-cs8409
make
```

Do **not** run only:

```text
make -C /lib/modules/$(uname -r)/build M=$(pwd) modules
```

without passing the same `CFLAGS_MODULE` values as in the `Makefile` `all:` recipe. The Makefile sets defines such as `APPLE_CODECS` and `CONFIG_SND_HDA_RECONFIG` that this tree expects.

### Optional: build for another installed kernel

```bash
make KVER=6.18.7-76061807-generic
```

(Use the directory name under `/lib/modules/` for that kernel.)

### Install module into `updates/` (takes precedence over in-tree module)

```bash
sudo make install
sudo depmod -a   # install target runs depmod; repeat if you copy the .ko manually
```

Reload the audio stack or reboot as appropriate on your distribution (e.g. unload/reload `snd-hda-intel` and related modules, or reboot).

## Kernel compatibility

Recent work in this repository targets **modern kernels (6.17+)** where the ALSA HDA stack uses:

- `struct hda_codec_driver` with `probe` / `remove` instead of the old `codec->patch_ops` / `.free` callbacks
- `snd_hda_gen_remove()` instead of the former `snd_hda_gen_free()` export (a compatibility wrapper in `hda_generic.h` maps the old name for this module)

The module has been verified to build and run on **6.18.x** (e.g. Pop!_OS). Older kernels may still work if the symbols and APIs match; if not, use a branch or commit intended for that era.

## Tested on

| Environment | Kernel | Notes |
|-------------|--------|--------|
| **Pop!_OS** | `6.18.7-76061807-generic` | `make` and `sudo make install` succeed; audio confirmed working after reload/reboot as needed on the test machine. |

Always install **kernel headers** that match your running kernel (`linux-headers-$(uname -r)` on Debian-based systems).

## Development

The **entire set of changes** in this repository as published here—the **kernel 6.17+ HDA API port** (`hda_codec_driver`, variant ops, `snd_hda_gen_remove` compatibility), **Makefile** / **`.gitignore`** updates, **README**, and related integration—was **written and iterated using [Cursor](https://cursor.com)** (AI-assisted editor). The CS8409 codec logic and Apple extensions remain **derived from Cirrus Logic and the Linux ALSA HDA codebase**; original **SPDX** and **copyright** lines in the source files still apply.

## Configuration flags (Makefile)

`KBUILD_EXTRA_CFLAGS` enables, among other things:

- `APPLE_CODECS` — Apple-specific paths in `patch_cirrus_apple.h`
- `APPLE_PINSENSE_FIXUP`
- `CONFIG_SND_HDA_RECONFIG`

A debug-oriented line is commented out in the `Makefile` (extra logging defines).

## License

The sources are under **GPL-2.0-or-later** (see SPDX headers in the individual files). This tree includes code attributed to Cirrus Logic and Takashi Iwai / the ALSA project, consistent with the upstream HDA codec drivers.

## Troubleshooting

| Issue | What to check |
|--------|----------------|
| `No rule to make target .../build` | Install kernel headers for `uname -r`. |
| Many errors about missing `cs8409_spec` fields | Build with this repo’s `make` (see above), not bare kbuild without `CFLAGS_MODULE`. |
| `modpost: "snd_hda_gen_free" undefined` | Use a tree that includes the `hda_generic.h` wrapper for `snd_hda_gen_remove` (kernel **≥ 6.17**). |
| Compiler differs from kernel | Usually a warning only; same major `gcc` as the distro kernel is ideal. |

## Contributing

Pull requests and reports against specific **kernel version** and **hardware** (PCI subsystem ID, machine model) help keep this module useful for others.
