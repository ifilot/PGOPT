# PGOPT/VASP Test Ladder

These tests increase coverage gradually, from image sanity checks to small Pt4 gas-phase VASP relaxations.

They assume the Docker image has already been built:

```bash
docker build --build-arg VASP_MAKE_JOBS=4 -t pgopt:local .
```

The proprietary VASP source and POTCAR archives must remain local-only inputs to that build and are ignored by git.

## Rungs

| Rung | Script | Approx. effort | What it proves |
| --- | --- | --- | --- |
| 0 | `00-image-sanity.sh` | seconds | VASP binaries, PBE POTCARs, and dynamic libs are present. |
| 1 | `01-h-singlepoint-svasp.sh` | seconds | PGOPT/SVASP can launch VASP with a real POTCAR and produce `OUTCAR`. |
| 2 | `02-pt4-hand-relax-svasp.sh` | ~10 seconds | A hand-written Pt4 gas-phase cluster can run one cheap VASP relaxation step. |
| 3 | `03-pt4-create-acnn.sh` | seconds | ACNN can generate and filter Pt4 gas-phase candidate structures. |
| 4 | `04-pt4-generated-relax-svasp.sh` | ~10 seconds | A generated Pt4 candidate can be relaxed through PGOPT/SVASP and VASP. |
| 5 | `05-pt4-generated-batch-svasp.sh` | ~30 seconds | Several generated Pt4 candidates can each run through the same VASP path. |

The relaxation rungs intentionally use cheap settings (`encut=150`, `prec=Low`, `nsw=1`, `scf(iter=10)`). They are not chemistry-quality calculations. They are integration tests that exercise structure generation, POTCAR lookup, VASP input generation, VASP execution, and output creation.

## Running

Run the fast ladder:

```bash
tests/vasp-ladder/run-ladder.sh
```

Include the slower generated-batch rung:

```bash
RUN_SLOW=1 tests/vasp-ladder/run-ladder.sh
```

Use a different image tag or thread count:

```bash
PGOPT_IMAGE=pgopt:local THREADS=4 RUN_SLOW=1 tests/vasp-ladder/run-ladder.sh
```

## Next Rungs

After this ladder is stable, the next useful additions are:

- A small PGOPT worker-orchestration test that runs 3-5 generated Pt4 candidates through the project’s `pgopt` command flow.
- A medium Pt4 campaign with higher `encut`, more SCF iterations, and `nsw=10-30`.
- A scaled-down version of the manual’s Pt7 gas-phase workflow once Pt4 orchestration is reliable.

