"""Read-only effective-source, history, tracked-file and package hygiene audit."""
from pathlib import Path
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
git = ["git", "-c", f"safe.directory={root.as_posix()}"]
tracked = subprocess.check_output(git + ["ls-files", "-z"], cwd=root).decode().split("\0")
counts = dict(library=0, tests=0, examples=0, cli=0)
for name in filter(None, tracked):
    parts = set(Path(name).parts)
    if {"_local", "_build", ".mooncakes", ".venv", "__pycache__"}.intersection(parts):
        raise SystemExit("Private/generated material tracked: " + name)
    if any(s in name for s in ("申报书", "审查报告", "辅助报告", "汇总报告")):
        raise SystemExit("Private contest material tracked: " + name)
    if not name.endswith(".mbt") or name == "fixture_data_wbtest.mbt":
        continue
    category = "tests" if name.endswith("test.mbt") else "examples" if name.startswith("examples/") else "cli" if name.startswith("cmd/") else "library"
    counts[category] += sum(bool(line.strip()) and not line.lstrip().startswith("//")
                            for line in (root / name).read_text(encoding="utf-8").splitlines())
total = sum(counts.values())
commits = int(subprocess.check_output(git + ["rev-list", "--count", "HEAD"], cwd=root))
print({**counts, "effective_MoonBit_total": total, "commits": commits,
       "generated_fixture_data_excluded": True})
if total <= 4000 or commits <= 30:
    raise SystemExit("Require >4000 effective MoonBit lines and >30 meaningful commits")
for archive in (root / "_build" / "publish").glob("*.zip"):
    with zipfile.ZipFile(archive) as package:
        for name in package.namelist():
            parts = set(name.replace("\\", "/").split("/"))
            if {"_local", ".git", ".mooncakes", ".venv", "__pycache__"}.intersection(parts) or any(
                    s in name for s in ("申报书", "审查报告", "辅助报告", "汇总报告")):
                raise SystemExit("Private material in package: " + name)
print("Source/history and any local package ZIPs passed hygiene checks; no upload performed")
