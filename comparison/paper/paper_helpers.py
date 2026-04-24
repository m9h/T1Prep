"""Helpers imported by every pweave chunk in main.pnw.

Each chunk re-imports; loads are cheap (small parquets/JSONs) so the
per-chunk cost is negligible and we sidestep pweave's kernel-isolation
between chunks.
"""
from pathlib import Path
import json

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt  # noqa: F401
import numpy as np              # noqa: F401
import pandas as pd

PROJECT = Path('/home/mhough/dev/smri-fm/experiments/dlbs_morphometry_benchmark')
RESULTS = PROJECT / 'results'
FIGURES = Path(__file__).resolve().parent / 'figures'
FIGURES.mkdir(exist_ok=True)


def read_parquet_or_empty(name: str) -> pd.DataFrame:
    p = RESULTS / name
    return pd.read_parquet(p) if p.exists() else pd.DataFrame()


def read_json_or_empty(name: str) -> dict:
    p = RESULTS / name
    return json.loads(p.read_text()) if p.exists() else {}


def load_all():
    return {
        "fs":             read_parquet_or_empty('fastsurfer_features.parquet'),
        "t1p":            read_parquet_or_empty('t1prep_features.parquet'),
        "brainiac":       read_parquet_or_empty('brainiac_embeddings.parquet'),
        "ridge_fs":       read_json_or_empty('ridge_fs_asegdkt.json'),
        "ridge_t1p":      read_json_or_empty('ridge_t1prep_thickness.json'),
        "ridge_brainiac": read_json_or_empty('ridge_brainiac_embed.json'),
        "ridge_concat":   read_json_or_empty('ridge_concat_fs_t1prep.json'),
        "ridge_concat3":  read_json_or_empty('ridge_concat_fs_t1prep_brainiac.json'),
    }


def fmt(v, digits=2):
    if isinstance(v, (int, float)):
        return f"{v:.{digits}f}"
    return "---"
