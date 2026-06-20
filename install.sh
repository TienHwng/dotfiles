#!/usr/bin/env bash

set -e

cd "$(dirname "$0")"

for package in */; do
    package="${package%/}"
    echo "Stowing $package..."
    stow -t "$HOME" "$package"
done

echo "All packages have been stowed successfully."