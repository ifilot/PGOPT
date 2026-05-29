#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ./common.sh

require_docker_image

docker_run bash -s <<'CONTAINER_SCRIPT'
set -euo pipefail

workdir=/tmp/pgopt-pt4-hand-relax
rm -rf "${workdir}"
mkdir -p "${workdir}/run"
cd "${workdir}/run"

stage_inputs() {
    # Hand-authored inputs live in tests/unit/fixtures/pt4-hand-relax.
    cp "${PGOPT_TEST_FIXTURES}/unit/fixtures/pt4-hand-relax/coords.xyz" .
    cp "${PGOPT_TEST_FIXTURES}/unit/fixtures/pt4-hand-relax/svasp.in" .
}

run_relaxation() {
SVASP < svasp.in > "${workdir}/svasp.out" 2>&1
tail -60 "${workdir}/svasp.out"
}

assert_relaxation_outputs() {
test -s pt4-relax.chk/POTCAR
test -s pt4-relax.chk/OUTCAR
test -s pt4-relax.chk/CONTCAR
test -s pt4-relax.chk/OSZICAR
test -s pt4-relax.chk/final.xyz
}

stage_inputs
run_relaxation
assert_relaxation_outputs
echo "hand-written Pt4 relax smoke ok"
CONTAINER_SCRIPT
