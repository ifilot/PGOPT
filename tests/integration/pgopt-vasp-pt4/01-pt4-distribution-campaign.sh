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
    bash -s <<'CONTAINER_SCRIPT'
set -euo pipefail

workdir=/tmp/pgopt-pt4-distribution-campaign
rm -rf "${workdir}"
mkdir -p "${workdir}"
cd "${workdir}"
fixture_dir="${PGOPT_TEST_FIXTURES}/integration/pgopt-vasp-pt4/fixtures/distribution-campaign"

render_template() {
    local input_file="$1"
    local output_file="$2"
    local idx="${3:-}"

    sed \
        -e "s/@CANDIDATE_COUNT@/${CANDIDATE_COUNT}/g" \
        -e "s/@RELAX_COUNT@/${RELAX_COUNT}/g" \
        -e "s/@ENCUT@/${ENCUT}/g" \
        -e "s/@SCF_ITER@/${SCF_ITER}/g" \
        -e "s/@NSW@/${NSW}/g" \
        -e "s/@IDX@/${idx}/g" \
        "${input_file}" > "${output_file}"
}

stage_creation_request() {
    render_template "${fixture_dir}/pt4-create.json.template" pt4-create.json
}

generate_candidates() {
    # This is the PGOPT/ACNN creation stage. Energies in this candidate file are
    # placeholders; the VASP-derived energies appear after relaxation.
    acnnmain pt4-create.json > create.out
    test -s OUT-pt4-gas/fil_structs.xyz.0
    structure_count="$(grep -c "^4$" OUT-pt4-gas/fil_structs.xyz.0)"
    test "${structure_count}" -ge "${RELAX_COUNT}"
}

draw_candidates() {
    render_template "${fixture_dir}/draw-candidates.json.template" draw-candidates.json

    acnnmain draw-candidates.json > draw-candidates.out
    test -s report/pt4-candidates.pdf
}

extract_candidate() {
    local idx="$1"
    local start stop

    start=$((idx * 6 + 1))
    stop=$((start + 5))
    awk -v start="${start}" -v stop="${stop}" "NR>=start && NR<=stop {print}" \
        OUT-pt4-gas/fil_structs.xyz.0 > "coords-${idx}.xyz"
    test -s "coords-${idx}.xyz"
}

write_svasp_input() {
    local idx="$1"

    render_template "${fixture_dir}/svasp.template.in" "svasp-${idx}.in" "${idx}"
}

run_relaxation() {
    local idx="$1"

    SVASP < "svasp-${idx}.in" > "svasp-${idx}.out" 2>&1
    tail -30 "svasp-${idx}.out"
}

assert_relaxation_outputs() {
    local idx="$1"
    local chk="pt4-relax-${idx}.chk"

    grep -q "Normal termination" "svasp-${idx}.out"
    test -s "${chk}/POTCAR"
    test -s "${chk}/OUTCAR"
    test -s "${chk}/CONTCAR"
    test -s "${chk}/final.xyz"
}

collect_relaxation() {
    local idx="$1"

    cat "pt4-relax-${idx}.chk/final.xyz" >> relaxed/final.xyz
    cp "pt4-relax-${idx}.chk/CONTCAR" "relaxed/CONTCAR-${idx}"
}

relax_selected_candidates() {
    mkdir -p relaxed
    : > relaxed/final.xyz

    local idx=0
    while [[ "${idx}" -lt "${RELAX_COUNT}" ]]; do
        extract_candidate "${idx}"
        write_svasp_input "${idx}"
        run_relaxation "${idx}"
        assert_relaxation_outputs "${idx}"
        collect_relaxation "${idx}"
        idx=$((idx + 1))
    done
}

draw_relaxed_structures() {
    render_template "${fixture_dir}/draw-relaxed.json.template" draw-relaxed.json

    acnnmain draw-relaxed.json > draw-relaxed.out
    test -s report/pt4-relaxed.pdf
}

write_summary() {
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
}

copy_artifacts() {
    [[ -n "${PGOPT_TEST_ARTIFACTS:-}" ]] || return 0

    local artifact_dir="${PGOPT_TEST_ARTIFACTS}/integration-pt4-distribution-campaign"
    mkdir -p "${artifact_dir}/logs" "${artifact_dir}/relaxed"
    cp summary.txt "${artifact_dir}/"
    cp create.out draw-candidates.out draw-relaxed.out "${artifact_dir}/logs/"
    cp OUT-pt4-gas/fil_structs.xyz.0 "${artifact_dir}/candidates.xyz"
    cp report/pt4-candidates.pdf "${artifact_dir}/"
    cp relaxed/final.xyz "${artifact_dir}/relaxed/final.xyz"
    cp relaxed/CONTCAR-* "${artifact_dir}/relaxed/"
    cp report/pt4-relaxed.pdf "${artifact_dir}/relaxed/"
    cp svasp-*.out "${artifact_dir}/logs/"
}

stage_creation_request
generate_candidates
draw_candidates
relax_selected_candidates
draw_relaxed_structures
write_summary
copy_artifacts

echo "Pt4 integration campaign ok: ${structure_count} candidates, ${RELAX_COUNT} VASP relaxations"
CONTAINER_SCRIPT
