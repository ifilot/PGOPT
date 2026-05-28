#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ./common.sh

require_docker_image

docker_run bash -lc '
set -euo pipefail
workdir=/tmp/pgopt-pt4-generated-relax
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
awk "NR<=6 {print}" OUT-pt4-gas/fil_structs.xyz.0 > coords.xyz

cat > svasp.in <<EOF
% nproc=1
% chk=pt4-generated-relax.chk
# PBE/ coords=coords.xyz cell=18 encut=150 prec=Low lwave=F lcharg=F sigma=0.1 ismear=0 nsw=1 ibrion=2 potim=0.2 ediff=1e-4 ediffg=-0.5 scf(iter=10)

PGOPT generated Pt4 VASP relaxation smoke

0 0

EOF

SVASP < svasp.in > svasp.out 2>&1
tail -60 svasp.out
test -s pt4-generated-relax.chk/POTCAR
test -s pt4-generated-relax.chk/OUTCAR
test -s pt4-generated-relax.chk/CONTCAR
test -s pt4-generated-relax.chk/final.xyz
echo "generated Pt4 relax smoke ok"
'

