#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ./common.sh

require_docker_image

docker_run bash -lc '/root/PGOPT-PROGRAMS/smoke-vasp-pgopt.sh'

