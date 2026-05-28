#!/usr/bin/env bash
set -euo pipefail

workdir="${PGOPT_VASP_SMOKE_DIR:-/tmp/pgopt-vasp-smoke}"
element="${PGOPT_VASP_SMOKE_ELEMENT:-}"
encut="${PGOPT_VASP_SMOKE_ENCUT:-120}"
nelm="${PGOPT_VASP_SMOKE_NELM:-1}"
cell="${PGOPT_VASP_SMOKE_CELL:-8}"

: "${VASP_PP_PATH:?VASP_PP_PATH must be set}"
: "${VASPHOME:?VASPHOME must be set}"

pbe_dir="${VASP_PP_PATH}/potpaw_PBE"

if [[ -z "${element}" ]]; then
    if [[ -s "${pbe_dir}/H/POTCAR" ]]; then
        element="H"
    else
        first_potcar="$(find "${pbe_dir}" -mindepth 2 -maxdepth 2 -type f -name POTCAR -print -quit 2>/dev/null || true)"
        if [[ -n "${first_potcar}" ]]; then
            element="$(basename "$(dirname "${first_potcar}")")"
        fi
    fi
fi

if [[ -z "${element}" || ! -s "${pbe_dir}/${element}/POTCAR" ]]; then
    echo "No usable PBE POTCAR found under ${pbe_dir}." >&2
    echo "Put licensed potentials at the repository root, for example ./potpaw_PBE/<Element>/POTCAR, then rebuild the image." >&2
    exit 2
fi

rm -rf "${workdir}"
mkdir -p "${workdir}/run"

cat > "${workdir}/run/coords.xyz" <<EOF
1
PGOPT VASP smoke
${element} 0.0 0.0 0.0
EOF

cat > "${workdir}/run/svasp.in" <<EOF
% nproc=1
% chk=vasp-smoke.chk
# PBE/ coords=coords.xyz cell=${cell} encut=${encut} prec=Low lwave=F lcharg=F sigma=0.1 ismear=0 nsw=0 ibrion=-1 scf(iter=${nelm})

PGOPT VASP smoke

0 0

EOF

cd "${workdir}/run"
set +e
SVASP < svasp.in > "${workdir}/svasp.out" 2>&1
status=$?
set -e

chk="${workdir}/run/vasp-smoke.chk"

echo "SVASP exit status: ${status}"
echo "VASP program: ${VASPHOME}/vasp_gam"
echo "Smoke directory: ${chk}"
echo
tail -80 "${workdir}/svasp.out"

test -s "${chk}/POTCAR"
test -s "${chk}/proc-stat.txt"
test -s "${chk}/OUTCAR"

if [[ "${status}" -ne 0 ]]; then
    exit "${status}"
fi

echo
echo "PGOPT launched VASP and VASP produced OUTCAR."
