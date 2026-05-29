#!/usr/bin/env bash
set -euo pipefail

# This test is intentionally a real PGOPT workflow:
#   generate candidates -> create master/worker scripts -> run workers ->
#   let the master collect responses -> verify scheduler bookkeeping.
#
# The Pt4 benchmark showed that this Docker/VASP build gives best throughput
# with many single-core jobs, so the default is one OMP/MKL thread per worker.

if [[ -z "${THREADS+x}" ]]; then
    export THREADS=1
fi
export PGOPT_DOCKER_HOSTNAME="${PGOPT_DOCKER_HOSTNAME:-mac.local}"

cd "$(dirname "$0")"
. ./common.sh

require_docker_image

CANDIDATE_COUNT="${CANDIDATE_COUNT:-8}"
RELAX_COUNT="${RELAX_COUNT:-4}"
WORKER_COUNT="${WORKER_COUNT:-${RELAX_COUNT}}"
ENCUT="${ENCUT:-150}"
PREC="${PREC:-Low}"
SCF_ITER="${SCF_ITER:-20}"
NSW="${NSW:-20}"
MASTER_TIMEOUT="${MASTER_TIMEOUT:-1200}"

if [[ "${THREADS}" -ne 1 ]]; then
    echo "This integration test is tuned for one-core VASP workers; set THREADS=1." >&2
    exit 2
fi
if [[ "${RELAX_COUNT}" -lt 1 || "${WORKER_COUNT}" -lt 1 ]]; then
    echo "RELAX_COUNT and WORKER_COUNT must both be positive." >&2
    exit 2
fi
if [[ "${CANDIDATE_COUNT}" -lt "${RELAX_COUNT}" ]]; then
    echo "CANDIDATE_COUNT must be at least RELAX_COUNT." >&2
    exit 2
fi

docker_run env \
    CANDIDATE_COUNT="${CANDIDATE_COUNT}" \
    RELAX_COUNT="${RELAX_COUNT}" \
    WORKER_COUNT="${WORKER_COUNT}" \
    ENCUT="${ENCUT}" \
    PREC="${PREC}" \
    SCF_ITER="${SCF_ITER}" \
    NSW="${NSW}" \
    MASTER_TIMEOUT="${MASTER_TIMEOUT}" \
    PROJECT_NAME=pgopt-test \
    bash -s <<'CONTAINER_SCRIPT'
set -euo pipefail

workdir=/tmp/pgopt-pt4-master-worker-nsw20
worker_tmp=/tmp/pgopt-pt4-master-worker-nsw20-worker-tmp
summary_log=master/1.0/par_shlog.txt.0
runtime_json=master/1.0/par_runtime.json.0
event_log=master/1.0/par_log.txt.0

prepare_workspace() {
    rm -rf "${workdir}" "${worker_tmp}"
    mkdir -p "${workdir}" "${worker_tmp}"
    cd "${workdir}"
    export WORKDIR="${worker_tmp}"
}

print_settings() {
    cat <<EOF
candidate_count=${CANDIDATE_COUNT}
relax_count=${RELAX_COUNT}
worker_count=${WORKER_COUNT}
omp_threads_per_worker=${OMP_NUM_THREADS}
mkl_threads_per_worker=${MKL_NUM_THREADS}
encut=${ENCUT}
prec=${PREC}
nsw=${NSW}
scf_iter=${SCF_ITER}
EOF
}

tar_list() {
    # PGOPT sometimes writes plain tar archives with a .tar.gz suffix when it
    # keeps WAVECAR-style restart data. Treat the suffix as historical, not as
    # a guarantee of compression.
    local archive_file="$1"

    tar -tzf "${archive_file}" 2>/dev/null || tar -tf "${archive_file}"
}

tar_extract_member() {
    local archive_file="$1"
    local member="$2"

    tar -xOzf "${archive_file}" "${member}" 2>/dev/null \
        || tar -xOf "${archive_file}" "${member}"
}

