# Original synthetic fixtures

Created by `scripts/interop.py generate fixtures` with official OpenEXR 3.4.2.
No photographs or third-party test assets. Files contain original numeric ramps,
UINT32 boundaries, signed zero, infinities, NaN payloads and negative data origins.
Tiled is a deliberate rejection fixture. Data and generator are Apache-2.0.
`fixture_data_wbtest.mbt` embeds these binary DATA for portable backend tests and
is excluded from effective source line counts. Rebuild with `scripts/embed_fixtures.py`.
