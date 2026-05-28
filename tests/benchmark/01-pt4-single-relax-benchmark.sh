#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ../docker-common.sh

require_docker_image

BENCHMARK_ARTIFACTS="${PGOPT_TEST_ARTIFACTS:-OUT-benchmark-artifacts}"
NSW="${NSW:-1}"
SCF_ITER="${SCF_ITER:-10}"
ENCUT="${ENCUT:-150}"
PREC="${PREC:-Low}"
EDIFFG="${EDIFFG:--0.5}"
EDIFF="${EDIFF:-1e-4}"

export PGOPT_TEST_ARTIFACTS="${BENCHMARK_ARTIFACTS}"

docker_run env \
    NSW="${NSW}" \
    SCF_ITER="${SCF_ITER}" \
    ENCUT="${ENCUT}" \
    PREC="${PREC}" \
    EDIFFG="${EDIFFG}" \
    EDIFF="${EDIFF}" \
    bash -lc '
set -euo pipefail

workdir=/tmp/pgopt-pt4-single-relax-benchmark
rm -rf "${workdir}"
mkdir -p "${workdir}"
cd "${workdir}"

if ! grep -q "\"NCORE\"" /root/PGOPT-PROGRAMS/STMOLE/svasp.py; then
    sed -i "s/\"NPAR\",/\"NPAR\", \"NCORE\",/" /root/PGOPT-PROGRAMS/STMOLE/svasp.py
fi

artifact_dir="${PGOPT_TEST_ARTIFACTS}/pt4-single-relax-benchmark"
mkdir -p "${artifact_dir}/raw-vasp" "${artifact_dir}/logs"
results="${artifact_dir}/results.tsv"
printf "case\tstatus\twall_seconds\tloop_real_seconds\tloop_cpu_seconds\tfinal_energy_ev\tionic_steps\tomp_threads\tmkl_threads\tnproc\tincar_extra\n" > "${results}"

cat > coords.xyz <<EOF
4
Pt4 benchmark geometry
Pt    -0.59198295    -2.28624997     0.00000000
Pt     1.46751265    -0.16734385     0.00000000
Pt    -1.17852185     0.14377228     0.00000000
Pt     0.30299214     2.30982155     0.00000000
EOF

run_case() {
    local name="$1"
    local omp_threads="$2"
    local nproc="$3"
    local incar_extra="$4"

    local case_dir="${workdir}/${name}"
    rm -rf "${case_dir}"
    mkdir -p "${case_dir}"
    cp coords.xyz "${case_dir}/coords.xyz"
    cd "${case_dir}"

    cat > svasp.in <<EOF
% nproc=${nproc}
% chk=${name}.chk
# PBE/ coords=coords.xyz cell=18 encut=${ENCUT} prec=${PREC} lwave=F lcharg=F sigma=0.1 ismear=0 nsw=${NSW} ibrion=2 potim=0.2 ediff=${EDIFF} ediffg=${EDIFFG} scf(iter=${SCF_ITER}) ${incar_extra}

PGOPT Pt4 benchmark ${name}

0 0

EOF

    local start_ts end_ts status
    start_ts="$(date +%s)"
    status="pass"
    if ! env OMP_NUM_THREADS="${omp_threads}" MKL_NUM_THREADS="${omp_threads}" \
        SVASP < svasp.in > svasp.out 2>&1; then
        status="fail"
    fi
    end_ts="$(date +%s)"

    local wall loop_real loop_cpu final_energy ionic_steps
    wall="$((end_ts - start_ts))"
    loop_real="NA"
    loop_cpu="NA"
    final_energy="NA"
    ionic_steps="NA"

    if [[ -s "${name}.chk/OUTCAR" ]]; then
        loop_real="$(awk "/LOOP\\+:/ {v=\$7} END {print v ? v : \"NA\"}" "${name}.chk/OUTCAR")"
        loop_cpu="$(awk "/LOOP\\+:/ {v=\$4; gsub(\":\", \"\", v)} END {print v ? v : \"NA\"}" "${name}.chk/OUTCAR")"
        final_energy="$(awk "/free  energy   TOTEN/ {v=\$5} END {print v ? v : \"NA\"}" "${name}.chk/OUTCAR")"
    fi
    if [[ -s "${name}.chk/OSZICAR" ]]; then
        ionic_steps="$(awk "/ F=/ {n++} END {print n ? n : \"NA\"}" "${name}.chk/OSZICAR")"
    fi

    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "${name}" "${status}" "${wall}" "${loop_real}" "${loop_cpu}" \
        "${final_energy}" "${ionic_steps}" "${omp_threads}" "${omp_threads}" \
        "${nproc}" "${incar_extra:-none}" >> "${results}"

    mkdir -p "${artifact_dir}/logs/${name}" "${artifact_dir}/raw-vasp/${name}.chk"
    cp svasp.in svasp.out "${artifact_dir}/logs/${name}/"
    if [[ -d "${name}.chk" ]]; then
        for raw_file in INCAR KPOINTS POSCAR CONTCAR OUTCAR OSZICAR XDATCAR vasprun.xml proc-stat.txt; do
            if [[ -e "${name}.chk/${raw_file}" ]]; then
                cp "${name}.chk/${raw_file}" "${artifact_dir}/raw-vasp/${name}.chk/"
            fi
        done
    fi

    cd "${workdir}"
}

skip_case() {
    local name="$1"
    local reason="$2"
    printf "%s\tskipped\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\t%s\n" "${name}" "${reason}" >> "${results}"
}

run_case omp1 1 1 ""
run_case omp2 2 1 ""
run_case omp4 4 1 ""
run_case omp8 8 1 ""
run_case omp4_ncore1 4 1 "ncore=1"
run_case omp4_ncore2 4 1 "ncore=2"
run_case omp4_ncore4 4 1 "ncore=4"
run_case omp4_npar1 4 1 "npar=1"
run_case omp4_npar2 4 1 "npar=2"

if command -v mpirun >/dev/null 2>&1; then
    run_case mpi2_omp1 1 2 ""
    run_case mpi4_omp1 1 4 ""
else
    skip_case mpi2_omp1 "mpirun-not-installed-in-image"
    skip_case mpi4_omp1 "mpirun-not-installed-in-image"
fi

column -t -s "$(printf "\t")" "${results}" > "${artifact_dir}/results.txt" 2>/dev/null || cp "${results}" "${artifact_dir}/results.txt"
cat "${artifact_dir}/results.txt"
'
