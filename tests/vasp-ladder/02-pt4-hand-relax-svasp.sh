#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ./common.sh

require_docker_image

docker_run bash -lc '
set -euo pipefail
workdir=/tmp/pgopt-pt4-hand-relax
rm -rf "${workdir}"
mkdir -p "${workdir}/run"
cd "${workdir}/run"

cat > coords.xyz <<EOF
4
Pt4 tetrahedron smoke
Pt 0.000 0.000 0.000
Pt 2.600 0.000 0.000
Pt 1.300 2.252 0.000
Pt 1.300 0.751 2.124
EOF

cat > svasp.in <<EOF
% nproc=1
% chk=pt4-relax.chk
# PBE/ coords=coords.xyz cell=18 encut=150 prec=Low lwave=F lcharg=F sigma=0.1 ismear=0 nsw=1 ibrion=2 potim=0.2 ediff=1e-4 ediffg=-0.5 scf(iter=10)

PGOPT VASP Pt4 relaxation smoke

0 0

EOF

SVASP < svasp.in > "${workdir}/svasp.out" 2>&1
tail -60 "${workdir}/svasp.out"
test -s pt4-relax.chk/POTCAR
test -s pt4-relax.chk/OUTCAR
test -s pt4-relax.chk/CONTCAR
test -s pt4-relax.chk/OSZICAR
test -s pt4-relax.chk/final.xyz
echo "hand-written Pt4 relax smoke ok"
'

