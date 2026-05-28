#!/usr/bin/env bash
set -euo pipefail

PGOPT_IMAGE="${PGOPT_IMAGE:-pgopt:local}"
THREADS="${THREADS:-2}"

docker_run() {
    docker run --rm \
        -e OMP_NUM_THREADS="${THREADS}" \
        -e MKL_NUM_THREADS="${THREADS}" \
        "${PGOPT_IMAGE}" "$@"
}

require_docker_image() {
    docker image inspect "${PGOPT_IMAGE}" >/dev/null
}

