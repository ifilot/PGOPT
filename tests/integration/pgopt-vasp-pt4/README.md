# PGOPT/VASP Pt4 Integration Campaign

This is the higher-order integration layer. It is separate from the cheap smoke ladder in `tests/unit`.

The campaign exercises the full Pt4 path:

1. Generate a distribution of Pt4 gas-phase candidates with ACNN.
2. Draw the generated candidate distribution.
3. Send several generated candidates through `SVASP`, which writes VASP inputs and calls VASP.
4. Collect the relaxed final structures.
5. Draw a second report for the relaxed subset.

The default settings are intentionally more realistic than the smoke tests:

```text
CANDIDATE_COUNT=12
RELAX_COUNT=3
ENCUT=350
PREC=Normal
NSW=1
SCF_ITER=20
```

This is still not a production optimization campaign; it is a compact integration assessment that proves PGOPT, ACNN, POTCAR discovery, VASP execution, and report production work together.

## Running

```bash
PGOPT_TEST_ARTIFACTS=OUT-integration-artifacts \
  tests/integration/pgopt-vasp-pt4/01-pt4-distribution-campaign.sh
```

Useful runtime knobs:

```bash
RELAX_COUNT=2 THREADS=4 PGOPT_TEST_ARTIFACTS=OUT-integration-artifacts \
  tests/integration/pgopt-vasp-pt4/01-pt4-distribution-campaign.sh
```

## Artifacts

The artifact bundle is written to:

```text
OUT-integration-artifacts/integration-pt4-distribution-campaign/
```

It contains:

- `summary.txt`
- `candidates.xyz`
- `pt4-candidates.pdf`
- `relaxed/final.xyz`
- `relaxed/CONTCAR-*`
- `relaxed/pt4-relaxed.pdf`
- `logs/*.out`

Proprietary `POTCAR` and full VASP `OUTCAR` files are intentionally not copied into the artifact bundle.

## Master/Worker Parallel Relaxation Check

The second integration test exercises PGOPT's own master/worker scheduler. It
generates Pt4 candidates, creates one-core `PROC*` workers, lets the master
assign structures through `REQUEST` files, and verifies that workers report back
through `RESPONSE` files. This matches the best throughput mode seen in the Pt4
benchmarks: many independent single-core VASP jobs instead of a few multi-thread
jobs.

```bash
PGOPT_TEST_ARTIFACTS=OUT-integration-artifacts \
  tests/integration/pgopt-vasp-pt4/02-pt4-parallel-relax-nsw20.sh
```

Defaults:

```text
CANDIDATE_COUNT=8
RELAX_COUNT=4
WORKER_COUNT=4
THREADS=1
ENCUT=150
PREC=Low
NSW=20
SCF_ITER=20
```

For a more realistic cutoff while keeping the same scheduling model:

```bash
ENCUT=350 PREC=Normal PGOPT_TEST_ARTIFACTS=OUT-integration-artifacts \
  tests/integration/pgopt-vasp-pt4/02-pt4-parallel-relax-nsw20.sh
```

Artifacts are written to:

```text
OUT-integration-artifacts/integration-pt4-parallel-relax-nsw20/
```

The bundle includes the PGOPT master logs, runtime JSON, worker request/response
files, worker `relax.in`/`relax.out` files, archived worker bundles, and
combined final structures. Proprietary `POTCAR` files are not copied into the
artifact bundle.
