default:
    @just --list nix

# Build the independent Nix package, including its product tests.
build:
    nix build .#c-plugin
