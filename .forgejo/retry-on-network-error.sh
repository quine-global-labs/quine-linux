#!/usr/bin/env bash
# retry-on-network-error.sh COMMAND...: runs COMMAND, and if it fails with
# what looks like a dropped connection (any fetch: git, curl, dnf, npm,
# podman pulls), runs it again, up to RETRIES times in all (default 3),
# RETRY_DELAY seconds apart (default 60). Any other failure fails at once.
#
# Retrying a whole build is cheap: podman keeps each finished layer, and
# task skips tasks whose sources haven't changed, so a retry picks up at
# the step that broke. (Run 64: one dropped GitHub fetch, three hours in,
# failed the amd64 job.)
set -uo pipefail

retries=${RETRIES:-3}
delay=${RETRY_DELAY:-60}

# Messages that mean the network failed, not the build.
pattern='RPC failed|early EOF|unexpected disconnect|Connection (reset|refused|timed out)|connection reset by peer|Could not resolve host|Temporary failure in name resolution|TLS handshake timeout|i/o timeout|unexpected EOF|Operation timed out|timed out after|curl: \((6|7|18|28|35|52|56|92)\)|HTTP error 50[234]|returned error: 50[234]|50[234] (Bad Gateway|Service Unavailable|Gateway Time-?out)|ECONNRESET|ETIMEDOUT|EAI_AGAIN|socket hang up|Curl error \((6|7|18|28|35|52|56)\)'

log=$(mktemp)
trap 'rm -f "$log"' EXIT

for attempt in $(seq 1 "$retries"); do
  "$@" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  [ "$status" -ne 0 ] || exit 0
  # Only the end of the output: a fetch that failed and was retried
  # successfully earlier in the build doesn't count.
  if ! tail -n 200 "$log" | grep -qE "$pattern"; then
    exit "$status"
  fi
  if [ "$attempt" -lt "$retries" ]; then
    echo "::warning::network error (attempt $attempt of $retries); retrying in ${delay}s: $*"
    tail -n 200 "$log" | grep -E "$pattern" | tail -3
    sleep "$delay"
  fi
done
echo "::error::still failing with a network error after $retries attempts: $*"
exit "$status"
