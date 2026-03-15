#!/usr/bin/env python3
"""Infer the dominant read length from VG JSON alignments."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Infer the dominant read length from a JSON alignment file.",
    )
    parser.add_argument("input_json", help="Path to line-delimited alignment JSON.")
    parser.add_argument("output_path", help="Path to write the inferred read length.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    counts: Counter[int] = Counter()

    with Path(args.input_json).open() as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            record = json.loads(line)
            sequence = record.get("sequence")
            if sequence:
                counts[len(sequence)] += 1

    if not counts:
        raise SystemExit(f"No sequences found in {args.input_json}")

    read_length = sorted(counts.items(), key=lambda item: (-item[1], item[0]))[0][0]
    Path(args.output_path).write_text(f"{read_length}\n")


if __name__ == "__main__":
    main()
