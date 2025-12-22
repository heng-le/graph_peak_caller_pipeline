configfile: "config/config.yaml"

from collections import Counter
from pathlib import Path
import os

INPUT_DIRS = config.get("input_dirs", [])
if isinstance(INPUT_DIRS, str):
    INPUT_DIRS = [INPUT_DIRS]
if not INPUT_DIRS:
    raise ValueError("config.yaml must define input_dirs with one or more directories")
if not isinstance(INPUT_DIRS, list):
    raise ValueError("input_dirs must be a list of directory paths")

LOG_DIR = config.get("log_dir", "logs/slurm")
VG_DIR = config.get("vg_dir")
if VG_DIR:
    VG_BIN = str(Path(VG_DIR) / "vg")
else:
    VG_BIN = "vg"


def discover_gam_files(input_dirs):
    gam_files = []
    for dir_path in input_dirs:
        p = Path(dir_path)
        if not p.exists():
            raise ValueError(f"Input dir not found: {dir_path}")
        if not p.is_dir():
            raise ValueError(f"Input dir is not a directory: {dir_path}")
        for gam in sorted(p.rglob("*.gam")):
            if gam.is_file():
                gam_files.append(str(gam.resolve()))
    gam_files = sorted(set(gam_files))
    if not gam_files:
        raise ValueError("No .gam files found in input_dirs")
    return gam_files


def sample_from_path(path):
    return Path(path).stem


INPUT_DIRS = [str(Path(p).resolve()) for p in INPUT_DIRS]

parent_dirs = [str(Path(p).parent) for p in INPUT_DIRS]
common_parent = Path(os.path.commonpath(parent_dirs))
RESULTS_DIR = str(common_parent / "results")

GAM_FILES = discover_gam_files(INPUT_DIRS)
sample_names = [sample_from_path(p) for p in GAM_FILES]
counts = Counter(sample_names)
dups = sorted([name for name, count in counts.items() if count > 1])
if dups:
    raise ValueError(f"Duplicate sample names from .gam files: {', '.join(dups)}")

SAMPLES = dict(zip(sample_names, GAM_FILES))
MANIFEST = f"{RESULTS_DIR}/input_manifest.tsv"


rule all:
    input:
        MANIFEST


rule input_manifest:
    input:
        GAM_FILES
    output:
        MANIFEST
    log:
        f"{LOG_DIR}/input_manifest.log"
    threads: 1
    resources:
        mem_mb=512,
        time="00:05:00"
    shell:
        "python scripts/write_input_manifest.py --output {output} {input}"
