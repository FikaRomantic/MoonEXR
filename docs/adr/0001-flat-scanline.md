# Preserve sample bits in bounded flat scanline images

MoonEXR stores typed channel bits and supports only single-part, non-deep scanline images with unit sampling in the first release. A universal floating-point pixel model would silently change UINT and NaN payloads; complete EXR support would require distinct deep/tile/part models. Unsupported storage modes are rejected before decoding, while window selection retains absolute coordinates. Whole-file input and chunk workspaces remain bounded but are not disk streaming.
