# Changelog

## 0.1.0 — 2026-11-01

- 位级样本差异与数值误差：Plane::compare_samples
- 对象掩膜下的有限值统计：Plane::masked_statistics
- 增加边界回归、可运行集成示例和CI步骤。

### Initial implementation

- Original flat scanline EXR reader/writer for typed HALF/FLOAT/UINT channels.
- NONE/RLE/ZIPS/ZIP, checked zlib framing, predictor, raw fallback and offset directories.
- Exact bit preservation, absolute-coordinate selection, chunk-backed scans and atomic incremental writes.
- Metadata/layer/region processing, explicit conversion, statistics and diagnostic RGBA previews.
- Four-backend tests, official OpenEXR bidirectional oracle, three application scenarios and scale workload.
- Public package namespace: FikaRomantic/moonexr; reproducible compiler/core version and independent OpenEXR validation in CI.
