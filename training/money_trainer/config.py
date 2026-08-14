"""Typed configuration with a dependency-free YAML fallback."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from importlib.resources import files
import json
import math
import os
from pathlib import Path
from typing import Any, Mapping

from .constants import COIN_CLASSES, DEFAULT_CONFIG_NAME


class ConfigurationError(ValueError):
    """Raised when a training configuration is internally inconsistent."""


@dataclass(frozen=True, slots=True)
class ModelConfig:
    architecture: str = "yolo26n.pt"
    image_size: int = 640
    device: str = "auto"


@dataclass(frozen=True, slots=True)
class TrainingSettings:
    epochs: int = 100
    batch_size: int = 16
    patience: int = 20
    seed: int = 42
    workers: int = 4
    deterministic: bool = True


@dataclass(frozen=True, slots=True)
class DatasetConfig:
    train: float = 0.70
    validation: float = 0.15
    test: float = 0.15
    copy_mode: str = "copy"
    minimum_images_per_class: int = 1
    minimum_instances_per_class: int = 1
    require_reviewed: bool = True
    require_all_classes_in_each_split: bool = True

    @property
    def ratios(self) -> dict[str, float]:
        return {"train": self.train, "validation": self.validation, "test": self.test}


@dataclass(frozen=True, slots=True)
class AugmentationConfig:
    enabled: bool = True
    rotation_degrees: float = 180.0
    brightness: float = 0.20
    contrast: float = 0.20
    exposure: float = 0.15
    blur_probability: float = 0.05
    noise_probability: float = 0.05
    scale: float = 0.20
    crop_fraction: float = 0.05
    perspective: float = 0.0005
    shadow_probability: float = 0.05
    horizontal_flip_probability: float = 0.50


@dataclass(frozen=True, slots=True)
class EvaluationConfig:
    confidence_threshold: float = 0.25
    low_confidence_threshold: float = 0.50
    iou_threshold: float = 0.50
    coreml_min_match_rate: float = 0.90
    coreml_max_mean_confidence_delta: float = 0.10
    coreml_min_mean_iou: float = 0.80
    coreml_validation_images: int = 8


@dataclass(frozen=True, slots=True)
class ExportConfig:
    format: str = "coreml"
    quantize: bool | int = False
    nms: bool = False


@dataclass(frozen=True, slots=True)
class RuntimeConfig:
    mock_mode: bool = False


@dataclass(frozen=True, slots=True)
class AppConfig:
    model: ModelConfig = field(default_factory=ModelConfig)
    training: TrainingSettings = field(default_factory=TrainingSettings)
    dataset: DatasetConfig = field(default_factory=DatasetConfig)
    augmentation: AugmentationConfig = field(default_factory=AugmentationConfig)
    evaluation: EvaluationConfig = field(default_factory=EvaluationConfig)
    export: ExportConfig = field(default_factory=ExportConfig)
    runtime: RuntimeConfig = field(default_factory=RuntimeConfig)
    classes: tuple[str, ...] = COIN_CLASSES

    @classmethod
    def from_mapping(cls, value: Mapping[str, Any]) -> "AppConfig":
        def section(name: str) -> dict[str, Any]:
            raw = value.get(name, {})
            if raw is None:
                return {}
            if not isinstance(raw, Mapping):
                raise ConfigurationError(f"'{name}' must be a mapping")
            return dict(raw)

        dataset_values = section("dataset")
        if "val" in dataset_values and "validation" not in dataset_values:
            dataset_values["validation"] = dataset_values.pop("val")
        dataset_aliases = {
            "min_images_per_class": "minimum_images_per_class",
            "min_instances_per_class": "minimum_instances_per_class",
        }
        for alias, canonical in dataset_aliases.items():
            if alias in dataset_values and canonical not in dataset_values:
                dataset_values[canonical] = dataset_values.pop(alias)

        augmentation_values = section("augmentation")
        augmentation_aliases = {
            "rotation": "rotation_degrees",
            "blur": "blur_probability",
            "noise": "noise_probability",
            "crop": "crop_fraction",
            "shadow": "shadow_probability",
        }
        for alias, canonical in augmentation_aliases.items():
            if alias in augmentation_values and canonical not in augmentation_values:
                augmentation_values[canonical] = augmentation_values.pop(alias)

        class_values = value.get("classes", COIN_CLASSES)
        if not isinstance(class_values, (list, tuple)):
            raise ConfigurationError("'classes' must be a list")

        try:
            result = cls(
                model=ModelConfig(**section("model")),
                training=TrainingSettings(**section("training")),
                dataset=DatasetConfig(**dataset_values),
                augmentation=AugmentationConfig(**augmentation_values),
                evaluation=EvaluationConfig(**section("evaluation")),
                export=ExportConfig(**section("export")),
                runtime=RuntimeConfig(**section("runtime")),
                classes=tuple(str(item) for item in class_values),
            )
        except TypeError as exc:
            raise ConfigurationError(str(exc)) from exc
        result.validate()
        return result

    def validate(self) -> None:
        if self.classes != COIN_CLASSES:
            raise ConfigurationError(
                "classes must use the stable order: " + ", ".join(COIN_CLASSES)
            )
        ratios = self.dataset.ratios
        if any(not math.isfinite(value) or value < 0 for value in ratios.values()):
            raise ConfigurationError("dataset split ratios must be finite and non-negative")
        if not math.isclose(sum(ratios.values()), 1.0, abs_tol=1e-9):
            raise ConfigurationError("dataset train/validation/test ratios must sum to 1.0")
        if self.dataset.copy_mode not in {"copy", "symlink", "hardlink"}:
            raise ConfigurationError("dataset.copy_mode must be copy, symlink, or hardlink")
        if self.model.image_size <= 0:
            raise ConfigurationError("model.image_size must be positive")
        if self.training.epochs <= 0 or self.training.batch_size <= 0:
            raise ConfigurationError("training epochs and batch_size must be positive")
        if self.training.patience < 0 or self.training.workers < 0:
            raise ConfigurationError("training patience and workers cannot be negative")
        if self.dataset.minimum_images_per_class < 0:
            raise ConfigurationError("minimum_images_per_class cannot be negative")
        if self.dataset.minimum_instances_per_class < 0:
            raise ConfigurationError("minimum_instances_per_class cannot be negative")
        probabilities = {
            "blur_probability": self.augmentation.blur_probability,
            "noise_probability": self.augmentation.noise_probability,
            "shadow_probability": self.augmentation.shadow_probability,
            "horizontal_flip_probability": self.augmentation.horizontal_flip_probability,
        }
        if any(value < 0 or value > 1 for value in probabilities.values()):
            raise ConfigurationError("augmentation probabilities must be between 0 and 1")
        thresholds = (
            self.evaluation.confidence_threshold,
            self.evaluation.low_confidence_threshold,
            self.evaluation.iou_threshold,
            self.evaluation.coreml_min_match_rate,
            self.evaluation.coreml_min_mean_iou,
        )
        if any(value < 0 or value > 1 for value in thresholds):
            raise ConfigurationError("evaluation thresholds must be between 0 and 1")
        if self.evaluation.coreml_max_mean_confidence_delta < 0:
            raise ConfigurationError("Core ML confidence delta cannot be negative")
        if self.export.format != "coreml":
            raise ConfigurationError("export.format must be 'coreml'")
        if self.export.quantize not in (False, 8, 16):
            raise ConfigurationError("export.quantize must be false, 8, or 16")

    def to_dict(self) -> dict[str, Any]:
        value = asdict(self)
        value["classes"] = list(self.classes)
        return value


def load_config(
    path: str | Path | None = None,
    *,
    overrides: Mapping[str, Any] | None = None,
) -> AppConfig:
    """Load the bundled defaults, merge an optional YAML file, then overrides."""

    default_path = Path(str(files("money_trainer").joinpath(DEFAULT_CONFIG_NAME)))
    defaults = _load_yaml(default_path)
    if path is not None:
        custom = _load_yaml(Path(path))
        defaults = _deep_merge(defaults, custom)
    if overrides:
        defaults = _deep_merge(defaults, overrides)
    env_mock = os.getenv("MONEY_TRAINER_MOCK_MODE")
    if env_mock is not None:
        defaults = _deep_merge(
            defaults,
            {"runtime": {"mock_mode": env_mock.strip().lower() in {"1", "true", "yes", "on"}}},
        )
    return AppConfig.from_mapping(defaults)


def dump_yaml(value: Mapping[str, Any]) -> str:
    """Serialize config-sized mappings without requiring PyYAML."""

    lines: list[str] = []

    def emit(item: Any, indent: int, key: str | None = None) -> None:
        prefix = " " * indent
        if key is not None:
            if isinstance(item, Mapping):
                lines.append(f"{prefix}{key}:")
                for child_key, child in item.items():
                    emit(child, indent + 2, str(child_key))
            elif isinstance(item, (list, tuple)):
                lines.append(f"{prefix}{key}:")
                for child in item:
                    lines.append(f"{' ' * (indent + 2)}- {_scalar_to_yaml(child)}")
            else:
                lines.append(f"{prefix}{key}: {_scalar_to_yaml(item)}")

    for top_key, top_value in value.items():
        emit(top_value, 0, str(top_key))
    return "\n".join(lines) + "\n"


def _load_yaml(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise ConfigurationError(f"configuration file does not exist: {path}")
    text = path.read_text(encoding="utf-8")
    try:
        import yaml  # type: ignore[import-not-found]
    except ImportError:
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            parsed = _parse_simple_yaml(text)
    else:
        parsed = yaml.safe_load(text)
    if parsed is None:
        return {}
    if not isinstance(parsed, Mapping):
        raise ConfigurationError(f"configuration root must be a mapping: {path}")
    return dict(parsed)


def _parse_simple_yaml(text: str) -> dict[str, Any]:
    tokens: list[tuple[int, str]] = []
    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        raw_line = _strip_yaml_comment(raw_line).rstrip()
        if not raw_line.strip():
            continue
        if "\t" in raw_line[: len(raw_line) - len(raw_line.lstrip())]:
            raise ConfigurationError(f"tabs are not supported in YAML indentation (line {line_number})")
        tokens.append((len(raw_line) - len(raw_line.lstrip(" ")), raw_line.strip()))

    def parse_block(index: int, indent: int) -> tuple[Any, int]:
        if index >= len(tokens):
            return {}, index
        is_list = tokens[index][1].startswith("- ")
        result: Any = [] if is_list else {}
        while index < len(tokens):
            current_indent, content = tokens[index]
            if current_indent < indent:
                break
            if current_indent != indent:
                raise ConfigurationError("invalid YAML indentation")
            if is_list:
                if not content.startswith("- "):
                    break
                result.append(_parse_scalar(content[2:].strip()))
                index += 1
                continue
            if content.startswith("- ") or ":" not in content:
                raise ConfigurationError(f"unsupported YAML entry: {content}")
            key, raw_value = content.split(":", 1)
            key = key.strip()
            raw_value = raw_value.strip()
            index += 1
            if raw_value:
                result[key] = _parse_scalar(raw_value)
            elif index < len(tokens) and tokens[index][0] > indent:
                result[key], index = parse_block(index, tokens[index][0])
            else:
                result[key] = {}
        return result, index

    if not tokens:
        return {}
    parsed, end = parse_block(0, tokens[0][0])
    if end != len(tokens) or not isinstance(parsed, dict):
        raise ConfigurationError("unsupported YAML structure")
    return parsed


def _strip_yaml_comment(line: str) -> str:
    quote: str | None = None
    escaped = False
    for index, character in enumerate(line):
        if escaped:
            escaped = False
            continue
        if character == "\\" and quote == '"':
            escaped = True
            continue
        if character in {"'", '"'}:
            if quote is None:
                quote = character
            elif quote == character:
                quote = None
            continue
        if character == "#" and quote is None and (
            index == 0 or line[index - 1].isspace()
        ):
            return line[:index]
    return line


def _parse_scalar(raw: str) -> Any:
    lowered = raw.lower()
    if lowered in {"true", "false"}:
        return lowered == "true"
    if lowered in {"null", "none", "~"}:
        return None
    if (raw.startswith('"') and raw.endswith('"')) or (
        raw.startswith("'") and raw.endswith("'")
    ):
        return raw[1:-1]
    try:
        return int(raw)
    except ValueError:
        try:
            return float(raw)
        except ValueError:
            return raw


def _scalar_to_yaml(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "null"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    if not text or any(character in text for character in "#:[]{}&*!|>'\"%@`"):
        return json.dumps(text, ensure_ascii=False)
    return text


def _deep_merge(base: Mapping[str, Any], override: Mapping[str, Any]) -> dict[str, Any]:
    result = dict(base)
    for key, value in override.items():
        previous = result.get(key)
        if isinstance(previous, Mapping) and isinstance(value, Mapping):
            result[key] = _deep_merge(previous, value)
        else:
            result[key] = value
    return result
