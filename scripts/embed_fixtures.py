"""Mechanically embed original EXR fixture DATA; excluded from source LOC."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
out = ["// Generated original fixture DATA, not effective code.\n", "fn official_fixture(name : String) -> Bytes {\n  match name {\n"]
for path in sorted((root / "fixtures").glob("*.exr")):
    data = path.read_bytes()
    out.append(f'    "{path.stem}" => {{\n      let out = sink()\n')
    for start in range(0, len(data), 256):
        literal = ''.join(f"\\x{v:02x}" for v in data[start:start + 256])
        out.append(f'      out.raw(b"{literal}")\n')
    out.append("      out.finish()\n    }\n")
out.append('    _ => abort("unknown fixture")\n  }\n}\n')
(root / "fixture_data_wbtest.mbt").write_text(''.join(out), encoding="utf-8")
