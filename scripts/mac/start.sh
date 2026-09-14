#! /usr/bin/env bash

set -o nounset
set -o errexit
set -o pipefail
IFS=$'\n\t'

cd "$(dirname "$0")/../.."

printf "%s\n" "Starting services..."
brew services start postgresql@17
brew services start valkey

printf "%s\n" "Waiting for PostgreSQL to be ready..."
until pg_isready -q; do
  sleep 1
done

printf "%s\n" "Starting Terminus..."
exec overmind start --port-step 10 --procfile Procfile.dev --can-die assets,migrate
