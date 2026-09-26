#!/bin/bash
# Forces the CS8409 internal-mic ADC (nid 0x23 on iMac19,2/18,x-family
# subsystem ids) out of D3 power state on boot. See
# docs/imac19-2-mic-fix.md in the quine-linux repo for the full story.
#
# Confirmed needed on a sibling model (iMac18,1); unconfirmed on iMac19,2.
# This logs the power state on every attempt, so the journal for this unit
# is the evidence for whether this model needs it at all. Always exits 0 --
# this is a best-effort defensive fixup, not something that should fail boot.
set -u

dev=/dev/snd/hwC0D0
nid=0x23

log() { echo "cs8409-intmike-power-fixup: $*"; }

log "initial state: $(hda-verb "$dev" "$nid" GET_POWER_STATE 0x0 2>&1 | tail -1)"

for i in $(seq 1 10); do
	hda-verb "$dev" "$nid" SET_POWER_STATE 0x0 >/dev/null 2>&1
	sleep 1
	state="$(hda-verb "$dev" "$nid" GET_POWER_STATE 0x0 2>&1 | tail -1)"
	log "attempt $i state: $state"
	case "$state" in
	*0x0*) log "reached D0 after $i attempt(s)"; exit 0 ;;
	esac
done

log "gave up after 10 attempts, last state: $state"
exit 0
