#!/usr/bin/env bash
# rebuild.command — rebuild and reinstall Mac Analyzers from THIS clone as it is.
# The same steps as upgrade.command without the `git pull`: for someone who builds
# from their own clone and wants to see work that is not committed yet. Safe to run
# any time; your config.local.sh is never touched.
set -euo pipefail
cd "$(dirname "$0")"
exec ./upgrade.command --no-pull
