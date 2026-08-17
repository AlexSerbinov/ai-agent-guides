#!/bin/bash
# Keep .env.example in sync with .env WITHOUT ever losing what is already there.
#
# Why this exists: `copy-env` (and every "generate the example from the real file"
# tool) REGENERATES the example from the local .env. Any key you do not happen to
# have locally — a partner refcode that only lives in GitHub Secrets, a colleague's
# new variable, anything prod-only — silently disappears, and the comments
# explaining those keys go with it. In this repo that cost three separate
# "restore .env.example entries" commits before anyone noticed.
#
# What this does instead:
#   - never removes a line that is already in .env.example
#   - never rewrites existing comments or ordering
#   - appends only keys that exist in .env and are missing from .env.example
#   - writes names only, never values
#
# Usage: merge-env-example.sh <dir-containing-.env>

set -uo pipefail

dir="${1:?usage: merge-env-example.sh <dir>}"
env_file="$dir/.env"
example_file="$dir/.env.example"

[ -f "$env_file" ] || exit 0

# Key names present in .env, in file order. Accepts optional `export ` prefix.
env_keys=$(grep -E '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' "$env_file" 2>/dev/null \
  | sed -E 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/')

[ -n "$env_keys" ] || exit 0

if [ ! -f "$example_file" ]; then
  # First run: nothing to preserve, so a plain listing is safe.
  printf '%s=\n' $env_keys > "$example_file"
  exit 0
fi

# Keys already documented — commented-out ones count too, so a deliberately
# disabled `# OPTIONAL_KEY=` is not re-added as if it were missing.
existing_keys=$(grep -E '^[[:space:]]*#?[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' "$example_file" 2>/dev/null \
  | sed -E 's/^[[:space:]]*#?[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/')

missing=""
for key in $env_keys; do
  if ! printf '%s\n' $existing_keys | grep -qx -- "$key"; then
    case " $missing " in
      *" $key "*) ;;                 # already queued (duplicate in .env)
      *) missing="$missing $key" ;;
    esac
  fi
done

[ -n "${missing// /}" ] || exit 0

# Append under a dated heading so it is obvious these arrived automatically and
# still need a human comment explaining what they are for.
{
  printf '\n# --- added automatically %s (document these) ---\n' "$(date +%Y-%m-%d)"
  for key in $missing; do printf '%s=\n' "$key"; done
} >> "$example_file"
