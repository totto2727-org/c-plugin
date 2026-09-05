name = "username/project"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/username/project"

license = "MIT"

keywords = [ "moonbit", "cli" ]

description = "A simple MoonBit command-line application"

// Leave both settings unset for synchronous, backend-neutral libraries.
//
// For async libraries, uncomment supported_targets and exactly one
// preferred_target. Choose the first viable preferred target in this order:
// wasm, js, native. If a dependency supports fewer targets, narrow both
// settings to match that dependency.
//
// supported_targets = "+native+js+wasm"
// preferred_target = "wasm"
// preferred_target = "js"
// preferred_target = "native"

source = "./src"