configure_pgopt_workflow() {
    # Generate a normal PGOPT local project and ask it to prepare the master and
    # worker scripts. We use model=mac because it renders the simplest local
    # shell wrappers and avoids queue-system assumptions inside Docker.
    pgopt init Pt4 "${CANDIDATE_COUNT}" blda \
        --program=vasp --model=mac --cores=1 --nodes=1 --no-scratch
    pgopt set creation 2d 0.3
    pgopt set creation order 2
    pgopt set relax
    pgopt set opts^ "cell=18;encut=${ENCUT};prec=${PREC};lwave=F;lcharg=F;sigma=0.1;ismear=0;nsw=${NSW};ibrion=2;potim=0.2;ediff=1e-4;ediffg=-0.5;scf(iter=${SCF_ITER})"
    pgopt set args step "${NSW}"
    pgopt set args max_step "${NSW}"
    pgopt set parallel idle_time 1.0
    pgopt set parallel max_no_repsonce_time 300.0
    pgopt relax 1 --time=00:30:00 --rseed=0 --max-config="${RELAX_COUNT}"
    pgopt torun para 0 "${WORKER_COUNT}" --time=00:30:00
}

start_workers() {
    export JOBID=pgopt02
    worker_pids=()

    local idx=0
    while [[ "${idx}" -lt "${WORKER_COUNT}" ]]; do
        (
            cd torun/para
            "${PGOPTHOME}/scripts/torun-single.sh" para "${idx}" \
                > "../../worker-${idx}.out" 2>&1
        ) &
        worker_pids+=("$!")
        idx=$((idx + 1))
    done
}

stop_workers() {
    [[ -d procs/para ]] || return 0

    local proc_dir
    for proc_dir in procs/para/PROC*; do
        [[ -d "${proc_dir}" ]] || continue
        echo FINISH > "${proc_dir}/REQUEST"
    done
}

wait_for_workers() {
    local pid
    for pid in "${worker_pids[@]}"; do
        wait "${pid}" || true
    done
}

run_master() {
    # The generated wrapper does useful cleanup after ACNN finishes. Its final
    # `[ -f ./DIRECTORIES ] && pgopt sync` can return 1 in this no-scratch test,
    # so later validation trusts the PGOPT summary state over the wrapper code.
    master_status=0
    (
        cd tomaster/relax-1.0
        timeout "${MASTER_TIMEOUT}" ./run-master.sh > run-master.direct.out 2>&1
    ) || master_status="$?"
}

copy_failure_artifacts() {
    [[ -n "${PGOPT_TEST_ARTIFACTS:-}" ]] || return 0

    local artifact_dir="${PGOPT_TEST_ARTIFACTS}/integration-pt4-parallel-relax-nsw20-failed"
    mkdir -p "${artifact_dir}/logs" "${artifact_dir}/master" "${artifact_dir}/procs"
    cp CMD-HISTORY para-template.json "${artifact_dir}/" 2>/dev/null || true
    cp tomaster/relax-1.0/para.json "${artifact_dir}/master/" 2>/dev/null || true
    cp tomaster/relax-1.0/run-master.sh "${artifact_dir}/master/" 2>/dev/null || true
    cp tomaster/relax-1.0/run-master.direct.out "${artifact_dir}/logs/" 2>/dev/null || true
    cp tomaster/relax-1.0/master.out.* "${artifact_dir}/logs/" 2>/dev/null || true
    cp master/1.0/par_*.0 "${artifact_dir}/master/" 2>/dev/null || true
    cp worker-*.out "${artifact_dir}/logs/" 2>/dev/null || true

    local proc_dir proc_name
    for proc_dir in procs/para/PROC*; do
        [[ -d "${proc_dir}" ]] || continue
        proc_name="$(basename "${proc_dir}")"
        mkdir -p "${artifact_dir}/procs/${proc_name}"
        cp "${proc_dir}"/REQUEST* "${artifact_dir}/procs/${proc_name}/" 2>/dev/null || true
        cp "${proc_dir}"/RESPONSE* "${artifact_dir}/procs/${proc_name}/" 2>/dev/null || true
        cp "${proc_dir}"/relax.in.* "${artifact_dir}/procs/${proc_name}/" 2>/dev/null || true
        cp "${proc_dir}"/relax.out.* "${artifact_dir}/procs/${proc_name}/" 2>/dev/null || true
        cp "${proc_dir}"/final.xyz.* "${artifact_dir}/procs/${proc_name}/" 2>/dev/null || true
        cp "${proc_dir}"/archive.tar.gz.* "${artifact_dir}/procs/${proc_name}/" 2>/dev/null || true
    done
}

