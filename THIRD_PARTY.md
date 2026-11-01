# Sources and licenses

- Original MoonBit implementation based on the [OpenEXR file layout](https://openexr.com/en/latest/OpenEXRFileLayout.html). No OpenEXR C++/Python implementation is embedded or linked by the runtime library.
- [OpenEXR](https://github.com/AcademySoftwareFoundation/openexr), BSD-3-Clause: independent development/test oracle only. Generated fixtures contain original synthetic pixel data; generator scripts identify their provenance.
- moonbit-community/flate 0.10.0, Apache-2.0: pure MoonBit raw DEFLATE codec.
- moonbitlang/async 0.22.5, Apache-2.0: native CLI file IO only.
- tools/windows: process-local argv adapter reused from the user's MoonORC/MoonH5 projects under Apache-2.0; adapter code is auxiliary and excluded from effective MoonBit source totals.

AI assisted design, implementation, tests and documentation. Contest reports and proposal facts are kept outside tracked source. No private or commercial third-party source was imported.

- [NumPy 2.3.4](https://github.com/numpy/numpy/tree/v2.3.4), [BSD-3-Clause](https://github.com/numpy/numpy/blob/v2.3.4/LICENSE.txt): independent development oracle arrays only, not a MoonBit runtime dependency. Installed wheels may include their own third-party notices; no wheel or Python library source is redistributed in this package.
