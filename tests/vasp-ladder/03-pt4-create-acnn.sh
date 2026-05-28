#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ./common.sh

require_docker_image

docker_run bash -lc '
set -euo pipefail
workdir=/tmp/pgopt-pt4-create
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

acnnmain pt4-create.json
test -s OUT-pt4-gas/fil_structs.xyz.0
test "$(grep -c "^4$" OUT-pt4-gas/fil_structs.xyz.0)" -ge 1
echo "Pt4 ACNN creation smoke ok"
'

