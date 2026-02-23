"""Generate tissue metrics CSV from config-driven inputs."""

from __future__ import annotations

import argparse
import re
from dataclasses import asdict, field, make_dataclass
from pathlib import Path
from typing import Iterable, Optional

import pandas as pd
import yaml


_SEQUENCE_RE = re.compile(r'"sequence"\s*:\s*"([ACGTNacgtn]{20,})"')
_ENC_RE = re.compile(r"_enc(\d+)_")


def count_unique_sequences(json_path: str | Path) -> int:
    json_path = Path(json_path)
    unique_sequences: set[str] = set()

    with json_path.open() as f:
        for line in f:
            for match in _SEQUENCE_RE.finditer(line):
                unique_sequences.add(match.group(1).upper())

    return len(unique_sequences)


def count_lines(path: Path) -> Optional[int]:
    try:
        with path.open() as f:
            return sum(1 for _ in f)
    except FileNotFoundError:
        return None
    except IsADirectoryError:
        return None


def tissue_should_skip(tissue_dir: Path) -> bool:
    metrics_root = tissue_dir / "results" / "metrics"
    skip_files = sorted(metrics_root.glob("*_exp/skip_tissue.txt"))
    for skip_file in skip_files:
        value = skip_file.read_text().strip().lower()
        if value == "true":
            return True
    return False


def _enc_num(name: str) -> int:
    match = _ENC_RE.search(name)
    return int(match.group(1)) if match else 10**9


def _enc_label(name: str) -> Optional[str]:
    match = _ENC_RE.search(name)
    return f"enc{match.group(1)}" if match else None


def _read_int_file(path: Path) -> Optional[int]:
    try:
        return int(path.read_text().strip())
    except FileNotFoundError:
        return None
    except ValueError:
        return None


def _collect_enc_labels(tissue_dirs: Iterable[Path]) -> list[str]:
    labels: set[str] = set()
    for tissue_dir in tissue_dirs:
        peaks_root = tissue_dir / "results" / "peaks"
        if not peaks_root.is_dir():
            continue
        for directory in peaks_root.iterdir():
            if not directory.is_dir() or not directory.name.endswith("_exp"):
                continue
            label = _enc_label(directory.name)
            if label:
                labels.add(label)
    return sorted(labels, key=lambda x: int(x.replace("enc", "")))


def _resolve_input_dir(value: str, base: Path) -> Path:
    path = Path(value)
    return path if path.is_absolute() else (base / path)


def _make_tissue_dataclass(encs: list[str], chromosomes: list[str]):
    base_fields = [("tissue", str)]
    for kind in ("exp", "control"):
        for i in range(1, 5):
            base_fields.append((f"{kind}_{i}", Optional[Path], field(default=None)))
    for kind in ("exp", "control"):
        for i in range(1, 5):
            base_fields.append((f"{kind}_{i}_reads", Optional[int], field(default=None)))
    for i in range(1, 5):
        base_fields.append((f"peaks_{i}", Optional[int], field(default=None)))

    linear_fields = [
        (f"linear_peaks_{enc}_{chrom}", Optional[int], field(default=None))
        for enc in encs
        for chrom in chromosomes
    ]
    missing_fields = [
        (f"missing_intervals_{enc}_{chrom}", Optional[int], field(default=None))
        for enc in encs
        for chrom in chromosomes
    ]

    return make_dataclass("Tissue", base_fields + linear_fields + missing_fields)


def build_tissue(tissue_path: Path, tissue_cls, chromosomes: list[str]):
    tissue_name = tissue_path.name
    tissue = tissue_cls(tissue=tissue_name)

    metrics_root = tissue_path / "results" / "metrics"
    exp_dirs = []
    if metrics_root.is_dir():
        exp_dirs = sorted(
            (d for d in metrics_root.iterdir() if d.is_dir() and d.name.endswith("_exp")),
            key=lambda d: _enc_num(d.name),
        )
        for i, directory in enumerate(exp_dirs[:4], start=1):
            setattr(tissue, f"exp_{i}", directory)
            count = _read_int_file(directory / "unique_read_count.txt")
            setattr(tissue, f"exp_{i}_reads", count)

    peaks_root = tissue_path / "results" / "peaks"
    peaks_exp_dirs = []
    if peaks_root.is_dir():
        peaks_exp_dirs = sorted(
            (d for d in peaks_root.iterdir() if d.is_dir() and d.name.endswith("_exp")),
            key=lambda d: _enc_num(d.name),
        )

        for i, directory in enumerate(peaks_exp_dirs[:4], start=1):
            count = count_lines(directory / "all_peaks.intervalcollection")
            setattr(tissue, f"peaks_{i}", count)

        for directory in peaks_exp_dirs:
            enc = _enc_label(directory.name)
            if not enc:
                continue
            beds_root = directory / "flattened_out" / "beds"
            if not beds_root.is_dir():
                continue
            for chrom in chromosomes:
                bed_count = count_lines(beds_root / f"{chrom}.bed")
                setattr(tissue, f"linear_peaks_{enc}_{chrom}", bed_count)

                missing_count = count_lines(
                    beds_root / f"{chrom}_missing.intervalcollection"
                )
                setattr(tissue, f"missing_intervals_{enc}_{chrom}", missing_count)

    jc_root = tissue_path / "results" / "json_combined"
    if jc_root.is_dir():
        control_dirs = sorted(
            (d for d in jc_root.iterdir() if d.is_dir() and d.name.endswith("_control")),
            key=lambda d: _enc_num(d.name),
        )

        for i, directory in enumerate(control_dirs[:4], start=1):
            matches = list(directory.glob("*combined.json"))
            if len(matches) != 1:
                continue

            combined_json = matches[0]
            setattr(tissue, f"control_{i}", combined_json)
            setattr(tissue, f"control_{i}_reads", count_unique_sequences(combined_json))

    return tissue


def parse_args(default_output: Path) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build tissue metrics CSV from config/config.yaml",
    )
    parser.add_argument(
        "-o",
        "--output",
        default=str(default_output),
        help="Output CSV path (default: ../output/stats.csv)",
    )
    return parser.parse_args()


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    args = parse_args(repo_root / "output" / "stats.csv")
    config_path = repo_root / "config" / "config.yaml"
    if not config_path.is_file():
        raise SystemExit(f"Config not found: {config_path}")

    with config_path.open() as f:
        data = yaml.safe_load(f) or {}

    chromosomes = data.get("chromosomes", [])
    input_dirs = [
        _resolve_input_dir(p, repo_root) for p in data.get("input_dirs", [])
    ]
    non_skipped_tissues: list[Path] = []
    skipped_tissues: list[Path] = []
    for tissue_dir in input_dirs:
        if tissue_should_skip(tissue_dir):
            skipped_tissues.append(tissue_dir)
        else:
            non_skipped_tissues.append(tissue_dir)

    for tissue_dir in skipped_tissues:
        print(f"Skipped tissue: {tissue_dir}")

    encs = _collect_enc_labels(non_skipped_tissues)
    Tissue = _make_tissue_dataclass(encs, chromosomes)

    tissues = []
    for tissue_path in non_skipped_tissues:
        print(f"Processing tissue: {tissue_path}")
        tissues.append(build_tissue(Path(tissue_path), Tissue, chromosomes))
    df = pd.DataFrame([asdict(t) for t in tissues])

    output_path = Path(args.output).expanduser()
    if not output_path.is_absolute():
        output_path = repo_root / output_path
    output_path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(output_path, index=False)
    print(f"Saved {len(df)} tissues to {output_path}")


if __name__ == "__main__":
    main()
