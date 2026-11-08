mod e2e 'e2e.just'
mod nix 'nix.just'

alias generate := e2e::_generate

default:
    @just --list --list-submodules

# Compile the Haskell library and CLI.
build: e2e::_generate
    cabal build --offline all

# Cabal manifest and compiler checks.
check: e2e::_generate
    cabal check
    fourmolu --mode check lib app test e2e/CPlugin e2e/Spec.hs
    hlint lib app test e2e/CPlugin e2e/Spec.hs
    cabal build --offline all

# Apply the standard Haskell formatter, then check lint suggestions.
fix:
    fourmolu --mode inplace lib app test e2e/CPlugin e2e/Spec.hs
    hlint lib app test e2e/CPlugin e2e/Spec.hs

# Run native product tests, without Docker.
test: e2e::_generate
    cabal test --offline all --test-show-details=direct

# Standard CI validation. Docker E2E remains an explicit local task.
ci: check test
