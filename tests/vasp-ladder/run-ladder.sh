#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

fast_tests=(
  ./00-image-sanity.sh
  ./01-h-singlepoint-svasp.sh
  ./02-pt4-hand-relax-svasp.sh
  ./03-pt4-create-acnn.sh
  ./04-pt4-generated-relax-svasp.sh
)

slow_tests=(
  ./05-pt4-generated-batch-svasp.sh
)

for test_script in "${fast_tests[@]}"; do
    echo "==> ${test_script}"
    "${test_script}"
done

if [[ "${RUN_SLOW:-0}" == "1" ]]; then
    for test_script in "${slow_tests[@]}"; do
        echo "==> ${test_script}"
        "${test_script}"
    done
else
    echo "Skipping slow tests. Set RUN_SLOW=1 to include them."
fi

