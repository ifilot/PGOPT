#!/usr/bin/env bash
set -euo pipefail

PGOPT_IMAGE="${PGOPT_IMAGE:-pgopt:local}"
THREADS="${THREADS:-2}"
PGOPT_TEST_ARTIFACTS="${PGOPT_TEST_ARTIFACTS:-}"

docker_run() {
    local artifact_args=()

    if [[ -n "${PGOPT_TEST_ARTIFACTS}" ]]; then
        local artifact_dir
        artifact_dir="${PGOPT_TEST_ARTIFACTS}"
        if [[ "${artifact_dir}" != /* ]]; then
            local repo_root
            repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
            artifact_dir="${repo_root}/${artifact_dir}"
        fi
        artifact_dir="$(mkdir -p "${artifact_dir}" && cd "${artifact_dir}" && pwd)"
        artifact_args=(-v "${artifact_dir}:/artifacts" -e PGOPT_TEST_ARTIFACTS=/artifacts)
    fi

    docker run --rm \
        -e OMP_NUM_THREADS="${THREADS}" \
        -e MKL_NUM_THREADS="${THREADS}" \
        "${artifact_args[@]}" \
        "${PGOPT_IMAGE}" "$@"
}

require_docker_image() {
    docker image inspect "${PGOPT_IMAGE}" >/dev/null
}
