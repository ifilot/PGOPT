# PGOPT Fork

Parallel global optimization of gas phase and surface systems.

This repository is a maintained fork of the original PGOPT project. It keeps
the legacy PGOPT/ACNN/STMOLE code usable in a containerized environment and
adds Docker-based VASP smoke and integration tests. The upstream repository is
treated as historical reference for this fork; the changes here are not
currently intended to be submitted upstream as pull requests.

## Upstream

The original project is PGOPT by Huanchen Zhai:

```text
https://github.com/hczhai/PGOPT
```

The original root README has been preserved at
[`docs/upstream-README.md`](docs/upstream-README.md). Use that file for the
legacy user guide and citation context. Use this root README for the current
state of this fork.

## Fork Changes

This fork currently adds or changes the following areas:

- A reproducible Docker build around the legacy Python 2 Anaconda environment.
- Containerized compilation of ACNN Fortran modules.
- Containerized compilation of VASP 5.4.1 from local source archives.
- A low-cost PGOPT/SVASP/VASP smoke ladder under `tests/unit`.
- A higher-order Pt4 PGOPT/VASP integration campaign under
  `tests/integration/pgopt-vasp-pt4`.
- Docker Desktop / WSL build compatibility for tracked executable symlinks.

The fork still depends on proprietary VASP source and potential data. Those
files must remain local-only inputs and should not be committed.

## Repository Layout

```text
ACNN/                                Core algorithms and ACNN entry point
PGOPT/                               PGOPT environment and workflow scripts
STMOLE/                              Interfaces to VASP and TURBOMOLE
tests/unit/                          Cheap PGOPT/SVASP/VASP smoke ladder
tests/integration/pgopt-vasp-pt4/    Pt4 integration campaign
docs/upstream-README.md              Preserved upstream README
Dockerfile                           Fork-maintained container build
```

## Docker Build

The Docker image expects the local VASP source and potential archives to be
available in the repository root. For example, this working copy uses:

```text
vasp.5.4.1.tar.gz
potpaw_PBE.54.tar.gz
```

Build the image:

```bash
docker build --build-arg VASP_MAKE_JOBS=4 -t pgopt:local .
```

The resulting image contains:

- Python 2 Anaconda packages needed by the legacy PGOPT code.
- Compiled ACNN Fortran modules.
- `vasp_gam`, `vasp_std`, and `vasp` under `/opt/vasp/bin`.
- PBE potentials under `/opt/vasp/potentials`.

## Tests

Run the default smoke ladder:

```bash
tests/unit/run-ladder.sh
```

Include the slower generated-batch smoke test:

```bash
RUN_SLOW=1 tests/unit/run-ladder.sh
```

Run the higher-order Pt4 integration campaign:

```bash
PGOPT_TEST_ARTIFACTS=OUT-integration-artifacts \
  tests/integration/pgopt-vasp-pt4/01-pt4-distribution-campaign.sh
```

The smoke tests intentionally use cheap VASP settings. They prove that PGOPT,
SVASP, POTCAR discovery, VASP execution, and selected ACNN paths work together;
they are not chemistry-quality production calculations.

## Notes For Maintainers

This fork is expected to diverge from upstream. Keep fork-specific instructions
in this root README, preserve upstream reference material under `docs/`, and use
`CHANGELOG.md` for notable local changes.

When adding tests or build behavior, prefer documenting the exact command that
was run and whether proprietary VASP inputs are required.

## Citations

If you use PGOPT or ACNN in scientific work, cite the original project papers:

Zhai, Huanchen, and Anastassia N. Alexandrova. "Ensemble-average representation
of Pt clusters in conditions of catalysis accessed through GPU accelerated deep
neural network fitting global optimization." *Journal of Chemical Theory and
Computation* **12** (2016): 6213-6226.

Zhai, Huanchen, and Anastassia N. Alexandrova. "Local Fluxionality of
Surface-Deposited Cluster Catalysts: The Case of Pt7 on Al2O3." *The Journal of
Physical Chemistry Letters* **9** (2018): 1696-1702.