print_master_diagnostics() {
    echo "--- run-master.direct.out ---" >&2
    tail -120 tomaster/relax-1.0/run-master.direct.out >&2 || true

    local master_out
    for master_out in tomaster/relax-1.0/master.out.*; do
        [[ -e "${master_out}" ]] || continue
        echo "--- ${master_out} ---" >&2
        tail -160 "${master_out}" >&2 || true
    done
}

master_finished() {
    [[ -s "${summary_log}" ]] && \
        awk "{ if (\$NF == \"finished\") ok=1 } END { exit ok ? 0 : 1 }" "${summary_log}"
}

validate_master_status() {
    if [[ "${master_status}" -eq 0 ]]; then
        return 0
    fi

    echo "PGOPT run-master.sh exited with status ${master_status}; checking master state." >&2
    print_master_diagnostics
    if ! master_finished; then
        copy_failure_artifacts
        exit "${master_status}"
    fi
    echo "PGOPT master state is finished; ignoring generated wrapper status ${master_status}." >&2
}

assert_master_outputs_exist() {
    test -s "${summary_log}"
    test -s "${runtime_json}"
    test -s "${event_log}"
}

assert_scheduler_state() {
    python - "${runtime_json}" "${summary_log}" "${RELAX_COUNT}" "${WORKER_COUNT}" <<'PY'
import json
import sys

runtime_path, summary_path, relax_count, worker_count = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
with open(runtime_path) as handle:
    runtime = json.load(handle)
with open(summary_path) as handle:
    summary = handle.read().strip().split()

if len(summary) < 11 or summary[10] != "finished":
    raise SystemExit("PGOPT summary is not finished: " + " ".join(summary))
total, remaining = int(summary[0]), int(summary[1])
if total != relax_count or remaining != 0:
    raise SystemExit("unexpected total/remaining in summary: " + " ".join(summary))

completed = []
for proc_id, entries in runtime.get("times", {}).items():
    for entry in entries:
        if len(entry) >= 5:
            completed.append((proc_id, float(entry[0]), float(entry[2]), entry[4]))

if len(completed) != relax_count:
    raise SystemExit("expected %d completed assignments, got %d" % (relax_count, len(completed)))
used_workers = sorted({proc_id for proc_id, _, _, _ in completed})
if len(used_workers) < min(worker_count, relax_count):
    raise SystemExit("not all expected workers were used: " + ",".join(used_workers))

events = []
for _, start, stop, _ in completed:
    events.append((start, 1))
    events.append((stop, -1))
active = 0
max_overlap = 0
for _, delta in sorted(events, key=lambda item: (item[0], item[1])):
    active += delta
    max_overlap = max(max_overlap, active)
if min(worker_count, relax_count) > 1 and max_overlap < 2:
    raise SystemExit("worker assignments did not overlap")

print("completed_assignments=%d" % len(completed))
print("used_workers=%s" % ",".join(used_workers))
print("max_overlapping_assignments=%d" % max_overlap)
PY
}

assert_worker_responses() {
    local response_count
    response_count="$(find procs/para -path "*/RESPONSE.old.*" -type f | wc -l)"
    if [[ "${response_count}" -ne "${RELAX_COUNT}" ]]; then
        echo "Expected ${RELAX_COUNT} worker responses, found ${response_count}." >&2
        copy_failure_artifacts
        exit 1
    fi
}

