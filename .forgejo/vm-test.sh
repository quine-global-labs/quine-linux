#!/usr/bin/env bash
# vm-test.sh [TAG]: boots a Quine Linux live ISO on a Proxmox VM (zeus's
# VM 107, quine-live-test) and waits for it to come up. TAG is a release
# tag (v0.1.1-alpha.1: its public ISO, checked against its SHA256SUMS) or
# `latest` (the last build of main, from MinIO through a presigned link).
#
# Through Proxmox's API only, with an API token that can do no more than
# this (docs/VM_TEST.md):
#   1. stop the VM, detach the ISO, replace it with TAG's (Proxmox
#      downloads it straight from MinIO), attach it, enable the QEMU guest
#      agent's channel, start the VM. The VM must already boot from its CD
#      (ide2) first: the boot order is a disk setting in Proxmox, which the
#      token can't change (it would let it change the VM's disks too);
#   2. wait for the live system's guest agent (Fedora's qemu-guest-agent,
#      in the image) to answer, and report the OS it says it runs.
# The VM is left running, at the live desktop, for a look in its console.
#
# Environment:
#   PVE_TOKEN    required: `user@realm!tokenid=secret`
#   PVE_URL      default https://proxmox.in.coldairnetworks.com (tailnet)
#   PVE_NODE     default zeus;  VMID default 107;  PVE_STORAGE default local
#   ISO_URL      instead of working it out from TAG
#   BOOT_TIMEOUT seconds to wait for the guest agent, default 900
#   For TAG=latest: RCLONE_CONFIG_STORE_* (as iso.yml) and MINIO_BUCKET
set -euo pipefail

tag=${1:-${TAG:-latest}}
: "${PVE_TOKEN:?PVE_TOKEN is not set: a Proxmox API token, user@realm!tokenid=secret (docs/VM_TEST.md)}"
pve=${PVE_URL:-https://proxmox.in.coldairnetworks.com}/api2/json
node=${PVE_NODE:-zeus}
vmid=${VMID:-107}
storage=${PVE_STORAGE:-local}
iso=quine-linux-live-test.iso
timeout=${BOOT_TIMEOUT:-900}
bucket=${MINIO_BUCKET:-quine-linux}
public=https://s3.quineglobal.com/$bucket

log() { echo "== $*" >&2; }
api() { # METHOD PATH [curl args...]: the response's .data; fails, saying why, on an error
  local method=$1 path=$2 out code
  shift 2
  out=$(curl -sS -w '\n%{http_code}' -X "$method" -H "Authorization: PVEAPIToken=$PVE_TOKEN" "$pve$path" "$@") || return 1
  code=${out##*$'\n'}
  out=${out%$'\n'*}
  if [ "${code:0:1}" != 2 ]; then
    echo "Proxmox: $method $path: HTTP $code $(jq -r '.message // .errors // empty' <<<"$out" 2>/dev/null)" >&2
    return 1
  fi
  jq -c '.data' <<<"$out"
}
# Waits for a Proxmox task (UPID) and fails if it did.
wait_task() {
  local upid=$1 status
  while :; do
    status=$(api GET "/nodes/$node/tasks/$(jq -rn --arg u "$upid" '$u|@uri')/status")
    [ "$(jq -r .status <<<"$status")" = stopped ] && break
    sleep 3
  done
  [ "$(jq -r .exitstatus <<<"$status")" = OK ] || {
    echo "::error::Proxmox task failed: $(jq -r .exitstatus <<<"$status") ($upid)" >&2
    exit 1
  }
}

# Which ISO, and its checksum when there is one.
checksum=
if [ -n "${ISO_URL:-}" ]; then
  url=$ISO_URL
elif [ "$tag" = latest ]; then
  command -v rclone >/dev/null || { echo "::error::TAG=latest needs rclone and MinIO's credentials (or set ISO_URL)" >&2; exit 1; }
  url=$(rclone link --expire 3h "store:$bucket/live/latest/live.iso")
else
  name=quine-linux-$tag-live-x86_64.iso
  url=$public/releases/$tag/$name
  checksum=$(curl -fsS "$public/releases/$tag/SHA256SUMS" | awk -v n="$name" '$2 == n || $2 == "*"n {print $1}')
  [ -n "$checksum" ] || { echo "::error::$name isn't in $tag's SHA256SUMS" >&2; exit 1; }
fi
log "VM $vmid on $node: booting $tag"

boot=$(api GET "/nodes/$node/qemu/$vmid/config" | jq -r '.boot // ""')
case "$boot" in
  order=ide2*) ;;
  *) echo "::error::VM $vmid must boot from its CD first (boot: order=ide2;...), not '$boot'. Set it in Proxmox; the token can't (docs/VM_TEST.md)." >&2; exit 1 ;;
esac

if [ "$(api GET "/nodes/$node/qemu/$vmid/status/current" | jq -r .status)" = running ]; then
  log "stopping VM $vmid"
  wait_task "$(api POST "/nodes/$node/qemu/$vmid/status/stop" | jq -r .)"
fi

log "replacing $storage:iso/$iso"
api PUT "/nodes/$node/qemu/$vmid/config" --data-urlencode "ide2=none,media=cdrom" >/dev/null
api DELETE "/nodes/$node/storage/$storage/content/$storage:iso/$iso" >/dev/null 2>&1 || true
args=(--data-urlencode "url=$url" --data-urlencode "content=iso" --data-urlencode "filename=$iso")
[ -z "$checksum" ] || args+=(--data-urlencode "checksum=$checksum" --data-urlencode "checksum-algorithm=sha256")
wait_task "$(api POST "/nodes/$node/storage/$storage/download-url" "${args[@]}" | jq -r .)"

api PUT "/nodes/$node/qemu/$vmid/config" \
  --data-urlencode "ide2=$storage:iso/$iso,media=cdrom" \
  --data-urlencode "agent=enabled=1" >/dev/null

log "starting VM $vmid"
wait_task "$(api POST "/nodes/$node/qemu/$vmid/status/start" | jq -r .)"
started=$SECONDS

log "waiting up to ${timeout}s for the live system's guest agent"
until osinfo=$(api GET "/nodes/$node/qemu/$vmid/agent/get-osinfo" 2>/dev/null) && [ -n "$osinfo" ] && [ "$osinfo" != null ]; do
  if [ $((SECONDS - started)) -ge "$timeout" ]; then
    echo "::error::VM $vmid didn't come up in ${timeout}s: no answer from its guest agent. Look at its console in Proxmox." >&2
    exit 1
  fi
  sleep 10
done

result=$(jq -r --arg tag "$tag" --arg s "$((SECONDS - started))" '"\($tag) booted on VM '"$vmid"' in \($s)s: \(.result["pretty-name"] // .result.name) (kernel \(.result["kernel-release"]))"' <<<"$osinfo")
log "$result"
[ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "$result" >>"$GITHUB_STEP_SUMMARY"
