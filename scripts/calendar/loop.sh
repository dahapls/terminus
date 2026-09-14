#! /usr/bin/env bash

set -o nounset
set -o pipefail
IFS=$'\n\t'

INTERVAL="${CALENDAR_INTERVAL:-600}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

while true; do
  ruby "$SCRIPT_DIR/fetch.rb" || printf "%s\n" "Calendar fetch failed; retrying in $INTERVAL seconds"
  sleep "$INTERVAL"
done
