#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ./common.sh

require_docker_image

docker_run bash -lc '
set -euo pipefail
workdir=/tmp/pgopt-pt4-generated-batch
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
    "number": 3,
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

for idx in 0 1 2; do
    start=$((idx * 6 + 1))
    stop=$((start + 5))
    awk -v start="${start}" -v stop="${stop}" "NR>=start && NR<=stop {print}" \
        OUT-pt4-gas/fil_structs.xyz.0 > "coords-${idx}.xyz"
    test -s "coords-${idx}.xyz"

    cat > "svasp-${idx}.in" <<EOF
% nproc=1
% chk=pt4-batch-${idx}.chk
# PBE/ coords=coords-${idx}.xyz cell=18 encut=150 prec=Low lwave=F lcharg=F sigma=0.1 ismear=0 nsw=1 ibrion=2 potim=0.2 ediff=1e-4 ediffg=-0.5 scf(iter=10)

PGOPT generated Pt4 batch VASP smoke ${idx}

0 0

EOF

    SVASP < "svasp-${idx}.in" > "svasp-${idx}.out" 2>&1
    test -s "pt4-batch-${idx}.chk/OUTCAR"
    test -s "pt4-batch-${idx}.chk/CONTCAR"
    tail -8 "svasp-${idx}.out"
done

echo "generated Pt4 batch smoke ok"
'
