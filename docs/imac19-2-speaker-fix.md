# iMac19,2 internal speakers: no sound on playback

## TL;DR

Built-in speaker playback produces no audible sound at all, even though the
HDA plumbing looks correct at every layer PipeWire/ALSA can see (unmuted
volume, un-muted output pin, clean `speaker-test` device open). Root cause
(via sibling-model research, not yet confirmed on this exact iMac19,2):
audio on this hardware doesn't go straight from the CS8409's internal DAC to
the speakers — it's relayed through external Texas Instruments **TAS5764L**
speaker-amplifier chips over I2C, and a Cirrus **CS42L83** companion codec,
neither of which the in-tree (or our currently-vendored) driver ever
initializes. The DAC happily outputs a signal; nothing downstream ever
brings the amps out of reset to play it. **No patch has been written or
applied for this repo yet** — this doc captures the investigation and the
most promising existing prior art. See
[Current verification status](#current-verification-status).

## Hardware / software identification

- Model: Apple iMac19,2 (2019, 21.5")
- Distro: Aurora (uBlue/Fedora Kinoite bootc image), Kinoite variant
  `44.20260908.1`
- Kernel: `7.1.8-200.fc44.x86_64` — **stock/in-tree** `snd_hda_codec_cs8409`
  (`/lib/modules/.../kernel/sound/hda/codecs/cirrus/snd-hda-codec-cs8409.ko.xz`).
  This machine has **not yet been switched** to this repo's own patched
  image — the mic fix in
  [`docs/imac19-2-mic-fix.md`](imac19-2-mic-fix.md) is also still unverified
  on real hardware as of that doc's last update. So whatever's happening
  here is a pre-existing quirk in the stock driver, unrelated to our own mic
  patch.
- Audio codec: Cirrus Logic CS8409, HDA vendor id `0x10138409`, subsystem id
  `0x106b0f00` (same subsystem-id family the mic-fix doc groups with
  iMac18,1/iMac18,x).

## Symptom

No audible sound from the built-in speakers under any output. Checked:

- `wpctl status` — sink `Built-in Audio Analog Stereo` present, unmuted,
  volume 0.92–1.00, not the wrong default device.
- `amixer -c0 contents` — `PCM Playback Volume` at `245/255` (~-1dB from
  max), unmuted (`mute=0` reported, no explicit mute switch present at all
  for this control).
- `speaker-test -c2 -twav` opens the ALSA device and runs cleanly (no
  `-16 Device or resource busy`, no `-19 No such device`, no other open/setup
  error) — the kernel driver accepts the stream without complaint.

## Ruled out, with evidence

- **Wrong/muted PipeWire sink** — `wpctl status` shows the correct sink
  selected and unmuted; this is a separate, already-known-good check from
  the mic doc's own investigation (that doc independently found and fixed an
  unrelated muted-sink issue on the same class of hardware).
- **ALSA-level mute or zero volume** — `PCM Playback Volume` is at 245/255;
  there is no separate `Speaker Playback Volume`/`Switch` control at all
  (only `PCM`, `Mic`, `Internal Mic`, `Internal Mic Boost` exist per
  `amixer -c0 scontrols`), so there's no separate speaker-path mute to check
  — consistent with the codec not exposing an amp-capable mixer control on
  this path at all (see [Root cause](#root-cause)).
- **HDA pin disabled** — `/proc/asound/card0/codec#0`, Node `0x24`/`0x25`
  (`Pin Complex`, `[Fixed] Speaker at Int`, `DefAssociation=0x1`,
  `Sequence=0x0`/`0x1`) both show `Pin-ctls: 0x40: OUT` — output enabled at
  the pin level, not disabled.
- **Stream open failure** — `speaker-test` opens and runs without any ALSA
  error; this isn't a "device doesn't exist"/"busy" failure.
- **Kernel panic or crash on the audio path** — `dmesg`/`journalctl -k`
  weren't reachable as this user (`dmesg_restrict=1`, no passwordless sudo
  available in this session) so this wasn't directly checked; nothing else
  observed (no hang, no dropped SSH/session) is consistent with a crash
  either way. Worth checking with root access before further work.

## Root cause

Not confirmed on this exact machine yet, but strongly indicated by prior art
on sibling Apple CS8409 hardware:

- **Companion hardware, not a simple codec quirk**: per
  [`rojoxstar/imac19-2-cs8409-linux`](https://github.com/rojoxstar/imac19-2-cs8409-linux)
  (already referenced-and-shelved in the mic-fix doc), this exact 2019
  iMac's internal speakers are driven by **four TI TAS5764L amplifier
  chips** plus a **Cirrus CS42L83** companion codec sitting behind the
  CS8409 — not a direct CS8409-DAC-to-speaker path. That project reports
  getting internal speakers "audible on both sides at 44.1 kHz" on Ubuntu
  with kernel `7.0.0-31-generic`, after amplifier-specific bring-up work,
  and explicitly warns: **"Never try speculative TAS gain writes, including
  `0xCF`, on the speakers"** — i.e. wrong register writes to these chips are
  a real-hardware-damage risk, not just a "no sound" risk.
- **Closer, Fedora-specific precedent**:
  [`egorenar/snd-hda-codec-cs8409` issue #31](https://github.com/egorenar/snd-hda-codec-cs8409/issues/31),
  "iMac18,3 built-in speakers working on Fedora 43 / kernel 6.19.12 with
  additional TAS576 initialization" (iMac18,3 = 2017 27" 5K iMac, PCI
  subsystem `0x106b1000` — same subsystem-id family the mic doc already
  groups with our `0x106b0f00`). Root cause as described there: the speaker
  path needs additional **TAS576 boot/reset initialization** that's simply
  missing from the stock driver, and separately, code that cleared speaker
  DACs `0x02`/`0x03` during cleanup was *losing* an already-working speaker
  state.
  - The actual patch for that report lives in a follow-on repo,
    [`network-garden-lab/imac18-3-cs8409-fedora-speaker-patch`](https://github.com/network-garden-lab/imac18-3-cs8409-fedora-speaker-patch)
    (Fedora-specific, two patch variants for kernel `6.19.12` and
    `7.0.12-201.fc44.x86_64` — the latter within one Fedora point release of
    our own `7.1.8-200.fc44.x86_64`). Unlike the mic fix's vendored
    out-of-tree module, **this is a ~1100-line patch against the in-tree
    kernel source itself**
    (`sound/hda/codecs/cirrus/cs8409{.c,.h}` and `cs8409-tables.c`), adding
    (among others) `imac_tas576_boot_reset_setup()`,
    `imac_tas576_tdm_slot_setup()`, `imac_cs42l83_reset()` /
    `imac_cs42l83_inithw()`, and a new `CS8409_FIXUP_IMAC_AMP` PCI-quirk
    fixup keyed off subsystem id `0x106b1000` specifically (iMac18,3's id,
    not ours) — using the TAS576 family at I2C addresses `0xd8/0xda/0xdc/0xde`
    and the CS42L83 at `0x90`.
  - Its own README calls this "experimental, single-machine tested" and
    "a working result and investigation record, not a complete or
    upstream-ready solution," and separately warns that changing the sound
    profile in desktop sound settings mid-session "may temporarily disturb
    or break playback... playback may resume with unexpectedly loud noise."
- **What this doesn't explain yet**: neither prior-art project confirms the
  *exact* iMac19,2 / subsystem `0x106b0f00` combination — the closest
  confirmed case is iMac18,3 (`0x106b1000`, 27" 5K, likely 2-way stereo amp
  layout) and rojoxstar's own iMac19,2 work (4x TAS5764L). Whether our
  specific board has 2 or 4 TAS5764L chips, and at which I2C addresses, is
  unconfirmed — this needs an actual I2C bus scan on this machine, not
  assumed from either project.

## The fix

**Not yet written or applied.** No patch exists in this repo for this issue.
The most promising starting point is adapting
`network-garden-lab/imac18-3-cs8409-fedora-speaker-patch`'s
`imac18-3-cs8409-speaker-fedora-7.0.12.patch` (closest Fedora kernel match)
to our subsystem id and kernel `7.1.8-200.fc44.x86_64`, following the same
sibling-model-adaptation approach the mic fix already used successfully.

This is **not** something to attempt as a quick live edit:

- It patches core in-tree kernel HDA source, not a leaf out-of-tree module —
  a materially bigger lift than the mic fix's `kmod-builder` stage. It would
  need either a full kernel rebuild or repackaging the same functional
  change as an out-of-tree replacement module (mirroring how the mic fix's
  `patches/snd-hda-codec-cs8409/` is built and installed into
  `/usr/lib/modules/<kver>/extra/` to override the in-tree one — see
  [`docs/imac19-2-mic-fix.md`](imac19-2-mic-fix.md#packaging-approach)).
- It writes directly to amplifier-chip registers over I2C. Per the
  rojoxstar project's explicit warning, a wrong write here risks damaging
  the physical speaker hardware, not just producing no sound or a kernel
  warning — this needs real care re-deriving/checking register values
  against our actual chip revision before any write is attempted on this
  machine, not a copy-paste of another model's values.
- Precisely because of that, this should go through this repo's same
  build-image-then-`bootc switch`-then-reboot discipline as the mic fix
  (never a live `modprobe`/register-poke on the running system), and
  ideally should not even reach that stage until the I2C topology on our
  exact board is confirmed to match one of the two prior-art cases above.

## Current verification status

**Investigation only, as of 2026-09-29.** Ruled out the simple
mute/volume/pin-disabled explanations directly on this hardware (see
[Ruled out](#ruled-out-with-evidence)). Identified two independent pieces of
sibling-model prior art pointing at the same TAS5764L/TAS576 +
CS42L83 amplifier-bring-up root cause, with one Fedora-specific patch
(`network-garden-lab/imac18-3-cs8409-fedora-speaker-patch`) close enough in
kernel version to be a realistic starting point. Nothing has been vendored,
patched, or built yet. Next steps, in order:

1. Get root/sudo access on this machine and pull `dmesg`/`journalctl -k`
   around a `speaker-test` run, to see whether the stock driver logs
   anything about the amp/companion-codec path (the mic fix's own
   discovery process relied heavily on this kind of kernel-log evidence).
2. Scan the I2C bus for TAS5764L/CS42L83 addresses actually present on this
   board (2 vs 4 amps, and their real addresses) rather than assuming either
   prior-art project's numbers apply unmodified.
3. Only then evaluate adapting the `7.0.12-201.fc44.x86_64` patch, following
   the same vendor-and-patch-separately discipline as
   `patches/snd-hda-codec-cs8409/`.

## Open risks / unknowns

- **Unconfirmed on this exact model**: closest confirmed cases are
  iMac18,3 (patch exists, Fedora, close kernel match, different subsystem
  id) and rojoxstar's own iMac19,2 work (matching model, but Ubuntu-based,
  driver internals not yet compared line-by-line against the Fedora patch).
- **Real hardware-damage risk**: explicit upstream warning against
  speculative amp register writes on these speaker amps — this is not a
  "worst case is silence" fix like the mic one.
- **Packaging is a bigger lift than the mic fix**: in-tree kernel source
  patch vs. a leaf out-of-tree module; needs a build-pipeline decision
  before any code is written (full kernel rebuild vs. out-of-tree
  replacement module).
- **Playback-instability warning from the patch author**: changing sound
  profile/configuration mid-session reportedly can cause temporary
  loud/broken playback on iMac18,3 with this patch applied — unknown
  whether that's specific to that patch's implementation or a
  hardware-level behavior that would recur here too.
- **Root access needed**: this investigation stopped at what a non-root
  session could observe (`dmesg`/`journalctl -k` were inaccessible here).
- **Apple DSP / authenticated macOS SSV work in `rojoxstar`'s repo is a
  distinct, unrelated blocker** (`docs/apple-dsp/CURRENT-BLOCKER.md` in that
  repo, gated on an authenticated macOS Sequoia 24G90 install image) — that
  applies to advanced Apple-specific DSP/EQ features, not basic playback,
  and should not be confused with what's blocking sound here.

## References

- https://github.com/rojoxstar/imac19-2-cs8409-linux
- https://github.com/egorenar/snd-hda-codec-cs8409/issues/31
- https://github.com/network-garden-lab/imac18-3-cs8409-fedora-speaker-patch
- [`docs/imac19-2-mic-fix.md`](imac19-2-mic-fix.md) — sibling-model
  subsystem-id grouping and the vendor-and-patch-separately packaging
  precedent this doc leans on.
