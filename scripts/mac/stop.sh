#! /usr/bin/env bash

set -o nounset
set -o errexit
set -o pipefail
IFS=$'\n\t'

cd "$(dirname "$0")/../.."

if [[ -S ./.overmind.sock ]]; then
  printf "%s\n" "Stopping Terminus..."
  overmind quit
fi

printf "%s\n" "Stopping services..."
brew services stop postgresql@18
brew services stop valkey

printf "%s\n" "Stopped."
