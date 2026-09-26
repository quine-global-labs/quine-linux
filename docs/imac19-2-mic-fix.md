# iMac19,2 internal mic: silent capture despite maxed gain

## TL;DR

The internal mic shows up normally in PipeWire/ALSA/Discord, with fully
adjustable gain controls, but captures almost nothing regardless of how high
any gain is pushed. Root cause: the CS8409 codec driver's HDA auto-config
binds the exposed capture PCM stream to the wrong ADC node, orphaning the
real internal-mic ADC entirely — its mixer controls work, but nothing is
ever routed through them. A fix for this exact bug, confirmed on a sibling
Mac model, is packaged into this repo's build (`patches/snd-hda-codec-cs8409/`)
but **not yet verified on this exact iMac19,2 hardware** — see
[Current verification status](#current-verification-status).

## Hardware / software identification

- Model: Apple iMac19,2 (2019, 21.5")
- Distro: Aurora (uBlue/Fedora Kinoite bootc image), Kinoite variant
  `44.20260908.1`
- Kernel: `7.1.8-200.fc44.x86_64`
- Audio codec: Cirrus Logic CS8409, HDA vendor id `0x10138409`, subsystem id
  `0x106b0f00` (confirmed via `/proc/asound/card0/codec#0`)
- Secure Boot: unsupported/disabled on this hardware (`mokutil --sb-state`)
  — a documented non-goal of this fix; see [Open risks](#open-risks--unknowns).

## Symptom

Mic appears as a normal PipeWire source (`Built-in Audio Analog Stereo`) and
ALSA capture device (`CS8409 Analog`, card 0). All of the following were
confirmed at 100% (or higher) with no effect on captured level:

- ALSA `Internal Mic` capture volume: 100% (63/63), unmuted
- ALSA `Internal Mic Boost`: 100% (2/2)
- PipeWire source software volume: tested at 1.0, 4.0, and 8.0 (up to +18dB)
- Discord's own in-app input-volume slider: maxed

Direct measurement, bypassing Discord and any GUI entirely, via
`pw-record --target <mic source>` / `arecord`, analyzed with
`ffmpeg -af volumedetect`:

| Gain setting | mean_volume | max_volume |
|---|---|---|
| PipeWire source @ 1.0x (100%, all ALSA gain also maxed) | -80.8 dB | -71.2 dB |
| PipeWire source @ 4.0x | -59.7 dB | -50.3 dB |
| PipeWire source @ 8.0x | -59.7 dB | -50.3 dB (uncontrolled re-test, not a true ceiling — see note below) |

The 1x → 4x jump is real, reproducible signal (matches the expected
amplification). The identical 4x/8x reading is *not* evidence of a hard
ceiling — it came from two takes that weren't spoken into with controlled,
identical volume/distance, so it's not a clean A/B. Even at its best
measured point (-50dB max), this is far too quiet for usable speech (normal
speech should peak around -12 to -6dB) — consistent with "gain is working,
but there's very little real signal to amplify in the first place."

## Ruled out, with evidence

- **Wrong/muted output device** — a real but separate issue found early on:
  the *output* sink was muted at 0% (unrelated to the mic). Fixed
  independently (`wpctl set-mute @DEFAULT_AUDIO_SINK@ 0`).
- **PipeWire/ALSA mute or wrong default device** — `wpctl status`,
  `pactl list sources`, and `amixer` all independently agreed the mic source
  was unmuted and at 100%+ from three different vantage points.
- **Discord-side gain/config** — Discord's own input-volume slider was
  already at maximum; its `settings.json` doesn't store per-account
  voice/mic settings in plaintext (those sync via Discord's own account
  storage), so this was ruled out by the maxed-slider observation rather
  than a config file.
- **The camera providing the audio instead of the codec** — `arecord -l`
  shows exactly **one** ALSA capture device (`CS8409 Analog`, card 0); the
  FaceTime HD Camera (USB `05ac:8511`) exposes no audio interface to Linux
  at all (checked via `lsusb` + absence from `arecord -l`/`arecord -L`).
- **Apple T2 chip audio routing** — ruled out: no Apple PCI bridge/T2 device
  present (`lspci -nn`), and iMac19,2 (2019 21.5") predates T2's presence in
  Macs' internal-mic path regardless.
- **Missing Flatpak/portal permission for Discord's mic access** —
  `wpctl status` showed Discord's own `WEBRTC VoiceEngine` client (verified
  by cross-referencing the sandboxed PID against the host process list) with
  an *active* capture stream connected to the real hardware node — a
  permission denial would show no connected stream at all, not merely low
  level.

## Root cause

Traced to a specific, very recent (2026-08-19) upstream bug report and fix
on a sibling Mac model:

- **Issue**: [`egorenar/snd-hda-codec-cs8409` #5, "mic input"](https://github.com/egorenar/snd-hda-codec-cs8409/issues/5)
- **Diagnostic dead-end + panic warning + D3 discovery** (2026-08-17):
  https://github.com/egorenar/snd-hda-codec-cs8409/issues/5#issuecomment-5314393975
- **Root cause + fix, confirmed working** (2026-08-19):
  https://github.com/egorenar/snd-hda-codec-cs8409/issues/5#issuecomment-5338459155
- **Fork/PR carrying Linux 6.17+ HDA API compatibility**:
  [PR #30](https://github.com/egorenar/snd-hda-codec-cs8409/pull/30),
  `daviddoll/snd-hda-codec-cs8409@kernel-6.17-hda-compat`, open/unmerged.

In `patch_cirrus_apple.h`, function `cs_8409_apple_boot_init()`, the
`SNDRV_PCM_STREAM_CAPTURE` branch only handles two cases for the capture
stream's `hinfo->nid`:

- `hinfo->nid == spec->intmike_adc_nid` — the real internal-mic ADC, set up
  correctly.
- `hinfo->nid == 0x1a` — the headset-mic node, set up correctly.

There's no fallback for when HDA auto-config lands the exposed capture PCM
stream on **neither** — e.g. landing on node `0x12`, wired to an unconfigured
external Line-In pin (`0x34`) with no physical signal path at all. When this
happens, the real internal-mic ADC (`spec->intmike_adc_nid`, `0x23` for our
subsystem-id group) has all its mixer/gain/switch controls correctly present
and adjustable — which is exactly why raising every gain control had no
effect — but is never attached to any PCM stream, so it's completely
orphaned. Confirmed on the sibling model via `journalctl -kf` during a live
`arecord` test: the internal-mic-specific prepare hook was never called,
only the generic default path ran.

Our subsystem id (`0x106b0f00`) is grouped together with the sibling model's
family (`0x106b1000`, `0x106b0f00`, `0x106b0e00`) in this same file's
`intmike_adc_nid` assignment logic — all three get `intmike_nid = 0x45`,
`intmike_adc_nid = 0x23` — matching our own kernel log
(`snd_hda_codec_cs8409 hdaudioC0D0: ... Internal Mic=0x45`). So this is a
plausible direct match, though **confirmed only on iMac18,1, not this exact
iMac19,2** — see [Open risks](#open-risks--unknowns).

On the sibling model, applying the fix took capture from -91dB pure digital
silence to a real -16.9dB mean / -0.0dB max signal.

## The fix

See [`patches/snd-hda-codec-cs8409/0001-imac19-2-force-intmike-adc-nid-fallback.patch`](../patches/snd-hda-codec-cs8409/0001-imac19-2-force-intmike-adc-nid-fallback.patch)
for the actual diff (source of truth — not duplicated here). In short: if
the capture stream's `hinfo->nid` matches neither the internal-mic ADC nor
the headset-mic node, force it onto the internal-mic ADC before the existing
setup code runs.

### A second, related issue (defensive, unconfirmed on this model)

On the sibling model, the internal-mic ADC node also came up in HDA power
state D3 (suspended) after cold boot, failing capture with an I/O error
until forced to D0 via `hda-verb ... 0x23 SET_POWER_STATE 0x0` — not
persistent across reboots. This repo includes a defensive systemd unit
(`cs8409-intmike-power-fixup.service`, running
`overlay/usr/libexec/quine-linux/cs8409-intmike-power-fixup.sh`) that logs
the power state and retries forcing D0 a few seconds after boot. **Whether
iMac19,2 actually hits this at all is unconfirmed** — its own journal output
after the real test boot is the evidence that will settle it.

## Packaging approach

The fix is built into this repo's own bootc image rather than hand-patched
live on the running system, specifically to avoid a documented panic risk
(see [Open risks](#open-risks--unknowns)) and to get free, cheap rollback via
`bootc rollback`/`rpm-ostree rollback` if anything goes wrong.

- `patches/snd-hda-codec-cs8409/vendor/` — a verbatim copy of the 16 files
  from the pinned upstream commit (`daviddoll/snd-hda-codec-cs8409` @
  `14e00de4290e090afd7632bc6d5c724131a19e7b`), vendored rather than fetched
  at build time because this is an unmerged personal-fork branch that could
  be force-pushed or deleted with no notice. See
  [`PROVENANCE.md`](../patches/snd-hda-codec-cs8409/PROVENANCE.md) for the
  full origin/license/rationale writeup (license: `GPL-2.0-or-later`, one
  file `GPL-2.0-only`, per each file's own original SPDX header).
- `patches/snd-hda-codec-cs8409/0001-imac19-2-force-intmike-adc-nid-fallback.patch` —
  the actual functional change, kept separate from the vendored copy so it's
  easy to re-diff if/when PR #30 lands upstream and this vendoring can be
  dropped.
- `Containerfile` — a new `kmod-builder` stage installs kernel headers
  matching the exact kernel shipped in the `aurora:stable` base image
  (pinned by digest, shared between both stages via a single `ARG`, so they
  can't drift apart), applies the patch, and builds the module with the
  vendored `Makefile`. The final stage copies the resulting `.ko` into
  `/usr/lib/modules/<kernel-version>/extra/` (the same convention Fedora's
  own `kmod-*` subpackages use to override an in-tree module of the same
  name/modalias — no blacklisting or renaming needed) and re-runs `depmod`
  against the final image's own module tree.
- DKMS was deliberately **not** used: it exists to rebuild modules at
  boot/install time when a kernel updates later on a mutable host. On this
  bootc image, a new kernel only ever arrives bundled inside a freshly built
  image, at which point the `kmod-builder` stage reruns from scratch anyway
  — DKMS's rebuild-on-boot machinery is redundant weight here.

## Current verification status

**Not yet tested on real hardware as of 2026-09-26.** The patch has been
verified to apply cleanly (`git apply --check`) and produce the intended
diff against the vendored source. The Containerfile has been written and a
local `podman build` sanity check (module compiles, `vermagic` matches the
target kernel) is the next step. Actually switching this machine to boot the
built image (`bootc switch`/`rpm-ostree rebase` + reboot) is a separate,
explicitly confirmed step, not yet taken, given this hardware/kernel/fix
combination is entirely unverified. This section will be updated with real
results (measured dB, Discord input-meter behavior, and whether the D3
power-state unit actually fired) once that test happens.

## Open risks / unknowns

- **Kernel API mismatch risk**: the vendored fork targets Linux 6.17+ HDA
  API; our kernel is 7.1.8. Untested whether it compiles cleanly without
  further porting — but this fails safely at `podman build` time, before
  ever touching the running system.
- **Unconfirmed on this exact model**: the fix is confirmed only on
  iMac18,1, not this iMac19,2/subsystem-id combination, even though the
  `intmike_adc_nid` code path is shared across both per direct source
  inspection.
- **D3 power-state issue unconfirmed on this model** — only confirmed on the
  sibling; the defensive unit's journal is the intended way to settle this.
- **Module search-path precedence** (`extra/` overriding in-tree
  `kernel/...`) is asserted from documented Fedora/kmod convention, not yet
  verified on this image — check `modinfo -F filename
  snd_hda_codec_cs8409` after the real test boot.
- **Live-unbind panic risk**: a live `unbind`/`rmmod`/`modprobe`/`bind` cycle
  of this module while PipeWire has the sink active caused an unrecoverable
  freeze on the sibling model. This is exactly why all testing here goes
  through a full image build + reboot, never a live module reload.
- **Secure Boot non-goal**: this approach assumes Secure Boot stays
  disabled on this hardware. If it's ever enabled, this entire approach
  breaks (an unsigned out-of-tree `.ko` gets rejected at load) and would
  need MOK enrollment + module signing added to the builder stage.
- **Personal-fork provenance risk**: the ultimate origin of the 6.17+
  compatibility work is an unmerged personal-fork PR (#30). Vendoring
  mitigates the "it could disappear" risk but doesn't change that this
  hasn't gone through upstream review.
- `quine-linux`'s own `rpm-ostree-cleanup.timer` prunes the rollback
  deployment weekly — worth being aware of before testing an unverified
  change on this hardware, though no action has been taken on this yet.

## References

- https://github.com/egorenar/snd-hda-codec-cs8409/issues/5
- https://github.com/egorenar/snd-hda-codec-cs8409/issues/5#issuecomment-5314393975
- https://github.com/egorenar/snd-hda-codec-cs8409/issues/5#issuecomment-5338459155
- https://github.com/egorenar/snd-hda-codec-cs8409/pull/30
- https://github.com/daviddoll/snd-hda-codec-cs8409/tree/kernel-6.17-hda-compat
- https://github.com/rojoxstar/imac19-2-cs8409-linux (iMac19,2-specific
  project; primarily speaker/playback and Apple-DSP research, explicitly
  does not claim mic-capture support — investigated and set aside in favor
  of the fix above, which directly targets the observed symptom)
