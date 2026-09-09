#!/usr/bin/env python3
"""Merge llm-deepseek overrides from env into $DSH_HOME/settings.yaml."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

VALID_REASONING = frozenset({"off", "low", "high", "max"})


def main() -> None:
    home = Path(os.environ.get("DSH_HOME", "/dsh"))
    settings_path = home / "settings.yaml"
    reasoning = os.environ.get("DSH_LLM_REASONING_EFFORT", "").strip()
    max_tokens = os.environ.get("DSH_LLM_MAX_TOKENS", "").strip()

    if not reasoning and not max_tokens:
        return

    if reasoning and reasoning not in VALID_REASONING:
        print(
            f"Invalid DSH_LLM_REASONING_EFFORT: {reasoning!r} "
            f"(expected one of {', '.join(sorted(VALID_REASONING))})",
            file=sys.stderr,
        )
        sys.exit(1)

    max_tokens_value: int | None = None
    if max_tokens:
        try:
            max_tokens_value = int(max_tokens)
            if max_tokens_value <= 0:
                raise ValueError
        except ValueError:
            print(
                f"Invalid DSH_LLM_MAX_TOKENS: {max_tokens!r} (expected a positive integer)",
                file=sys.stderr,
            )
            sys.exit(1)

    block_lines = ["llm-deepseek:"]
    if reasoning:
        block_lines.append(f"  reasoningEffort: {reasoning}")
    if max_tokens_value is not None:
        block_lines.append(f"  maxTokens: {max_tokens_value}")
    block = "\n".join(block_lines)

    content = settings_path.read_text(encoding="utf-8") if settings_path.exists() else ""
    pattern = r"^llm-deepseek:\n(?:  .*\n)*"
    if re.search(pattern, content, re.MULTILINE):
        content = re.sub(pattern, block + "\n", content, count=1)
    else:
        content = content.rstrip() + ("\n\n" if content.strip() else "") + block + "\n"

    settings_path.parent.mkdir(parents=True, exist_ok=True)
    settings_path.write_text(content, encoding="utf-8")


if __name__ == "__main__":
    main()
