# HDR channel interchange

OpenEXR exchanges named numerical image channels in a coordinate window. An image channel is not a display-ready colour by itself.

## Language

**Data window**: The inclusive rectangle whose coordinates have stored samples.
_Avoid_: Canvas, display window

**Display window**: The intended complete image rectangle, which can extend beyond the stored data window.
_Avoid_: Crop

**Channel**: A named plane of samples with one declared numerical representation.
_Avoid_: Component when referring to a named layer

**Chunk**: A compressed group of scanlines represented by one file offset entry.
_Avoid_: Tile, batch

**Region**: An inclusive requested rectangle in image coordinates.
_Avoid_: Relative offset

**Sample bits**: The stored IEEE or integer bit representation of a pixel value.
_Avoid_: Display colour
