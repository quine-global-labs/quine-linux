#!/usr/bin/env bash
# Copies upstream images into this forge's registry, as
# forge.in.quineglobal.com/quine-global-labs/mirror/<registry>/<path>,
# which the runners' registries.conf tries before the upstream registry
# (petersweb-infra, nixos/forgejo-runner.nix). So builds pull from
# the forge, and still build from yesterday's copy when upstream is down.
#
# Usage: vendor-images.sh REF...   (registry-qualified, e.g.
# quay.io/fedora/fedora-bootc:rawhide, or name:tag@sha256:...)
#
# Needs a `podman login` to the forge first. Best effort: an image that
# can't be copied is a warning, not a failure; the build then gets the
# mirror's last copy, or upstream's.
set -uo pipefail

mirror=${MIRROR:-forge.in.quineglobal.com/quine-global-labs/mirror}
# Read from upstream itself, not from the mirror registries.conf points at.
# The flag, not CONTAINERS_REGISTRIES_CONF: podman and buildah read that
# variable, but skopeo never has. Until 2026-11-03 this exported it, skopeo
# read the mirror, and every run copied the mirror onto itself, so tags
# stayed at their first copy. (runner-x86-linux's skopeo now honors the
# variable too; petersweb-infra, hosts/runner-x86-linux.)
skopeo() { command skopeo --registries-conf /dev/null "$@"; }

for ref in "$@"; do
  src="docker://$ref"
  dest="docker://$mirror/$ref"
  # Every architecture: the x86_64 and the aarch64 runner vendor the same
  # tags, and one architecture's copy would replace the other's.
  opts=(--multi-arch all)
  if [[ $ref == *@sha256:* ]]; then
    # Pinned by digest: copy the whole index unchanged, so the digest the
    # build asks for exists on the mirror. skopeo refuses a reference with
    # both a tag and a digest, so read by digest and write by tag.
    name=${ref%@*}
    src="docker://${name%:*}@${ref#*@}"
    dest="docker://$mirror/$name"
    opts=(--multi-arch all --preserve-digests)
  fi
  echo "::group::$ref"
  # Layers already on the mirror aren't downloaded again.
  skopeo copy --retry-times 5 "${opts[@]}" "$src" "$dest" ||
    echo "::warning::couldn't vendor $ref; builds get the mirror's last copy, or upstream's"
  echo "::endgroup::"
done
