"""Original synthetic fixtures and independent official OpenEXR bit-level oracle."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
import OpenEXR
import numpy as np

CODECS = dict(none=OpenEXR.NO_COMPRESSION, rle=OpenEXR.RLE_COMPRESSION,
              zips=OpenEXR.ZIPS_COMPRESSION, zip=OpenEXR.ZIP_COMPRESSION)


def channels():
    y, x = np.indices((19, 7))
    r = ((x + y) / 4 - 1).astype(np.float16)
    r[0, :5] = [0, -0.0, np.inf, -np.inf, np.nan]
    z = (x * x - y * 5).astype(np.float32)
    z.view(np.uint32)[0, :4] = [0x80000000, 0x7fc00001, 0x7f800000, 0xff800000]
    ids = (np.uint32(4294967295) - (y * 7 + x).astype(np.uint32))
    return {"R": r, "Z": z, "object.id": ids}


def bit_arrays(ch):
    return {k: a.view(np.uint16 if a.dtype == np.float16 else np.uint32).reshape(-1).tolist()
            for k, a in ch.items()}


def generate(folder):
    folder.mkdir(parents=True, exist_ok=True)
    for name, codec in CODECS.items():
        header = {"compression": codec, "type": OpenEXR.scanlineimage,
                  "dataWindow": (np.array([-3, -5], np.int32), np.array([3, 13], np.int32)),
                  "displayWindow": (np.array([-10, -10], np.int32), np.array([10, 20], np.int32)),
                  "pixelAspectRatio": 1.5, "screenWindowCenter": np.array([0.25, -0.5], np.float32),
                  "screenWindowWidth": 2.0, "comments": "Original synthetic MoonEXR test"}
        OpenEXR.File(header, channels()).write(str(folder / f"{name}.exr"))
    header = {"compression": OpenEXR.ZIP_COMPRESSION, "lineOrder": OpenEXR.DECREASING_Y}
    OpenEXR.File(header, channels()).write(str(folder / "decreasing.exr"))
    # File flags must reject storage layouts outside the advertised profile.
    OpenEXR.File({"type": OpenEXR.tiledimage, "tiles": OpenEXR.TileDescription(), "compression": OpenEXR.ZIP_COMPRESSION},
                 channels()).write(str(folder / "tiled.exr"))


def run(cli, *args, success=True):
    result = subprocess.run([str(cli), *map(str, args)], text=True, capture_output=True)
    if success and result.returncode:
        raise AssertionError(result.stderr + result.stdout)
    if not success and not result.returncode:
        raise AssertionError("Unexpected success: " + " ".join(map(str, args)))
    return result.stdout


def read_official(path):
    file = OpenEXR.File(str(path), separate_channels=True)
    return file, {k: v.pixels for k, v in file.channels().items()}


def verify(cli):
    cli = cli.resolve()
    with tempfile.TemporaryDirectory(prefix="moonexr-oracle-") as directory:
        root = Path(directory)
        generate(root)
        for source in [*root.glob("*.exr")]:
            if source.stem == "tiled":
                run(cli, "bits", source, success=False)
                continue
            official, original = read_official(source)
            expected = bit_arrays(original)
            assert json.loads(run(cli, "bits", source)) == expected, source
            for codec in CODECS:
                output = root / f"rewritten-{source.stem}-{codec}.exr"
                run(cli, "rewrite", source, output, codec)
                result, pixels = read_official(output)
                assert bit_arrays(pixels) == expected, (source, codec)
                for key in ("dataWindow", "displayWindow", "pixelAspectRatio", "screenWindowCenter", "screenWindowWidth"):
                    assert np.array_equal(np.array(result.header()[key]), np.array(official.header()[key])), key
                if "comments" in official.header():
                    assert result.header()["comments"] == official.header()["comments"]
                run(cli, "rewrite", source, output, codec, success=False)
        demo = root / "demo.exr"
        run(cli, "demo", demo)
        _, pix = read_official(demo)
        assert pix["id"][0, 1] == np.uint32(4294967294)
        assert pix["R"][0, 0] == np.float16(-1)
        run(cli, "demo", demo, success=False)
    print("PASS: official OpenEXR -> MoonEXR and all four writer codecs -> official OpenEXR; exact bits/windows/metadata/refusals")


if __name__ == "__main__":
    if sys.argv[1] == "generate":
        generate(Path(sys.argv[2]))
    elif sys.argv[1] == "verify":
        verify(Path(sys.argv[2]))
    else:
        raise SystemExit("generate DIRECTORY | verify CLI")
