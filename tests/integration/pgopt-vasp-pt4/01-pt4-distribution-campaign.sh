#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ./common.sh

require_docker_image

CANDIDATE_COUNT="${CANDIDATE_COUNT:-12}"
RELAX_COUNT="${RELAX_COUNT:-3}"
ENCUT="${ENCUT:-350}"
SCF_ITER="${SCF_ITER:-20}"
NSW="${NSW:-1}"

docker_run env \
    CANDIDATE_COUNT="${CANDIDATE_COUNT}" \
    RELAX_COUNT="${RELAX_COUNT}" \
    ENCUT="${ENCUT}" \
    SCF_ITER="${SCF_ITER}" \
    NSW="${NSW}" \
    bash -lc '
set -euo pipefail

workdir=/tmp/pgopt-pt4-distribution-campaign
rm -rf "${workdir}"
mkdir -p "${workdir}"
cd "${workdir}"

cat > pt4-create.json <<EOF
{
  "tasks": ["create"],
  "output_dir": "./OUT-pt4-gas",
  "random_seed": 0,
  "creation": {
    "name": "Pt4",
    "number": ${CANDIDATE_COUNT},
    "method": "blda",
    "order": 2,
    "2d": 0.3
  },
  "filtering-create": {
    "max_diff": 0.25,
    "max_diff_report": 1.00
  }
}
EOF

acnnmain pt4-create.json > create.out
test -s OUT-pt4-gas/fil_structs.xyz.0
structure_count="$(grep -c "^4$" OUT-pt4-gas/fil_structs.xyz.0)"
test "${structure_count}" -ge "${RELAX_COUNT}"

cat > draw-candidates.json <<EOF
{
  "tasks": ["draw"],
  "output_dir": "./report",
  "report": {
    "input_file": "./OUT-pt4-gas/fil_structs.xyz.0",
    "output_file": "./report/pt4-candidates.pdf",
    "number": ${CANDIDATE_COUNT},
    "ratio": 1.6
  }
}
EOF

acnnmain draw-candidates.json > draw-candidates.out
test -s report/pt4-candidates.pdf

mkdir -p relaxed
: > relaxed/final.xyz

idx=0
while [[ "${idx}" -lt "${RELAX_COUNT}" ]]; do
    start=$((idx * 6 + 1))
    stop=$((start + 5))
    awk -v start="${start}" -v stop="${stop}" "NR>=start && NR<=stop {print}" \
        OUT-pt4-gas/fil_structs.xyz.0 > "coords-${idx}.xyz"
    test -s "coords-${idx}.xyz"

    cat > "svasp-${idx}.in" <<EOF
% nproc=1
% chk=pt4-relax-${idx}.chk
# PBE/ coords=coords-${idx}.xyz cell=18 encut=${ENCUT} prec=Normal lwave=F lcharg=F sigma=0.1 ismear=0 nsw=${NSW} ibrion=2 potim=0.2 ediff=1e-4 ediffg=-0.5 scf(iter=${SCF_ITER})

PGOPT generated Pt4 integration campaign ${idx}

0 0

EOF

    SVASP < "svasp-${idx}.in" > "svasp-${idx}.out" 2>&1
    tail -30 "svasp-${idx}.out"
    grep -q "Normal termination" "svasp-${idx}.out"
    test -s "pt4-relax-${idx}.chk/POTCAR"
    test -s "pt4-relax-${idx}.chk/OUTCAR"
    test -s "pt4-relax-${idx}.chk/CONTCAR"
    test -s "pt4-relax-${idx}.chk/final.xyz"
    cat "pt4-relax-${idx}.chk/final.xyz" >> relaxed/final.xyz
    cp "pt4-relax-${idx}.chk/CONTCAR" "relaxed/CONTCAR-${idx}"
    idx=$((idx + 1))
done

cat > draw-relaxed.json <<EOF
{
  "tasks": ["draw"],
  "output_dir": "./report",
  "report": {
    "input_file": "./relaxed/final.xyz",
    "output_file": "./report/pt4-relaxed.pdf",
    "number": ${RELAX_COUNT},
    "ratio": 1.6
  }
}
EOF

acnnmain draw-relaxed.json > draw-relaxed.out
test -s report/pt4-relaxed.pdf

cat > summary.txt <<EOF
Pt4 PGOPT/VASP integration campaign
candidates_requested=${CANDIDATE_COUNT}
candidates_after_filtering=${structure_count}
relaxed_structures=${RELAX_COUNT}
encut=${ENCUT}
prec=Normal
nsw=${NSW}
scf_iter=${SCF_ITER}
EOF

if [[ -n "${PGOPT_TEST_ARTIFACTS:-}" ]]; then
    artifact_dir="${PGOPT_TEST_ARTIFACTS}/integration-pt4-distribution-campaign"
    mkdir -p "${artifact_dir}/logs" "${artifact_dir}/relaxed"
    cp summary.txt "${artifact_dir}/"
    cp create.out draw-candidates.out draw-relaxed.out "${artifact_dir}/logs/"
    cp OUT-pt4-gas/fil_structs.xyz.0 "${artifact_dir}/candidates.xyz"
    cp report/pt4-candidates.pdf "${artifact_dir}/"
    cp relaxed/final.xyz "${artifact_dir}/relaxed/final.xyz"
    cp relaxed/CONTCAR-* "${artifact_dir}/relaxed/"
    cp report/pt4-relaxed.pdf "${artifact_dir}/relaxed/"
    cp svasp-*.out "${artifact_dir}/logs/"
fi

echo "Pt4 integration campaign ok: ${structure_count} candidates, ${RELAX_COUNT} VASP relaxations"
'
