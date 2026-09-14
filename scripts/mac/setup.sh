#! /usr/bin/env bash

set -o nounset
set -o errexit
set -o pipefail
IFS=$'\n\t'

RUBY_VERSION="$(cat "$(dirname "$0")/../../.ruby-version")"

# Install Homebrew if missing
if ! command -v brew &>/dev/null; then
  printf "%s\n" "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add Homebrew to PATH for Apple Silicon
  if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi

# Install dependencies
printf "%s\n" "Installing Homebrew dependencies..."
brew install rbenv ruby-build overmind imagemagick valkey postgresql@18 node
brew install --cask google-chrome

# Set up rbenv in current shell
eval "$(rbenv init - zsh)"

# Add rbenv init to ~/.zshrc if not already present
if ! grep -q 'rbenv init' ~/.zshrc; then
  printf "%s\n" "Adding rbenv to ~/.zshrc..."
  echo 'eval "$(rbenv init - zsh)"' >> ~/.zshrc
fi

# Install required Ruby version
if ! rbenv versions | grep -q "$RUBY_VERSION"; then
  printf "%s\n" "Installing Ruby $RUBY_VERSION..."
  rbenv install "$RUBY_VERSION"
fi

rbenv global "$RUBY_VERSION"
rbenv rehash

# Start services
printf "%s\n" "Starting services..."
brew services start postgresql@18
brew services start valkey

printf "%s\n" "Waiting for PostgreSQL to be ready..."
until pg_isready -q; do
  sleep 1
done

printf "%s\n" "Mac setup complete! Now run: bin/setup"