assert_relax_input() {
    local input_file="$1"

    grep -q "^% workers=unknown:1" "${input_file}"
    grep -q "nsw=${NSW}" "${input_file}"
    grep -q "scf(iter=${SCF_ITER})" "${input_file}"
}

assert_worker_inputs() {
    # PGOPT archives successful worker files, so check both live files and
    # archive members. This validates that every worker was configured as a
    # single-core VASP job with the requested NSW/SCF settings.
    local input_count=0
    local input_file archive_file member

    while IFS= read -r input_file; do
        assert_relax_input "${input_file}"
        input_count=$((input_count + 1))
    done < <(find procs/para -path "*/relax.in.*" -type f | sort)

    while IFS= read -r archive_file; do
        while IFS= read -r member; do
            tar_extract_member "${archive_file}" "${member}" > /tmp/pgopt-archived-relax.in
            assert_relax_input /tmp/pgopt-archived-relax.in
            input_count=$((input_count + 1))
        done < <(tar_list "${archive_file}" | grep "^relax[.]in[.]" || true)
    done < <(find procs/para -path "*/archive.tar.gz.*" -type f | sort)

    if [[ "${input_count}" -ne "${RELAX_COUNT}" ]]; then
        echo "Expected ${RELAX_COUNT} worker relax inputs, found ${input_count}." >&2
        copy_failure_artifacts
        exit 1
    fi
}

write_summary() {
    cat > summary.txt <<EOF
Pt4 PGOPT master/worker VASP integration
candidates_requested=${CANDIDATE_COUNT}
relaxed_structures=${RELAX_COUNT}
workers=${WORKER_COUNT}
omp_threads_per_worker=${OMP_NUM_THREADS}
mkl_threads_per_worker=${MKL_NUM_THREADS}
encut=${ENCUT}
prec=${PREC}
nsw=${NSW}
scf_iter=${SCF_ITER}
summary=$(cat "${summary_log}")
EOF
}

copy_archive_members() {
    local archive_file="$1"
    local member_pattern="$2"
    local output_dir="$3"
    local prefix="${4:-}"
    local member

    tar_list "${archive_file}" | grep -E "${member_pattern}" | while IFS= read -r member; do
        tar_extract_member "${archive_file}" "${member}" > "${output_dir}/${prefix}${member}"
    done
}

append_final_structures() {
    local output_file="$1"
    local final_file archive_file member

    : > "${output_file}"
    while IFS= read -r final_file; do
        cat "${final_file}" >> "${output_file}"
    done < <(find procs/para -path "*/final.xyz.*" -type f | sort)

    while IFS= read -r archive_file; do
        while IFS= read -r member; do
            tar_extract_member "${archive_file}" "${member}" >> "${output_file}"
        done < <(tar_list "${archive_file}" | grep "^final[.]xyz[.]" || true)
    done < <(find procs/para -path "*/archive.tar.gz.*" -type f | sort)
}

