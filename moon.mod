name = "local/moonexr"

version = "0.1.0"

private = true

license = "Apache-2.0"

readme = "README.md"

description = "Bounded native OpenEXR HDR channel interchange and windowed decoding"

preferred_target = "wasm-gc"

keywords = [ "openexr", "hdr", "image" ]

import {
  "moonbit-community/flate@0.10.0",
  "moonbitlang/async@0.22.5",
}
