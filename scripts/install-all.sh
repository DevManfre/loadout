#!/usr/bin/env bash
# Kept because both READMEs, this repo's history and a lot of muscle memory
# name this path. The installer itself now lives in scripts/loadout.
exec "$(dirname "$0")/loadout" install "$@"
