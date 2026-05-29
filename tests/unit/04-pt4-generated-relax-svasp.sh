#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ./common.sh

require_docker_image

docker_run bash -s <<'CONTAINER_SCRIPT'
set -euo pipefail

workdir=/tmp/pgopt-pt4-generated-relax
rm -rf "${workdir}"
mkdir -p "${workdir}"
cd "${workdir}"

stage_inputs() {
    # The generated coordinates are runtime output; the ACNN and SVASP inputs
    # are fixtures so their chemistry settings are visible in the repo.
    cp "${PGOPT_TEST_FIXTURES}/unit/fixtures/pt4-generated-relax/pt4-create.json" .
    cp "${PGOPT_TEST_FIXTURES}/unit/fixtures/pt4-generated-relax/svasp.in" .
}

generate_first_candidate() {
acnnmain pt4-create.json > create.out
awk "NR<=6 {print}" OUT-pt4-gas/fil_structs.xyz.0 > coords.xyz
test -s coords.xyz
}

run_relaxation() {
SVASP < svasp.in > svasp.out 2>&1
tail -60 svasp.out
}

assert_relaxation_outputs() {
test -s pt4-generated-relax.chk/POTCAR
test -s pt4-generated-relax.chk/OUTCAR
test -s pt4-generated-relax.chk/CONTCAR
test -s pt4-generated-relax.chk/final.xyz
}

stage_inputs
generate_first_candidate
run_relaxation
assert_relaxation_outputs
echo "generated Pt4 relax smoke ok"
CONTAINER_SCRIPT
