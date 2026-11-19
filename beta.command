#!/usr/bin/env bash
# beta.command — update Mac Analyzers to the newest beta from THIS clone (it must be on development).
# The same steps as upgrade.command, but the clone moves to the newest beta's tag (a GitHub pre-release,
# vX.Y.Z-beta.N) instead of pulling the newest commit. Safe to run any time; your config.local.sh is never touched.
set -euo pipefail
cd "$(dirname "$0")"
exec ./upgrade.command --beta
