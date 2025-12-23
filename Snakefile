from pathlib import Path
import re
from collections import defaultdict

configfile: "config/config.yaml"

INPUT_DIRS = config.get("input_dirs", [])
if isinstance(INPUT_DIRS, str):
    INPUT_DIRS = [INPUT_DIRS]
if not INPUT_DIRS or not isinstance(INPUT_DIRS, list):
    raise ValueError("config.yaml must define input_dirs as a non-empty list")

LOG_DIR = config.get("log_dir", "logs/slurm")  
FILTER_SCRIPT = config.get("filter_script", "scripts/filter_gam.sh")
GAMTOJSON_SCRIPT = config.get("gamtojson_script", "scripts/gam_to_json.sh")
GRAPH_DIR = config.get("graph_dir", "")
CHROMOSOMES = config.get("chromosomes", [])

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
    str(Path(g).parent / "results" / "json" / f"{Path(g).stem}_filtered.json")
    for g in GAM_FILES
]

_rep_suffix_re = re.compile(
    r"_(single|paired)_rep\d+_mapped_filtered\.json$"
)

def group_key_from_filtered_json(p: str) -> str:
    name = Path(p).name
    key = _rep_suffix_re.sub("", name)
    if key == name:
        raise ValueError(f"Path does not match expected pattern *single/paired_repN_mapped_filtered.json: {p}")
    return key

def get_input_dir_for_json(json_path: str) -> str:
    """Get the input directory root for a filtered JSON path.
    JSON is at: {input_dir}/results/json/{name}.json
    So input_dir is 3 levels up from the JSON.
    """
    return str(Path(json_path).parent.parent.parent)

# Group JSONs by (input_dir, group_name) so each directory is processed independently
GROUPS_BY_DIR = defaultdict(list)
for _json_path in FILTERED_JSONS:
    _input_dir = get_input_dir_for_json(_json_path)
    _group_name = group_key_from_filtered_json(_json_path)
    GROUPS_BY_DIR[(_input_dir, _group_name)].append(_json_path)

for _key in GROUPS_BY_DIR:
    GROUPS_BY_DIR[_key] = sorted(GROUPS_BY_DIR[_key])

COMBINED_JSONS = [
    str(Path(input_dir) / "results" / "json_combined" / group / f"{group}_combined.json")
    for input_dir, group in sorted(GROUPS_BY_DIR.keys())
]


SPLIT_JSONS = [
    str(Path(input_dir) / "results" / "json_combined" / group / f"{group}_combined_{chrom}.json")
    for input_dir, group in sorted(GROUPS_BY_DIR.keys())
    for chrom in CHROMOSOMES
]

rule all:
    input:
        SPLIT_JSONS

rule filter_gam:
    input:
        gam="{dir}/{stem}.gam"
    output:
        filtered="{dir}/{stem}_filtered.gam"
    threads: 4
    resources:
        mem_mb=20000,
        runtime= 720 # in minutes
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
        runtime= 120
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


def cat_json_files(json_paths, output_file):
    output_file = Path(output_file)
    with open(output_file, "wb") as out_f:
        for path in json_paths:
            path = Path(path)
            with open(path, "rb") as in_f:
                out_f.write(in_f.read())


def inputs_for_group(wildcards):
    """Return the list of filtered JSONs for a specific (dir, group) pair."""
    input_dir = wildcards.dir
    prefix = wildcards.group
    key = (input_dir, prefix)
    if key not in GROUPS_BY_DIR:
        raise ValueError(f"No filtered JSONs found for dir={input_dir}, group={prefix}")
    return GROUPS_BY_DIR[key]

rule combine_jsons:
    input:
        jsons=inputs_for_group
    output:
        combined="{dir}/results/json_combined/{group}/{group}_combined.json"
    wildcard_constraints:
        dir=".+?",
        group="[^/]+"
    threads: 1
    resources:
        mem_mb=50000,
        runtime=120
    log:
        "logs/slurm/combine_jsons/{group}_{dir}.log"
    run:
        cat_json_files(input.jsons, output.combined)


def split_outputs_for_combined(wildcards):
    base = Path(wildcards.dir) / "results" / "json_combined" / wildcards.group / f"{wildcards.group}_combined"
    return [f"{base}_{chrom}.json" for chrom in CHROMOSOMES]

def group_to_enc(group: str) -> str:
    enc = group.split("_")[-2]
    if not re.fullmatch(r"enc\d+", enc):
        raise ValueError(f"Expected enc### as second-to-last token in group, got {enc} from {group}")
    return enc

GRAPH_DIR = config["graph_dir"]
CHROMOSOMES = config["chromosomes"]

rule split_by_chromosome:
    input:
        combined="{dir}/results/json_combined/{group}/{group}_combined.json"
    output:
        split=expand(
            "{dir}/results/json_combined/{group}/{group}_combined_{chrom}.json",
            chrom=CHROMOSOMES,
            allow_missing=True
        )
    wildcard_constraints:
        dir=".+?",
        group="[^/]+"
    threads: 1
    resources:
        mem_mb=8000,
        runtime=240
    log:
        "{dir}/results/logs/split_by_chromosome/{group}.log"
    params:
        chromosomes=",".join(CHROMOSOMES),
        graph_dir=lambda wc: str(Path(config["graph_dir"]) / group_to_enc(wc.group)) + "/",
        env="/gpfs/gibbs/pi/gerstein/hc865/cvenv"
    shell:
        r"""
        mkdir -p "$(dirname {log})"
        bash scripts/split_by_chromosome.sh \
          {input.combined} \
          "{params.chromosomes}" \
          "{params.graph_dir}" \
          "{params.env}" &> {log}
        """