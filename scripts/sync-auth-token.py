#!/usr/bin/env python3
"""Ensure DSH_AUTH_TOKEN is present in $DSH_HOME/.credentials.yaml refs."""

from __future__ import annotations

import json
import os
import re
from pathlib import Path


def yaml_scalar(value: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_./-]+", value):
        return value
    return json.dumps(value)


def main() -> None:
    home = Path(os.environ["DSH_HOME"])
    token = os.environ["DSH_AUTH_TOKEN"]
    path = home / ".credentials.yaml"
    scalar = yaml_scalar(token)

    if not path.exists():
        path.write_text(
            "version: 1\n\nrefs:\n  DSH_AUTH_TOKEN: "
            + scalar
            + "\n",
            encoding="utf-8",
        )
        path.chmod(0o600)
        return

    text = path.read_text(encoding="utf-8")
    if re.search(r"(?m)^\s*DSH_AUTH_TOKEN:\s*.*$", text):
        text = re.sub(
            r"(?m)^(\s*)DSH_AUTH_TOKEN:\s*.*$",
            rf"\1DSH_AUTH_TOKEN: {scalar}",
            text,
            count=1,
        )
    elif re.search(r"(?m)^refs:\s*\{\}\s*$", text):
        text = re.sub(
            r"(?m)^refs:\s*\{\}\s*$",
            f"refs:\n  DSH_AUTH_TOKEN: {scalar}",
            text,
            count=1,
        )
    elif re.search(r"(?m)^refs:\s*$", text):
        text = re.sub(
            r"(?m)^refs:\s*$",
            f"refs:\n  DSH_AUTH_TOKEN: {scalar}",
            text,
            count=1,
        )
    else:
        text = text.rstrip() + f"\n\nrefs:\n  DSH_AUTH_TOKEN: {scalar}\n"

    path.write_text(text, encoding="utf-8")
    path.chmod(0o600)


if __name__ == "__main__":
    main()
