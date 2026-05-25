"""
Pre-fetch the sentence-transformers model into the image at build time.

Avoids the 440 MB cold-fetch each CronJob fire would otherwise incur
on a fresh pod. Under sustained sda write pressure that fetch overran
the job's `activeDeadlineSeconds`, triggering a backoff loop.

Honours `EMBEDDING_MODEL` so the baked weights match the runtime config
default in `config.py`; falls back to the same constant if unset.
"""

import os

from sentence_transformers import SentenceTransformer

MODEL = os.getenv("EMBEDDING_MODEL", "sentence-transformers/all-mpnet-base-v2")
SentenceTransformer(MODEL)
