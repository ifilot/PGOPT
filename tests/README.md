# Tests

The test tree is split by intent:

- `unit/` contains the cheap smoke ladder for image contents, ACNN creation,
  and minimal SVASP/VASP calls.
- `integration/` contains end-to-end PGOPT/VASP workflows.
- `benchmark/` contains timing probes for Pt4 VASP layouts.

Hand-authored input files live in nearby `fixtures/` directories. The shell
scripts should mainly orchestrate the flow:

1. stage or render fixtures into a scratch directory,
2. run PGOPT, ACNN, SVASP, or VASP,
3. assert the expected outputs,
4. copy useful artifacts when `PGOPT_TEST_ARTIFACTS` is set.

Docker tests mount this `tests/` directory read-only inside the container as
`/pgopt-tests`, exposed through `PGOPT_TEST_FIXTURES`.
