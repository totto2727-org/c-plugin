default:
    @just --list

# Compile the Haskell library and CLI.
build:
    cabal build --offline all

# Cabal manifest and compiler checks.
check:
    cabal check
    fourmolu --mode check hs/lib hs/app hs/test hs/e2e/CPlugin hs/e2e/Spec.hs
    hlint hs/lib hs/app hs/test hs/e2e/CPlugin hs/e2e/Spec.hs
    cabal build --offline all

# Apply the standard Haskell formatter, then check lint suggestions.
fix:
    fourmolu --mode inplace hs/lib hs/app hs/test hs/e2e/CPlugin hs/e2e/Spec.hs
    hlint hs/lib hs/app hs/test hs/e2e/CPlugin hs/e2e/Spec.hs

# Run native product tests, without Docker.
test:
    cabal test --offline all --test-show-details=direct

# Build the caller-owned image used by the isolated CLI scenarios.
c-plugin-e2e-image:
    docker build --file hs/e2e/Dockerfile --tag c-plugin-e2e:local .

# Compile host-side acceptance tests without starting Docker containers.
e2e-check:
    cd hs/e2e && cabal build test:acceptance

e2e: c-plugin-e2e-image
    cd hs/e2e && cabal test acceptance --test-show-details=direct --test-options='--jobs=2 --randomize'

# Build the independent Nix package, including its product tests.
build-nix:
    nix build .#c-plugin

# Standard CI validation. Docker E2E remains an explicit local task.
ci: check test
