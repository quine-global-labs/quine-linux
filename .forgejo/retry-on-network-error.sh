#!/usr/bin/env bash
# retry-on-network-error.sh COMMAND...: runs COMMAND, and if it fails with
# what looks like a dropped connection (any fetch: git, curl, dnf, npm,
# podman pulls), or hangs, runs it again, up to RETRIES times in all
# (default 3), RETRY_DELAY seconds apart (default 60). Any other failure
# fails at once.
#
# A hang is STALL_TIMEOUT seconds (default 1800) without a line of output:
# a fetch that stops mid-transfer without failing (run 64: a pull sat for
# three hours). The command's whole process group is killed, and it counts
# as a network error.
#
# Retrying a whole build is cheap: podman keeps each finished layer, and
# task skips tasks whose sources haven't changed, so a retry picks up at
# the step that broke. (Run 64: one dropped GitHub fetch, three hours in,
# failed the amd64 job.)
set -uo pipefail

retries=${RETRIES:-3}
delay=${RETRY_DELAY:-60}
stall=${STALL_TIMEOUT:-1800}

# Messages that mean the network failed, not the build.
pattern='RPC failed|early EOF|unexpected disconnect|Connection (reset|refused|timed out)|connection reset by peer|Could not resolve host|Temporary failure in name resolution|TLS handshake timeout|i/o timeout|unexpected EOF|Operation timed out|timed out after|curl: \((6|7|18|28|35|52|56|92)\)|HTTP error 50[234]|returned error: 50[234]|50[234] (Bad Gateway|Service Unavailable|Gateway Time-?out)|ECONNRESET|ETIMEDOUT|EAI_AGAIN|socket hang up|Curl error \((6|7|18|28|35|52|56)\)'

log=$(mktemp)
trap 'rm -f "$log"' EXIT

# Runs "$@" in its own process group with its output going to the job log
# and $log; kills the group after $stall seconds of silence. Returns the
# command's status, or 124 for a stall.
run_watched() {
  : >"$log"
  setsid bash -c '"$@" 2>&1 | tee "$0"; exit "${PIPESTATUS[0]}"' "$log" "$@" &
  local pid=$! last size=0 now
  last=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    sleep 15
    now=$(stat -c %s "$log" 2>/dev/null || echo 0)
    if [ "$now" != "$size" ]; then
      size=$now last=$SECONDS
    elif [ $((SECONDS - last)) -ge "$stall" ]; then
      echo "::warning::no output for ${stall}s: killing $*"
      kill -TERM -- "-$pid" 2>/dev/null
      sleep 30
      kill -KILL -- "-$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
  done
  wait "$pid"
}

for attempt in $(seq 1 "$retries"); do
  run_watched "$@"
  status=$?
  [ "$status" -ne 0 ] || exit 0
  # A stall, or a network error at the end of the output: a fetch that
  # failed and was retried successfully earlier in the build doesn't count.
  if [ "$status" -ne 124 ] && ! tail -n 200 "$log" | grep -qE "$pattern"; then
    exit "$status"
  fi
  if [ "$attempt" -lt "$retries" ]; then
    echo "::warning::network error or stall (attempt $attempt of $retries); retrying in ${delay}s: $*"
    tail -n 200 "$log" | grep -E "$pattern" | tail -3
    sleep "$delay"
  fi
done
echo "::error::still failing with a network error or stall after $retries attempts: $*"
exit "$status"
