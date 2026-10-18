default:
    @just --list

# Compile the Haskell library and CLI.
build: generate
    cabal build --offline all

# Cabal manifest and compiler checks.
check: generate
    cabal check
    fourmolu --mode check lib app test e2e/CPlugin e2e/Spec.hs
    hlint lib app test e2e/CPlugin e2e/Spec.hs
    cabal build --offline all

# Apply the standard Haskell formatter, then check lint suggestions.
fix:
    fourmolu --mode inplace lib app test e2e/CPlugin e2e/Spec.hs
    hlint lib app test e2e/CPlugin e2e/Spec.hs

# Run native product tests, without Docker.
test: generate
    cabal test --offline all --test-show-details=direct

# Build the caller-owned image used by the isolated CLI scenarios.
c-plugin-e2e-image:
    docker build --file e2e/Dockerfile --tag c-plugin-e2e:local .

# Compile host-side acceptance tests without starting Docker containers.
e2e-check: generate
    cd e2e && cabal build test:acceptance

e2e: c-plugin-e2e-image
    cd e2e && cabal test acceptance --test-show-details=direct --test-options='--jobs=2 --randomize'

# Build the independent Nix package, including its product tests.
build-nix:
    nix build .#c-plugin

# Standard CI validation. Docker E2E remains an explicit local task.
ci: check test

# Generate Cabal manifests from the maintained package definitions.
generate:
    hpack
    hpack e2e