copy_proc_artifacts() {
    local artifact_dir="$1"
    local proc_dir proc_name archive_file raw_file member

    for proc_dir in procs/para/PROC*; do
        [[ -d "${proc_dir}" ]] || continue
        proc_name="$(basename "${proc_dir}")"
        mkdir -p "${artifact_dir}/procs/${proc_name}" "${artifact_dir}/raw-vasp/${proc_name}"

        cp "${proc_dir}"/REQUEST.old.* "${artifact_dir}/procs/${proc_name}/" 2>/dev/null || true
        cp "${proc_dir}"/RESPONSE.old.* "${artifact_dir}/procs/${proc_name}/" 2>/dev/null || true
        cp "${proc_dir}"/relax.in.* "${artifact_dir}/procs/${proc_name}/" 2>/dev/null || true
        cp "${proc_dir}"/relax.out.* "${artifact_dir}/procs/${proc_name}/" 2>/dev/null || true
        cp "${proc_dir}"/final.xyz.* "${artifact_dir}/procs/${proc_name}/" 2>/dev/null || true
        cp "${proc_dir}"/archive.tar.gz.* "${artifact_dir}/procs/${proc_name}/" 2>/dev/null || true

        for archive_file in "${proc_dir}"/archive.tar.gz.*; do
            [[ -e "${archive_file}" ]] || continue
            copy_archive_members "${archive_file}" "^(relax[.]in|relax[.]out|final[.]xyz)[.]" \
                "${artifact_dir}/procs/${proc_name}"
        done

        if [[ -s "${proc_dir}/restart.tar.gz" ]]; then
            for raw_file in INCAR KPOINTS POSCAR CONTCAR OUTCAR OSZICAR XDATCAR vasprun.xml proc-stat.txt; do
                member="$(tar_list "${proc_dir}/restart.tar.gz" | grep "/${raw_file}$" | tail -1 || true)"
                if [[ -n "${member}" ]]; then
                    tar_extract_member "${proc_dir}/restart.tar.gz" "${member}" \
                        > "${artifact_dir}/raw-vasp/${proc_name}/${raw_file}"
                fi
            done
        fi
    done
}

copy_artifacts() {
    [[ -n "${PGOPT_TEST_ARTIFACTS:-}" ]] || return 0

    local artifact_dir="${PGOPT_TEST_ARTIFACTS}/integration-pt4-parallel-relax-nsw20"
    local archive_file

    mkdir -p \
        "${artifact_dir}/logs" \
        "${artifact_dir}/master" \
        "${artifact_dir}/procs" \
        "${artifact_dir}/raw-vasp" \
        "${artifact_dir}/relaxed"

    cp summary.txt CMD-HISTORY para-template.json "${artifact_dir}/"
    cp tomaster/relax-1.0/para.json "${artifact_dir}/master/"
    cp tomaster/relax-1.0/run-master.sh "${artifact_dir}/master/"
    cp tomaster/relax-1.0/run-master.direct.out "${artifact_dir}/logs/"
    cp tomaster/relax-1.0/master.out.* "${artifact_dir}/logs/" 2>/dev/null || true
    cp master/1.0/par_shlog.txt.0 "${artifact_dir}/master/"
    cp master/1.0/par_log.txt.0 "${artifact_dir}/master/"
    cp master/1.0/par_runtime.json.0 "${artifact_dir}/master/"
    cp master/1.0/par_sources.xyz.0 "${artifact_dir}/master/" 2>/dev/null || true
    cp master/1.0/fil_structs.xyz.0 "${artifact_dir}/candidates.xyz" 2>/dev/null || true
    cp worker-*.out "${artifact_dir}/logs/" 2>/dev/null || true
    cp procs/para/PROC*/relax.out.* "${artifact_dir}/logs/" 2>/dev/null || true

    while IFS= read -r archive_file; do
        copy_archive_members "${archive_file}" "^relax[.]out[.]" "${artifact_dir}/logs" \
            "$(basename "$(dirname "${archive_file}")")-"
    done < <(find procs/para -path "*/archive.tar.gz.*" -type f | sort)

    append_final_structures "${artifact_dir}/relaxed/final.xyz"
    copy_proc_artifacts "${artifact_dir}"
}

run_workflow() {
    prepare_workspace
    print_settings
    configure_pgopt_workflow

    start_workers
    trap stop_workers EXIT
    run_master
    stop_workers
    wait_for_workers
    trap - EXIT

    validate_master_status
    assert_master_outputs_exist
    assert_scheduler_state
    assert_worker_responses
    assert_worker_inputs
    write_summary
    copy_artifacts
}

run_workflow

cat "${summary_log}"
echo "Pt4 master/worker integration ok: ${RELAX_COUNT} structures, ${WORKER_COUNT} one-core workers, NSW=${NSW}"
CONTAINER_SCRIPT
