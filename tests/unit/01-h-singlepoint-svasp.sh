#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ./common.sh

require_docker_image

# Keep this rung as a direct call to the image-level smoke script. It checks the
# smallest possible SVASP -> VASP launch before the ladder moves on to Pt4.
docker_run bash -lc '/root/PGOPT-PROGRAMS/smoke-vasp-pgopt.sh'
