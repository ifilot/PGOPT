#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ./common.sh

require_docker_image

docker_run bash -lc '
set -euo pipefail
test -x /opt/vasp/bin/vasp_gam
test -x /opt/vasp/bin/vasp_std
test -s /opt/vasp/potentials/potpaw_PBE/H/POTCAR
test "$(find /opt/vasp/potentials/potpaw_PBE -maxdepth 2 -name POTCAR | wc -l)" -gt 100
! ldd /opt/vasp/bin/vasp_gam | grep "not found"
ldd /opt/vasp/bin/vasp_gam | grep "libgfortran.so.5"
echo "image sanity ok"
'

