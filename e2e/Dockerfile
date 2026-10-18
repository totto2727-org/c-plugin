ARG BUILD_IMAGE=ghcr.io/totto2727-org/monorepo/sandbox-base@sha256:df12730051f9c1c920c250be35e04a56332dd9d31f2a2dc839042f74c90fe1c0
ARG RUNTIME_IMAGE=ubuntu:26.04@sha256:c098726dd9b9733f3e885f8de0ef375206a311b0a317eadc40d347b1115fb944

FROM ${BUILD_IMAGE} AS builder
USER root
RUN mkdir -p /build /out/runtime && chown -R sandbox:sandbox /build /out
USER sandbox
WORKDIR /build
COPY --chown=sandbox:sandbox flake.nix flake.lock package.yaml c-plugin.cabal cabal.project cabal.project.freeze ./
# Resolve the pinned toolchain and gitlib once, independently of source edits.
# This is an ordinary Cabal build inside nix develop, not a Nix package build.
RUN nix develop --command sh -c 'cabal update && cabal build all --only-dependencies -j2 --disable-executable-dynamic --disable-shared'
COPY --chown=sandbox:sandbox app ./app
COPY --chown=sandbox:sandbox lib ./lib
COPY --chown=sandbox:sandbox test ./test
COPY --chown=sandbox:sandbox LICENSE ./LICENSE
RUN nix develop --command sh -ec ' \
    hpack --force; \
    cabal build exe:c-plugin -j2 --disable-executable-dynamic --disable-shared; \
    cp "$(cabal list-bin exe:c-plugin)" /out/c-plugin; \
    ldd /out/c-plugin > /out/ldd.txt; \
    ! grep -q "not found" /out/ldd.txt; \
    grep -o "/nix/store/[^ /]*" /out/ldd.txt | sort -u > /out/library-roots; \
    nix-store --query --requisites $(cat /out/library-roots) > /out/runtime-paths; \
    while IFS= read -r path; do cp -a --parents "$path" /out/runtime; done < /out/runtime-paths'

FROM ${RUNTIME_IMAGE}
LABEL org.opencontainers.image.source="https://github.com/totto2727-org/c-plugin"
# Git supplies the official gitlib-cmdline backend and test fixtures.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git python3 coreutils && \
    rm -rf /var/lib/apt/lists/* && \
    useradd --system --create-home --home-dir /sandbox --shell /bin/bash sandbox && \
    mkdir -p /sandbox/.local/bin && chown -R sandbox:sandbox /sandbox
COPY --from=builder /out/runtime/ /
COPY --from=builder --chown=sandbox:sandbox /out/c-plugin /sandbox/.local/bin/c-plugin
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
USER sandbox
WORKDIR /sandbox
RUN /sandbox/.local/bin/c-plugin --numeric-version
# PID 1 must handle TERM so disposable cases do not wait for Docker's kill timeout.
ENTRYPOINT ["/bin/sh", "-c", "trap 'exit 0' TERM INT; while :; do sleep 3600 & wait \"$!\"; done"]
