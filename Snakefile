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
GPC_ENV = config.get("gpc_env", "")

if not CHROMOSOMES:
    raise ValueError("config.yaml must define chromosomes as a non-empty list")

if not GRAPH_DIR:
    raise ValueError("config.yaml must define graph_dir")

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

def is_exp_target(input_dir: str, group: str) -> bool:
    """
    True for EXP, False for CONTROL.
    We check both the directory path and the group name for robust matching.
    """
    s = f"{input_dir}/{group}".lower()
    if re.search(r"(?:^|/|_)control(?:/|_|$)", s):
        return False
    return re.search(r"(?:^|/|_)exp(?:/|_|$)", s) is not None


EXP_GROUP_KEYS = [
    (input_dir, group)
    for (input_dir, group) in GROUPS_BY_DIR.keys()
    if is_exp_target(input_dir, group)
]

EXP_METRICS = [
    str(Path(input_dir) / "results" / "metrics" / group / "exp_metrics.txt")
    for (input_dir, group) in sorted(EXP_GROUP_KEYS)
]



rule all:
    input:
        SPLIT_JSONS,
        EXP_METRICS

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


# def inputs_for_group(wildcards):
#     """Return the list of filtered JSONs for a specific (dir, group) pair."""
#     input_dir = wildcards.dir
#     prefix = wildcards.group
#     key = (input_dir, prefix)
#     if key not in GROUPS_BY_DIR:
#         raise ValueError(f"No filtered JSONs found for dir={input_dir}, group={prefix}")
#     return GROUPS_BY_DIR[key]


# rule combine_jsons:
#     input:
#         jsons=inputs_for_group
#     output:
#         combined="{dir}/results/json_combined/{group}/{group}_combined.json"
#     wildcard_constraints:
#         dir=".+?",
#         group="[^/]+"
#     threads: 1
#     resources:
#         mem_mb=50000,
#         runtime=120
#     log:
#         "logs/slurm/combine_jsons/{group}_{dir}.log"
#     shell:
#         r"""
#         mkdir -p "$(dirname {log})"
#         bash {CONCAT_JSON_SCRIPT} {output.combined} {input.jsons} &> {log}
#         """

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
    log: "logs/slurm/combine_jsons/{group}_{dir}.log" 

    run: cat_json_files(input.jsons, output.combined)

def split_outputs_for_combined(wildcards):
    base = Path(wildcards.dir) / "results" / "json_combined" / wildcards.group / f"{wildcards.group}_combined"
    return [f"{base}_{chrom}.json" for chrom in CHROMOSOMES]

def group_to_enc(group: str) -> str:
    enc = group.split("_")[-2]
    if not re.fullmatch(r"enc\d+", enc):
        raise ValueError(f"Expected enc### as second-to-last token in group, got {enc} from {group}")
    return enc

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



def graph_dir_for_group(group: str) -> str:
    return str(Path(config["graph_dir"]) / group_to_enc(group)) + "/"


rule unique_read_count_exp:
    input:
        combined="{dir}/results/json_combined/{group}/{group}_combined.json"
    output:
        unique_read_count="{dir}/results/metrics/{group}/unique_read_count.txt"
    wildcard_constraints:
        dir=".+?",
        group="[^/]+"
    threads: 1
    resources:
        mem_mb=16000,
        runtime=240
    log:
        "{dir}/results/logs/metrics/{group}.unique_read_count.log"
    shell:
        r"""
        mkdir -p "$(dirname {log})"
        bash scripts/unique_read_count.sh {input.combined} {output.unique_read_count} &> {log}
        """

rule estimate_shift_exp:
    input:
        split=expand(
            "{dir}/results/json_combined/{group}/{group}_combined_{chrom}.json",
            chrom=CHROMOSOMES,
            allow_missing=True
        )
    output:
        logtxt="{dir}/results/metrics/{group}/estimate_shift_exp.txt",
        read_length="{dir}/results/metrics/{group}/read_length.txt",
        skipflag="{dir}/results/metrics/{group}/skip_tissue.txt"
    wildcard_constraints:
        dir=".+?",
        group="[^/]+"
    threads: 1
    resources:
        mem_mb=32000,
        runtime=480
    params:
        chromosomes=",".join(CHROMOSOMES),
        graph_dir=lambda wc: graph_dir_for_group(wc.group),
        prefix=lambda wc: str(Path(wc.dir) / "results" / "json_combined" / wc.group / f"{wc.group}_combined_"),
        env=GPC_ENV
    shell:
        r"""
        bash scripts/estimate_shift_exp.sh \
          "{params.chromosomes}" \
          "{params.graph_dir}" \
          "{params.prefix}" \
          "{params.env}" \
          "{output.logtxt}" \
          "{output.read_length}" \
          "{output.skipflag}"
        """

rule write_exp_metrics:
    input:
        unique="{dir}/results/metrics/{group}/unique_read_count.txt",
        readlen="{dir}/results/metrics/{group}/read_length.txt",
        skip="{dir}/results/metrics/{group}/skip_tissue.txt"
    output:
        metrics="{dir}/results/metrics/{group}/exp_metrics.txt"
    wildcard_constraints:
        dir=".+?",
        group="[^/]+"
    threads: 1
    resources:
        mem_mb=2000,
        runtime=30
    log:
        "{dir}/results/logs/metrics/{group}.exp_metrics.log"
    run:
        if not is_exp_target(wildcards.dir, wildcards.group):
            raise ValueError(...)

        Path(output.metrics).parent.mkdir(parents=True, exist_ok=True)
        Path(log[0]).parent.mkdir(parents=True, exist_ok=True)

        unique_reads = Path(input.unique).read_text().strip()
        read_length  = Path(input.readlen).read_text().strip()
        skip_tissue  = Path(input.skip).read_text().strip()

        Path(output.metrics).write_text(
            f"unique_reads\t{unique_reads}\nread_length\t{read_length}\nskip_tissue\t{skip_tissue}\n"
        )
        Path(log[0]).write_text(f"Wrote {output.metrics}\n")