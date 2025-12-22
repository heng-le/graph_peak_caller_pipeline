configfile: "config/config.yaml"

from pathlib import Path

INPUT_DIRS = config.get("input_dirs", [])
if isinstance(INPUT_DIRS, str):
    INPUT_DIRS = [INPUT_DIRS]
if not INPUT_DIRS or not isinstance(INPUT_DIRS, list):
    raise ValueError("config.yaml must define input_dirs as a non-empty list")

LOG_DIR = config.get("log_dir", "logs/slurm")  # you can keep this if you want
FILTER_SCRIPT = config.get("filter_script", "scripts/filter_gam.sh")
GAMTOJSON_SCRIPT = config.get("gamtojson_script", "scripts/gam_to_json.sh")

def discover_gams(dirs):
    gams = []
    for d in dirs:
        p = Path(d).resolve()
        if not p.exists():
            raise ValueError(f"Input dir not found: {p}")
        if not p.is_dir():
            raise ValueError(f"Input path is not a directory: {p}")

        for f in sorted(p.glob("*.gam")):
            if f.name.endswith("_filtered.gam"):
                continue
            if f.is_file():
                gams.append(str(f.resolve()))

    gams = sorted(set(gams))
    if not gams:
        raise ValueError("No .gam files found directly inside input_dirs")
    return gams

def filtered_path(gam_path: str) -> str:
    p = Path(gam_path)
    return str(p.with_name(p.stem + "_filtered" + p.suffix))

GAM_FILES = discover_gams(INPUT_DIRS)
FILTERED_GAMS = [filtered_path(g) for g in GAM_FILES]

FILTERED_JSONS = [
    str(Path(g).parent / "results" / "json" / (Path(g).stem + ".json"))
    for g in FILTERED_GAMS
]


rule all:
    input:
        FILTERED_JSONS

rule filter_gam:
    input:
        gam="{dir}/{stem}.gam"
    output:
        filtered="{dir}/{stem}_filtered.gam"
    threads: 4
    resources:
        mem_mb=20000,
        time="12:00:00"
    log:
        "{dir}/results/logs/{stem}.filter.log"
    wildcard_constraints:
        dir=".+",
        stem="[^/]+"
    shell:
        r"""
        mkdir -p "$(dirname {log})"
        bash scripts/filter_gam.sh {input.gam} {output.filtered} &> {log}
        """

rule gam_to_json:
    input:
        gam="{dir}/{stem}_filtered.gam"
    output:
        json="{dir}/results/json/{stem}_filtered.json"
    threads: 1
    resources:
        mem_mb=4000,
        time="02:00:00"
    log:
        "{dir}/results/logs/{stem}.gam_to_json.log"
    wildcard_constraints:
        dir=".+",
        stem="[^/]+"
    shell:
        r"""
        mkdir -p "$(dirname {output.json})" "$(dirname {log})"
        bash scripts/gam_to_json.sh {input.gam} {output.json} &> {log}
        """

