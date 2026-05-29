# PGOPT/VASP Benchmarks

These scripts are performance probes, not convergence tests. They run small,
repeatable Pt4 VASP calculations and write timing summaries plus raw VASP
outputs to an artifact directory. Defaults are intentionally light: `ENCUT=150`,
`PREC=Low`, one ionic step, and ten electronic iterations.

Hand-authored benchmark inputs live under `fixtures/pt4-single-relax/`: a fixed
Pt4 starting geometry and an `SVASP` template. The script renders the template
per benchmark case and keeps the raw VASP outputs in the artifact bundle.

## Pt4 Single Relaxation

```bash
PGOPT_TEST_ARTIFACTS=OUT-benchmark-artifacts \
  tests/benchmark/01-pt4-single-relax-benchmark.sh
```

The benchmark uses a fixed Pt4 starting geometry and tries several layouts:

- direct `vasp_gam` with `OMP_NUM_THREADS` set to 1, 2, 4, and 8
- direct `vasp_gam` with `OMP_NUM_THREADS=4` plus selected `NCORE` values
- direct `vasp_gam` with `OMP_NUM_THREADS=4` plus selected `NPAR` values
- an MPI launcher probe, recorded as skipped unless `mpirun` exists in the image

Current VASP guidance favors `NCORE` over the older `NPAR` parameter because it
is easier to reason about. For this Docker image, MPI cases are expected to skip:
the image currently builds serial/gamma VASP and does not install an MPI
launcher.
