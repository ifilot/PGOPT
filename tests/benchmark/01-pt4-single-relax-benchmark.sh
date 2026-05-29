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
    bash -s <<'CONTAINER_SCRIPT'
set -euo pipefail

workdir=/tmp/pgopt-pt4-single-relax-benchmark
artifact_dir="${PGOPT_TEST_ARTIFACTS}/pt4-single-relax-benchmark"
fixture_dir="${PGOPT_TEST_FIXTURES}/benchmark/fixtures/pt4-single-relax"
results="${artifact_dir}/results.tsv"

prepare_workspace() {
    rm -rf "${workdir}"
    mkdir -p "${workdir}" "${artifact_dir}/raw-vasp" "${artifact_dir}/logs"
    cd "${workdir}"
}

patch_image_if_needed() {
    # Older built images may not include the local NCORE passthrough yet. Keep
    # the benchmark script usable against that image while the source tree is in
    # flux.
    if ! grep -q "\"NCORE\"" /root/PGOPT-PROGRAMS/STMOLE/svasp.py; then
        sed -i "s/\"NPAR\",/\"NPAR\", \"NCORE\",/" /root/PGOPT-PROGRAMS/STMOLE/svasp.py
    fi
}

write_fixed_geometry() {
    cp "${fixture_dir}/coords.xyz" .
}

initialize_results() {
    printf "case\tstatus\twall_seconds\tloop_real_seconds\tloop_cpu_seconds\tfinal_energy_ev\tionic_steps\tomp_threads\tmkl_threads\tnproc\tincar_extra\n" > "${results}"
}

write_svasp_input() {
    local name="$1"
    local nproc="$2"
    local incar_extra="$3"

    sed \
        -e "s/@CASE_NAME@/${name}/g" \
        -e "s/@NPROC@/${nproc}/g" \
        -e "s/@ENCUT@/${ENCUT}/g" \
        -e "s/@PREC@/${PREC}/g" \
        -e "s/@NSW@/${NSW}/g" \
        -e "s/@SCF_ITER@/${SCF_ITER}/g" \
        -e "s/@EDIFF@/${EDIFF}/g" \
        -e "s/@EDIFFG@/${EDIFFG}/g" \
        -e "s/@INCAR_EXTRA@/${incar_extra}/g" \
        "${fixture_dir}/svasp.template.in" > svasp.in
}

extract_vasp_metrics() {
    local name="$1"
    local outcar="${name}.chk/OUTCAR"
    local oszicar="${name}.chk/OSZICAR"

    loop_real="NA"
    loop_cpu="NA"
    final_energy="NA"
    ionic_steps="NA"

    if [[ -s "${outcar}" ]]; then
        loop_real="$(awk "/LOOP\\+:/ {v=\$7} END {print v ? v : \"NA\"}" "${outcar}")"
        loop_cpu="$(awk "/LOOP\\+:/ {v=\$4; gsub(\":\", \"\", v)} END {print v ? v : \"NA\"}" "${outcar}")"
        final_energy="$(awk "/free  energy   TOTEN/ {v=\$5} END {print v ? v : \"NA\"}" "${outcar}")"
    fi
    if [[ -s "${oszicar}" ]]; then
        ionic_steps="$(awk "/ F=/ {n++} END {print n ? n : \"NA\"}" "${oszicar}")"
    fi
}

archive_case_outputs() {
    local name="$1"

    mkdir -p "${artifact_dir}/logs/${name}" "${artifact_dir}/raw-vasp/${name}.chk"
    cp svasp.in svasp.out "${artifact_dir}/logs/${name}/"
    if [[ -d "${name}.chk" ]]; then
        for raw_file in INCAR KPOINTS POSCAR CONTCAR OUTCAR OSZICAR XDATCAR vasprun.xml proc-stat.txt; do
            if [[ -e "${name}.chk/${raw_file}" ]]; then
                cp "${name}.chk/${raw_file}" "${artifact_dir}/raw-vasp/${name}.chk/"
            fi
        done
    fi
}

run_case() {
    local name="$1"
    local omp_threads="$2"
    local nproc="$3"
    local incar_extra="$4"

    local case_dir="${workdir}/${name}"
    local start_ts end_ts wall status

    rm -rf "${case_dir}"
    mkdir -p "${case_dir}"
    cp "${workdir}/coords.xyz" "${case_dir}/coords.xyz"
    cd "${case_dir}"
    write_svasp_input "${name}" "${nproc}" "${incar_extra}"

    start_ts="$(date +%s)"
    status="pass"
    if ! env OMP_NUM_THREADS="${omp_threads}" MKL_NUM_THREADS="${omp_threads}" \
        SVASP < svasp.in > svasp.out 2>&1; then
        status="fail"
    fi
    end_ts="$(date +%s)"
    wall="$((end_ts - start_ts))"

    extract_vasp_metrics "${name}"
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "${name}" "${status}" "${wall}" "${loop_real}" "${loop_cpu}" \
        "${final_energy}" "${ionic_steps}" "${omp_threads}" "${omp_threads}" \
        "${nproc}" "${incar_extra:-none}" >> "${results}"

    archive_case_outputs "${name}"
    cd "${workdir}"
}

skip_case() {
    local name="$1"
    local reason="$2"
    printf "%s\tskipped\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\t%s\n" "${name}" "${reason}" >> "${results}"
}

run_openmp_cases() {
    run_case omp1 1 1 ""
    run_case omp2 2 1 ""
    run_case omp4 4 1 ""
    run_case omp8 8 1 ""
}

run_vasp_layout_cases() {
    # NCORE and NPAR are meaningful probes for VASP layout behavior, but this
    # image is still serial/gamma-only. The table is therefore a local sanity
    # check, not a claim about MPI scaling.
    run_case omp4_ncore1 4 1 "ncore=1"
    run_case omp4_ncore2 4 1 "ncore=2"
    run_case omp4_ncore4 4 1 "ncore=4"
    run_case omp4_npar1 4 1 "npar=1"
    run_case omp4_npar2 4 1 "npar=2"
}

run_mpi_probe_cases() {
    if command -v mpirun >/dev/null 2>&1; then
        run_case mpi2_omp1 1 2 ""
        run_case mpi4_omp1 1 4 ""
    else
        skip_case mpi2_omp1 "mpirun-not-installed-in-image"
        skip_case mpi4_omp1 "mpirun-not-installed-in-image"
    fi
}

print_results() {
    column -t -s "$(printf "\t")" "${results}" > "${artifact_dir}/results.txt" 2>/dev/null || \
        cp "${results}" "${artifact_dir}/results.txt"
    cat "${artifact_dir}/results.txt"
}

prepare_workspace
patch_image_if_needed
write_fixed_geometry
initialize_results
run_openmp_cases
run_vasp_layout_cases
run_mpi_probe_cases
print_results
CONTAINER_SCRIPT
