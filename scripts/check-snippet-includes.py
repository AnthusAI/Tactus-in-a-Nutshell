#!/usr/bin/env python3

from __future__ import annotations

import pathlib
import re
import sys


FENCE_RE = re.compile(r"^```.*\{([^}]*)\}\s*$")
ATTR_RE = re.compile(r'(?P<key>[A-Za-z_][A-Za-z0-9_-]*)="(?P<value>[^"]*)"')


def parse_attrs(attr_text: str) -> dict[str, str]:
    return {match.group("key"): match.group("value") for match in ATTR_RE.finditer(attr_text)}


def snippet_markers_exist(text: str, snippet: str) -> tuple[bool, bool, bool]:
    start_re = re.compile(rf"^\s*--\s*snippet:start\s+{re.escape(snippet)}\s*$", re.M)
    end_re = re.compile(rf"^\s*--\s*snippet:end\s+{re.escape(snippet)}\s*$", re.M)
    start_match = start_re.search(text)
    end_match = end_re.search(text)
    ordered = bool(start_match and end_match and start_match.start() < end_match.start())
    return bool(start_match), bool(end_match), ordered


def extract_snippet_lines(text: str, snippet: str) -> list[str]:
    start_re = re.compile(rf"^\s*--\s*snippet:start\s+{re.escape(snippet)}\s*$")
    end_re = re.compile(rf"^\s*--\s*snippet:end\s+{re.escape(snippet)}\s*$")

    lines = text.splitlines()
    start_idx: int | None = None
    for i, line in enumerate(lines):
        if start_re.match(line):
            start_idx = i + 1
            break
    if start_idx is None:
        raise ValueError(f"snippet:start '{snippet}' not found")

    out: list[str] = []
    for line in lines[start_idx:]:
        if end_re.match(line):
            return out
        out.append(line)
    raise ValueError(f"snippet:end '{snippet}' not found")


def parse_lines_spec(spec: str) -> tuple[int | None, int | None]:
    spec = spec.strip()
    if not spec:
        return None, None

    if re.fullmatch(r"\d+", spec):
        n = int(spec)
        return n, n

    m = re.fullmatch(r"(\d+)\s*-\s*(\d+)", spec)
    if m:
        return int(m.group(1)), int(m.group(2))

    m = re.fullmatch(r"(\d+)\s*-\s*", spec)
    if m:
        return int(m.group(1)), None

    m = re.fullmatch(r"-\s*(\d+)", spec)
    if m:
        return None, int(m.group(1))

    raise ValueError('invalid lines spec (expected e.g. "12-34", "12-", "-34", or "12")')


def validate_line_range(
    lines: list[str],
    start: int | None,
    end: int | None,
) -> str | None:
    total = len(lines)
    s = start or 1
    e = end or total

    if total == 0:
        return "cannot slice empty content"
    if s < 1 or e < 1 or s > total or e > total:
        return f"line range out of bounds (1-{total})"
    if s > e:
        return "line range start is greater than end"
    return None


def main() -> int:
    project_root = pathlib.Path(__file__).resolve().parent.parent

    qmd_paths: list[pathlib.Path] = []
    index_qmd = project_root / "index.qmd"
    if index_qmd.exists():
        qmd_paths.append(index_qmd)
    qmd_paths.extend(sorted((project_root / "chapters").rglob("*.qmd")))

    errors: list[str] = []

    for qmd_path in qmd_paths:
        try:
            lines = qmd_path.read_text(encoding="utf-8").splitlines()
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{qmd_path}: failed to read ({exc})")
            continue

        for i, line in enumerate(lines, start=1):
            m = FENCE_RE.match(line)
            if not m:
                continue

            attrs = parse_attrs(m.group(1))
            include_path = attrs.get("file") or attrs.get("include") or attrs.get("tac-file")
            if not include_path:
                continue

            snippet = attrs.get("snippet") or attrs.get("tac-snippet")
            lines_spec = attrs.get("lines") or attrs.get("line-range") or attrs.get("line_range")
            start_line_attr = attrs.get("start-line") or attrs.get("start_line")
            end_line_attr = attrs.get("end-line") or attrs.get("end_line")

            referenced = project_root / include_path
            if not referenced.exists():
                errors.append(f"{qmd_path}:{i}: missing include file: {include_path}")
                continue
            if not referenced.is_file():
                errors.append(f"{qmd_path}:{i}: include path is not a file: {include_path}")
                continue

            if lines_spec and (start_line_attr or end_line_attr):
                errors.append(
                    f'{qmd_path}:{i}: use either `lines="..."` or `start-line`/`end-line`, not both'
                )
                continue

            included_text: str
            try:
                included_text = referenced.read_text(encoding="utf-8")
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{qmd_path}:{i}: failed to read include file: {include_path} ({exc})")
                continue

            content_lines: list[str]
            if snippet:
                has_start, has_end, ordered = snippet_markers_exist(included_text, snippet)
                if not has_start:
                    errors.append(f"{qmd_path}:{i}: snippet:start '{snippet}' not found in {include_path}")
                if not has_end:
                    errors.append(f"{qmd_path}:{i}: snippet:end '{snippet}' not found in {include_path}")
                if has_start and has_end and not ordered:
                    errors.append(
                        f"{qmd_path}:{i}: snippet markers out of order for '{snippet}' in {include_path}"
                    )
                if not (has_start and has_end and ordered):
                    continue
                try:
                    content_lines = extract_snippet_lines(included_text, snippet)
                except ValueError as exc:
                    errors.append(f"{qmd_path}:{i}: {include_path}: {exc}")
                    continue
            else:
                content_lines = included_text.splitlines()

            start_line: int | None = None
            end_line: int | None = None
            if lines_spec:
                try:
                    start_line, end_line = parse_lines_spec(lines_spec)
                except ValueError as exc:
                    errors.append(f'{qmd_path}:{i}: {include_path}: invalid `lines="{lines_spec}"` ({exc})')
                    continue
            elif start_line_attr or end_line_attr:
                if start_line_attr:
                    try:
                        start_line = int(start_line_attr)
                    except ValueError:
                        errors.append(
                            f'{qmd_path}:{i}: {include_path}: invalid `start-line="{start_line_attr}"`'
                        )
                        continue
                if end_line_attr:
                    try:
                        end_line = int(end_line_attr)
                    except ValueError:
                        errors.append(f'{qmd_path}:{i}: {include_path}: invalid `end-line="{end_line_attr}"`')
                        continue

            if start_line is not None or end_line is not None:
                msg = validate_line_range(content_lines, start_line, end_line)
                if msg:
                    errors.append(f"{qmd_path}:{i}: {include_path}: {msg}")

    if errors:
        for err in errors:
            print(err, file=sys.stderr)
        return 1

    print("Snippet includes: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
