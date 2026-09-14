#! /usr/bin/env bash

set -o nounset
set -o errexit
set -o pipefail
IFS=$'\n\t'

# Rebases the local branch onto the latest upstream Terminus.
# Usage: scripts/rebase.sh [--push]

BRANCH="local"
UPSTREAM="upstream/main"

cd "$(dirname "$0")/.."

if [[ "$(git branch --show-current)" != "$BRANCH" ]]; then
  printf "%s\n" "Not on the $BRANCH branch. Run: git switch $BRANCH"
  exit 1
fi

printf "%s\n" "Fetching upstream..."
git fetch upstream

previous="$(git merge-base HEAD "$UPSTREAM")"

if [[ "$previous" == "$(git rev-parse "$UPSTREAM")" ]]; then
  printf "%s\n" "Already up to date with $UPSTREAM."
  exit 0
fi

printf "%s\n" "Rebasing $BRANCH onto $UPSTREAM..."

if ! git rebase --autostash "$UPSTREAM"; then
  printf "\n%s\n" "Rebase stopped on a conflict. Fix the files, then run:"
  printf "%s\n" "  git add <files> && git rebase --continue"
  printf "%s\n" "Or undo the rebase with: git rebase --abort"
  exit 1
fi

printf "\n%s\n" "Upstream changes pulled in:"
git log --oneline "$previous..$UPSTREAM"

changed="$(git diff --name-only "$previous" "$UPSTREAM")"

if grep -qx "Gemfile.lock" <<< "$changed"; then
  printf "\n%s\n" "Gems changed. Run: bundle install"
fi

if grep -qx "package-lock.json" <<< "$changed"; then
  printf "\n%s\n" "Packages changed. Run: npm install"
fi

if grep -q "^config/db/migrate/" <<< "$changed"; then
  printf "\n%s\n" "Database migrations added. Run: bundle exec hanami db migrate"
fi

if [[ "${1:-}" == "--push" ]]; then
  printf "\n%s\n" "Pushing $BRANCH to origin..."
  git push --force-with-lease origin "$BRANCH"
else
  printf "\n%s\n" "To back up the rebased branch, run: git push --force-with-lease origin $BRANCH"
fi

printf "\n%s\n" "Rebase complete. Restart Terminus to pick up the changes."
