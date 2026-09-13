#!/usr/bin/env python3
"""Bind MRA specialist inputs to its existing files-API collector policy."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

from role_review import Invalid, complete_hunks


DIRECTORY = Path(__file__).resolve().parent
SHA = re.compile(r"[0-9a-f]{40}\Z")
SOURCES = ("CLAUDE.md", "scripts/pr-review/mra-review-context.md")


def checksum(value):
    if not isinstance(value, bytes):
        value = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(value).hexdigest()


def git(*arguments):
    result = subprocess.run(["git", *arguments], capture_output=True)
    if result.returncode:
        raise ValueError("collector Git provenance is unavailable")
    return result.stdout


def snapshots(head, base, merge_base, before, after):
    if not all(isinstance(value, str) and SHA.fullmatch(value)
               for value in (head, base, merge_base)):
        raise ValueError("invalid collector snapshot")
    expected = {"head_sha": head, "base_sha": base}
    if before != expected or after != expected:
        raise ValueError("collector snapshot changed or differs from requested SHAs")
    if git("rev-parse", "HEAD").decode().strip() != base:
        raise ValueError("collector requires the pinned base snapshot")


def file_scope(files, merge_base, head):
    if not isinstance(files, list) or not 0 < len(files) < 3000:
        raise ValueError("collector scope is empty or reaches the files API cap")
    paths, names = set(), set()
    for entry in files:
        name = entry.get("filename")
        if not isinstance(name, str) or not name or name in names:
            raise ValueError("collector scope has invalid or duplicate entries")
        names.add(name)
        for path in (name, entry.get("previous_filename")):
            if path is None:
                continue
            if (not isinstance(path, str) or not path or path.startswith("/")
                    or ".." in path.split("/") or any(ord(c) < 32 for c in path)):
                raise ValueError("collector scope contains an invalid path")
            paths.add(path)
    actual = git(
        "diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--name-status",
        "-z", merge_base, head, "--",
    ).decode("utf-8").split("\0")
    if actual[-1] == "":
        actual.pop()
    statuses = dict(zip(actual[1::2], actual[::2]))
    if paths != set(statuses):
        raise ValueError("collector scope differs from immutable Git paths")
    for entry in files:
        name, status = entry["filename"], entry.get("status")
        expected = {"added": "A", "removed": "D", "modified": "MT", "changed": "T"}
        if status == "renamed":
            valid = (statuses.get(entry.get("previous_filename")) == "D"
                     and statuses.get(name) == "A")
        else:
            valid = statuses.get(name) in expected.get(status, "")
        if not valid:
            raise ValueError("collector status differs from immutable Git changes")
    return sorted(paths)


def classify(files):
    """Use the existing classifier; temporary raw input is gone before return."""
    with tempfile.TemporaryDirectory(prefix="mra-collector-") as temporary:
        root = Path(temporary)
        source = root / "files.json"
        source.write_text(json.dumps(files))
        result = subprocess.run(
            ["bash", str(DIRECTORY / "collect-diff.sh"), str(source), str(root / "out")],
            capture_output=True,
        )
        if result.returncode:
            raise ValueError("collector rejected state, path or unavailable patch")
        output = root / "out"
        records = {}
        for line in (output / "classified.tsv").read_text().splitlines():
            kind, name, previous, status, binary, asset = line.split("\t")
            records[name] = {
                "filename": name, "previous_filename": previous or None,
                "status": status, "classification": kind,
                "binary": binary == "1", "asset": asset == "1",
            }
        for entry in files:
            for key in ("sha", "changes", "additions", "deletions"):
                if key not in entry:
                    continue
                value = entry[key]
                valid = (isinstance(value, str) and SHA.fullmatch(value) if key == "sha"
                         else type(value) is int and value >= 0)
                if not valid:
                    raise ValueError("collector contains invalid file metadata")
                records[entry["filename"]][key] = value
        panel = (output / "panel.diff").read_bytes()
        unsafe = (output / "unsafe-filtered.txt").read_text().splitlines()
    return panel, records, unsafe


def validate_patches(files, records):
    for entry in files:
        if records[entry["filename"]]["classification"] != "panel":
            continue
        patch = entry.get("patch")
        if patch is not None:
            if not isinstance(patch, str) or not patch:
                raise ValueError("collector returned an empty text patch")
            try:
                complete_hunks("diff --git a/file b/file\n" + patch + "\n")
            except Invalid:
                raise ValueError("collector patch has an incomplete or invalid hunk") from None


def collect(files, output, *, head, base, merge_base, before, after):
    snapshots(head, base, merge_base, before, after)
    panel, records, unsafe = classify(files)
    scope = file_scope(files, merge_base, head)
    validate_patches(files, records)
    safe_files = []
    for entry in files:
        safe = {key: entry[key] for key in
                ("filename", "previous_filename", "status", "sha", "additions",
                 "deletions", "changes") if key in entry}
        if "patch" in entry:
            safe["patch"] = (entry["patch"] if
                             records[entry["filename"]]["classification"] == "panel" else "")
        safe_files.append(safe)
    bundle = {
        "schema_version": 1, "head_sha": head, "base_sha": base,
        "merge_base_sha": merge_base, "before": before, "after": after,
        "collector_sha256": checksum((DIRECTORY / "collect-diff.sh").read_bytes()),
        "diff_sha256": checksum(panel), "scope_paths": scope, "files": safe_files,
    }
    bundle["collection_digest"] = checksum(bundle)
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    (output / "panel.diff").write_bytes(panel)
    (output / "collection.json").write_text(json.dumps(bundle, indent=2) + "\n")
    public = {
        key: bundle[key] for key in
        ("schema_version", "head_sha", "base_sha", "merge_base_sha", "collector_sha256",
         "diff_sha256", "scope_paths", "collection_digest")
    }
    public["files"] = [records[name] for name in sorted(records)]
    public["exception"] = "adr004_deletions_only" if not panel and not unsafe else None
    (output / "collection-meta.json").write_text(json.dumps(public, indent=2) + "\n")


def context_at(base):
    sections, digests = [], {}
    for source in SOURCES:
        value = git("show", f"{base}:{source}")
        if not value.strip():
            raise ValueError("collector trusted context is empty")
        digests[source] = checksum(value)
        sections.append(f"BASE SOURCE: {source}\n".encode() + value)
    context = b"\n\n".join(sections)
    if len(context) > 24000:
        raise ValueError("collector trusted context exceeds 24000 bytes")
    return context, digests


def prepare(head, base, merge_base, work, supplied_diff):
    """Shared hook: no bundle means failure, never a raw Git diff fallback."""
    del work
    if supplied_diff is None:
        raise ValueError("MRA requires the approved collector bundle")
    supplied = Path(supplied_diff)
    try:
        bundle = json.loads((supplied.parent / "collection.json").read_bytes())
        panel = supplied.read_bytes()
        recorded = bundle.pop("collection_digest")
    except (OSError, ValueError, KeyError, TypeError):
        raise ValueError("MRA collector bundle is missing or malformed") from None
    if recorded != checksum(bundle) or bundle.get("diff_sha256") != checksum(panel):
        raise ValueError("collector bundle or supplied diff digest mismatch")
    if (bundle.get("schema_version") != 1 or
            (bundle.get("head_sha"), bundle.get("base_sha"), bundle.get("merge_base_sha"))
            != (head, base, merge_base)):
        raise ValueError("collector snapshot differs from requested SHAs")
    snapshots(head, base, merge_base, bundle["before"], bundle["after"])
    collector = git("show", f"{base}:scripts/pr-review/collect-diff.sh")
    if (checksum(collector) != bundle["collector_sha256"] or
            checksum((DIRECTORY / "collect-diff.sh").read_bytes()) != checksum(collector)):
        raise ValueError("collector provenance does not match the base revision")
    files = bundle["files"]
    replay, records, unsafe = classify(files)
    scope = file_scope(files, merge_base, head)
    if replay != panel or scope != bundle["scope_paths"]:
        raise ValueError("collector replay differs from supplied view")
    validate_patches(files, records)
    for entry in files:
        if records[entry["filename"]]["classification"] != "panel" and entry.get("patch"):
            raise ValueError("collector bundle contains a withheld patch")
    selected = sorted(
        (entry for entry in files if records[entry["filename"]]["classification"] == "panel"),
        key=lambda entry: (entry["filename"].endswith(".terraform.lock.hcl"), entry["filename"]),
    )
    excluded = [records[name] for name in sorted(records)
                if records[name]["classification"] != "panel"]
    collector_digest = checksum(panel)
    path_only = []
    for entry in selected:
        if entry["status"] == "renamed" and not entry.get("patch"):
            old, name = entry["previous_filename"], entry["filename"]
            before, after = [
                git("--literal-pathspecs", "ls-tree", "-z", revision, "--", path)
                .split(b"\t", 1)[0].split()
                for revision, path in ((merge_base, old), (head, name))
            ]
            if len(before) != 3 or len(after) != 3 or before[2] != after[2]:
                raise ValueError("collector rename contents differ or are unavailable")
            # Object IDs prove unchanged content without reading either blob.
            extra = b"similarity index 100%\n"
            if before[0] != after[0]:
                extra = b"old mode " + before[0] + b"\nnew mode " + after[0] + b"\n" + extra
            header = f"diff --git a/{old} b/{name}\n".encode()
            panel, count = re.subn(
                rb"(?m)^" + re.escape(header), lambda _: header + extra, panel, count=1,
            )
            if count != 1:
                raise ValueError("collector rename record is unavailable")
        if entry["status"] == "removed" and "patch" not in entry:
            # ADR-004 permits metadata-only oversized deletions. Add the actual
            # tree mode so the shared engine recognizes a complete deletion
            # record; never retrieve the deleted blob to manufacture a hunk.
            name = entry["filename"]
            mode = git("ls-tree", "-z", merge_base, "--", name).split(b" ", 1)[0]
            if not re.fullmatch(rb"(?:100644|100755|120000|160000)", mode):
                raise ValueError("collector deletion mode is unavailable")
            header = f"diff --git a/{name} b/{name}\n".encode()
            panel, count = re.subn(
                rb"(?m)^" + re.escape(header),
                lambda _: header + b"deleted file mode " + mode + b"\n",
                panel, count=1,
            )
            if count != 1:
                raise ValueError("collector deletion record is unavailable")
            path_only.append(name)
    exception = "adr004_deletions_only" if not panel and excluded and not unsafe else None
    failures = []
    if not panel and exception is None:
        failures.append("no_reviewable_input")
    if len(panel) > 95000:
        failures.append("diff_byte_limit")
    if len(panel.split(b"\n")) - int(panel.endswith(b"\n")) > 3000:
        failures.append("diff_line_limit")
    context_at(head)  # Validate candidate context bytes; never use as instructions.
    context, context_digests = context_at(base)
    provenance = {
        "head_sha": head, "base_sha": base, "merge_base_sha": merge_base,
        "collection_digest": recorded, "collector_sha256": checksum(collector),
        "collector_diff_sha256": collector_digest, "diff_sha256": checksum(panel),
        "scope_paths": scope, "path_only": path_only,
        "files": [records[name] for name in sorted(records)], "excluded": excluded,
        "context_sources": context_digests, "exception": exception,
    }
    return {
        "diff": panel, "paths": [entry["filename"] for entry in selected],
        "context": context, "provenance": provenance, "input_failures": failures,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--files", type=Path, required=True)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--merge-base", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    collect(
        json.loads(args.files.read_bytes()), args.output, head=args.head, base=args.base,
        merge_base=args.merge_base, before=json.loads(args.before.read_bytes()),
        after=json.loads(args.after.read_bytes()),
    )


if __name__ == "__main__":
    main()
