ARG SANDBOX_IMAGE=ghcr.io/totto2727-org/monorepo/sandbox-base@sha256:df12730051f9c1c920c250be35e04a56332dd9d31f2a2dc839042f74c90fe1c0
ARG HASKELL_IMAGE=haskell:9.4.8-slim@sha256:7ba95312dbfaf2a00f4c9899cd1f67eade14035398287a3627c3574a9d3e1d35

FROM ${HASKELL_IMAGE} AS builder
WORKDIR /build
COPY c-plugin.cabal cabal.project cabal.project.freeze ./
RUN cabal update
COPY hs-src ./hs-src
COPY app ./app
COPY LICENSE ./LICENSE
RUN cabal build exe:c-plugin --enable-executable-static --disable-shared --ghc-options="-optl-static" && \
    mkdir -p /out && \
    cp "$(cabal list-bin exe:c-plugin)" /out/c-plugin

FROM ${SANDBOX_IMAGE}
LABEL org.opencontainers.image.source="https://github.com/totto2727-org/c-plugin"
USER sandbox
WORKDIR /sandbox
COPY --from=builder --chown=sandbox:sandbox /out/c-plugin /sandbox/.local/bin/c-plugin
RUN /sandbox/.local/bin/c-plugin --numeric-version
ENTRYPOINT ["sleep", "infinity"]
