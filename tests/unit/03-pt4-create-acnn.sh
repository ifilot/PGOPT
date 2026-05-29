#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ./common.sh

require_docker_image

docker_run bash -s <<'CONTAINER_SCRIPT'
set -euo pipefail

workdir=/tmp/pgopt-pt4-create
rm -rf "${workdir}"
mkdir -p "${workdir}"
cd "${workdir}"

stage_inputs() {
    # This fixture is the smallest ACNN creation request in the unit ladder.
    cp "${PGOPT_TEST_FIXTURES}/unit/fixtures/pt4-create/pt4-create.json" .
}

run_creation() {
acnnmain pt4-create.json
}

assert_candidates() {
test -s OUT-pt4-gas/fil_structs.xyz.0
test "$(grep -c "^4$" OUT-pt4-gas/fil_structs.xyz.0)" -ge 1
}

stage_inputs
run_creation
assert_candidates
echo "Pt4 ACNN creation smoke ok"
CONTAINER_SCRIPT
