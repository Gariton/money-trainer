"""Command-line entrypoint for the complete training pipeline."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Sequence

from .pipeline import PipelineEvent, run_training
from .validation import DatasetValidationError


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="money-trainer")
    subcommands = parser.add_subparsers(dest="command", required=True)
    train = subcommands.add_parser("train", help="run the complete model pipeline")
    train.add_argument(
        "--dataset",
        type=Path,
        default=Path("dataset"),
        help="manifest JSON or directory containing manifest.json (default: ./dataset)",
    )
    train.add_argument(
        "--output",
        type=Path,
        default=Path("artifacts"),
        help="model artifact root (default: ./artifacts)",
    )
    train.add_argument("--config", type=Path, default=None, help="custom YAML config")
    train.add_argument("--model-version", default="v1")
    train.add_argument("--dataset-version", default=None)
    mode = train.add_mutually_exclusive_group()
    mode.add_argument("--mock", action="store_true", help="dependency-free deterministic run")
    mode.add_argument("--real", action="store_true", help="force the Ultralytics backend")
    train.add_argument(
        "--quiet",
        action="store_true",
        help="suppress progress JSON lines on stderr",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command != "train":
        raise AssertionError(f"unhandled command: {args.command}")
    selected_mock: bool | None = True if args.mock else False if args.real else None

    def progress(event: PipelineEvent) -> None:
        if not args.quiet:
            print(json.dumps(event.to_dict(), ensure_ascii=False), file=sys.stderr, flush=True)

    try:
        result = run_training(
            args.dataset,
            args.output,
            config_path=args.config,
            mock=selected_mock,
            model_version=args.model_version,
            dataset_version=args.dataset_version,
            progress_callback=progress,
        )
    except DatasetValidationError as exc:
        print(json.dumps(exc.report.to_dict(), ensure_ascii=False), file=sys.stderr)
        return 2
    except Exception as exc:
        print(
            json.dumps(
                {"error": type(exc).__name__, "message": str(exc)},
                ensure_ascii=False,
            ),
            file=sys.stderr,
        )
        return 1
    print(json.dumps(result.to_dict(), ensure_ascii=False, sort_keys=True))
    return 0

