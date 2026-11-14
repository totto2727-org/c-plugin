name = "totto2727/c-plugin"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/totto2727-org/c-plugin"

license = "MIT"

description = "Native MoonBit plugin skill manager"

source = "src"

preferred_target = "native"

supported_targets = "native"

// Raise transitive dependency floors to versions with current manifests.
// crater-layout 0.19.2 uses CSS #cfg imports unsupported by moon-nix 026f5a4.
import {
  "mizchi/crater-layout@0.19.1",
  "mizchi/signals@0.6.6",
  "mizchi/tui-terminal-buffer@0.1.4",
  "mizchi/tui@0.10.2",
  "moonbitlang/async@0.22.9",
  "moonbitlang/regexp@0.3.7",
  "totto2727/admiral@0.6.5",
}
