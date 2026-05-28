FROM continuumio/anaconda:latest@sha256:07f924ebe3cb59ae45044850078efb2994e24a654405a1e643f6b8945826d44c

SHELL ["/bin/bash", "-lc"]

# The legacy Python 2 Anaconda image used by PGOPT relies on archived
# Debian package sources. Enable the snapshot sources already present
# in the image and disable Release-file expiry checks.
RUN sed -i -E \
      's|^# deb http://snapshot.debian.org|deb http://snapshot.debian.org|; \
       s|^deb http://deb.debian.org/debian|# deb http://deb.debian.org/debian|; \
       s|^deb http://security.debian.org/debian-security|# deb http://security.debian.org/debian-security|' \
      /etc/apt/sources.list \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get -y install --no-install-recommends \
      gfortran \
      g++ \
      make \
      nano \
      libfftw3-dev \
      makedepf90 \
      rsync \
      vim \
    && rm -rf /var/lib/apt/lists/*

# Use explicit Python 2 compatible package versions so the image remains
# buildable even as current package indexes move on from Python 2.
RUN pip install \
      "Theano==1.0.5" \
      "reportlab==3.4.0" \
      "dill==0.2.9" \
    && conda install -y pygpu \
    && conda clean -tipsy

ENV BASE=/root/PGOPT-PROGRAMS \
    STMOLE_HOME=/root/PGOPT-PROGRAMS/STMOLE \
    ACNNHOME=/root/PGOPT-PROGRAMS/ACNN \
    PGOPTHOME=/root/PGOPT-PROGRAMS/PGOPT \
    VASPHOME=/opt/vasp/bin \
    VASP_PP_PATH=/opt/vasp/potentials \
    OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    PATH=/opt/vasp/bin:/root/PGOPT-PROGRAMS/STMOLE:/root/PGOPT-PROGRAMS/PGOPT:/root/PGOPT-PROGRAMS/ACNN:$PATH

RUN printf '%s\n' \
      'export BASE=/root/PGOPT-PROGRAMS' \
      'export STMOLE_HOME=$BASE/STMOLE' \
      'export ACNNHOME=$BASE/ACNN' \
      'export PGOPTHOME=$BASE/PGOPT' \
      'export VASPHOME=/opt/vasp/bin' \
      'export VASP_PP_PATH=/opt/vasp/potentials' \
      'export OMP_NUM_THREADS=${OMP_NUM_THREADS:-1}' \
      'export MKL_NUM_THREADS=${MKL_NUM_THREADS:-$OMP_NUM_THREADS}' \
      'export PATH=$VASPHOME:$STMOLE_HOME:$PGOPTHOME:$ACNNHOME:$PATH' \
      > /etc/profile.d/pgopt.sh \
    && cat /etc/profile.d/pgopt.sh >> /root/.bashrc

WORKDIR /root/PGOPT-PROGRAMS
COPY . /root/PGOPT-PROGRAMS

RUN make -C /root/PGOPT-PROGRAMS/ACNN/formod

ARG VASP_MAKE_JOBS=4
RUN mkdir -p /opt/vasp/build /opt/vasp/bin /opt/vasp/potentials \
    && tar -xzf /root/PGOPT-PROGRAMS/vasp.5.4.1.tar.gz -C /opt/vasp/build --strip-components=1 \
    && shopt -s nullglob \
    && for archive in /root/PGOPT-PROGRAMS/potpaw_PBE*.tar.gz; do \
         mkdir -p /opt/vasp/potentials/potpaw_PBE; \
         tar -xzf "${archive}" -C /opt/vasp/potentials/potpaw_PBE; \
       done \
    && for archive in /root/PGOPT-PROGRAMS/potpaw_GGA*.tar.gz; do \
         mkdir -p /opt/vasp/potentials/potpaw_GGA; \
         tar -xzf "${archive}" -C /opt/vasp/potentials/potpaw_GGA; \
       done \
    && for archive in /root/PGOPT-PROGRAMS/potentials*.tar.gz; do \
         tar -xzf "${archive}" -C /opt/vasp/potentials; \
       done \
    && for potential in /root/PGOPT-PROGRAMS/potentials* /root/PGOPT-PROGRAMS/potpaw* /root/PGOPT-PROGRAMS/POTCAR; do \
         [ -e "${potential}" ] || continue; \
         [[ "${potential}" != *.tar.gz ]] || continue; \
         cp -a "${potential}" /opt/vasp/potentials/; \
       done \
    && cd /opt/vasp/build \
    && sed -i 's/mkdir build\/$@/mkdir -p build\/$@/' makefile \
    && sed -i 's|\$(MAKE) -C \$@|\$(MAKE) -C \$@ -j1|' src/makefile \
    && printf '%s\n' \
      'CPP_OPTIONS= -DHOST=\"PGOPT_DOCKER_OMP\" -DIFC \' \
      '             -DCACHE_SIZE=4000 -Davoidalloc \' \
      '             -DnoAugXCmeta -Duse_bse_te' \
      '' \
      'CPP        = gcc -E -P -C $*$(FUFFIX) >$*$(SUFFIX) $(CPP_OPTIONS)' \
      'FC         = gfortran' \
      'FCL        = gfortran' \
      'CC_LIB     = gcc' \
      'F77        = gfortran' \
      '' \
      'FREE       = -ffree-form -ffree-line-length-none' \
      'FFLAGS     = -fopenmp -ffpe-summary=none' \
      'FFLAGS_F77 = $(FFLAGS)' \
      'OFLAG      = -O2 -march=x86-64 -mtune=generic' \
      'OFLAG_IN   = $(OFLAG)' \
      'DEBUG      = -O0' \
      '' \
      'OBJECTS    = fft3dfurth.o fft3dlib.o' \
      'OBJECTS_O1 += fft3dfurth.o fftw3d.o fftmpi.o fftmpiw.o chi.o' \
      'OBJECTS_O2 += fft3dlib.o' \
      'INCS       = -I/usr/include -I/opt/conda/include' \
      '' \
      'MKLROOT    = /opt/conda' \
      'LAPACK     = -Wl,--start-group $(MKLROOT)/lib/libmkl_gf_lp64.so $(MKLROOT)/lib/libmkl_gnu_thread.so $(MKLROOT)/lib/libmkl_core.so -Wl,--end-group' \
      'BLAS       =' \
      'LLIBS      = $(LAPACK) -lgomp -lpthread -lm -ldl -Wl,-rpath,/usr/lib/x86_64-linux-gnu -Wl,-rpath,$(MKLROOT)/lib' \
      '' \
      'CPP_LIB    = $(CPP)' \
      'FC_LIB     = $(FC)' \
      'CFLAGS_LIB = -O2' \
      'FFLAGS_LIB = -O1' \
      'FREE_LIB   = $(FREE)' \
      'OBJECTS_LIB= linpack_double.o getshmem.o' \
      '' \
      'SRCDIR     = ../../src' \
      'BINDIR     = ../../bin' \
      > makefile.include \
    && for target in gam std; do \
         mkdir -p "build/${target}" \
         && cp src/makefile src/.objects makefile.include "build/${target}/" \
         && make -C "build/${target}" VERSION="${target}" sources \
         && make -C "build/${target}" VERSION="${target}" dependencies -j1 \
         && make -C "build/${target}" VERSION="${target}" all -j"${VASP_MAKE_JOBS}" \
         && if [ -x "bin/vasp_${target}" ]; then \
              cp "bin/vasp_${target}" "/opt/vasp/bin/vasp_${target}"; \
            elif [ -x "build/${target}/vasp" ]; then \
              cp "build/${target}/vasp" "/opt/vasp/bin/vasp_${target}"; \
            else \
              echo "VASP ${target} executable was not produced" >&2; \
              exit 1; \
            fi; \
       done \
    && test -x /opt/vasp/bin/vasp_gam \
    && test -x /opt/vasp/bin/vasp_std \
    && ls -lh /opt/vasp/bin \
    && ln -sf vasp_std /opt/vasp/bin/vasp \
    && rm -rf /opt/vasp/build /root/.cache

WORKDIR /root/PGOPT-PROGRAMS/ACNN/tests/structure_generation
CMD ["/bin/bash"]
