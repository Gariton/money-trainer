"""Coin-appropriate augmentation configuration adapters."""

from __future__ import annotations

from typing import Any

from .config import AugmentationConfig


def ultralytics_augmentation_args(config: AugmentationConfig) -> dict[str, Any]:
    """Map safe native augmentations to Ultralytics training arguments.

    Brightness/exposure use the value channel and contrast uses saturation as
    the closest maintained native controls. Advanced blur/noise/shadow support
    is available through :func:`build_albumentations_pipeline`.
    """

    if not config.enabled:
        return {
            "degrees": 0.0,
            "hsv_s": 0.0,
            "hsv_v": 0.0,
            "scale": 0.0,
            "translate": 0.0,
            "perspective": 0.0,
            "fliplr": 0.0,
            "mosaic": 0.0,
            "mixup": 0.0,
            "copy_paste": 0.0,
        }
    return {
        "degrees": config.rotation_degrees,
        "hsv_s": config.contrast,
        "hsv_v": max(config.brightness, config.exposure),
        "scale": config.scale,
        "translate": config.crop_fraction,
        "perspective": config.perspective,
        "fliplr": config.horizontal_flip_probability,
        # Composite scenes can differ substantially from the iPhone camera
        # distribution, so they remain disabled for this coin-specific setup.
        "mosaic": 0.0,
        "mixup": 0.0,
        "copy_paste": 0.0,
    }


def build_albumentations_pipeline(config: AugmentationConfig) -> Any:
    """Build the optional advanced pipeline without importing it at startup.

    Returned transforms use YOLO-format boxes and preserve class labels. A
    custom backend can apply this pipeline offline or inject it into its loader.
    """

    try:
        import albumentations as A  # type: ignore[import-not-found]
    except ImportError as exc:
        raise RuntimeError(
            "advanced blur/noise/shadow augmentation requires the 'ml' extra"
        ) from exc
    if not config.enabled:
        return A.Compose(
            [],
            bbox_params=A.BboxParams(format="yolo", label_fields=["class_labels"]),
        )
    transforms = [
        A.Rotate(limit=config.rotation_degrees, border_mode=0, p=0.75),
        A.RandomBrightnessContrast(
            brightness_limit=config.brightness,
            contrast_limit=config.contrast,
            p=0.35,
        ),
        A.RandomGamma(
            gamma_limit=(
                max(1, int(100 * (1 - config.exposure))),
                int(100 * (1 + config.exposure)),
            ),
            p=0.20,
        ),
        A.Blur(blur_limit=(3, 5), p=config.blur_probability),
        A.GaussNoise(p=config.noise_probability),
        A.Perspective(scale=(0.0, max(config.perspective, 0.001)), p=0.10),
        A.RandomShadow(p=config.shadow_probability),
    ]
    return A.Compose(
        transforms,
        bbox_params=A.BboxParams(
            format="yolo",
            label_fields=["class_labels"],
            min_visibility=0.50,
            clip=True,
        ),
    )
