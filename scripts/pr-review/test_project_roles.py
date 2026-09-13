"""Exercise MRA's collector boundary without network access or model calls."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import role_review


SOURCE = Path(__file__).resolve().parent
ADAPTER = SOURCE / "prepare_project_roles.py"
MARKER = "SYNTHETIC_STATE_BODY_MUST_NOT_REACH_REVIEW"


class ProjectInputTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.previous = Path.cwd()
        os.chdir(self.repo)
        self.addCleanup(os.chdir, self.previous)
        self.git("init", "-q")
        self.git("config", "user.name", "Review fixture")
        self.git("config", "user.email", "review@example.invalid")
        target = self.repo / "scripts/pr-review"
        target.mkdir(parents=True)
        for name in ["collect-diff.sh", "role-project.json", "mra-review-context.md"]:
            path = SOURCE / name
            if path.exists():
                shutil.copy2(path, target / name)
        (self.repo / "CLAUDE.md").write_text("Canonical rule: preserve CloudFront ownership.\n")
        (self.repo / "AGENTS.md").write_text("Thin navigation only.\n")
        (self.repo / "terraform").mkdir()
        self.state = self.repo / "terraform/example.tfstate"
        self.state.write_text(json.dumps({"fixture": MARKER}) + "\n")
        (self.repo / "app.txt").write_text("old\n")
        self.git("add", ".")
        self.git("commit", "-qm", "base")
        self.base = self.git("rev-parse", "HEAD").strip()
        self.bundle = self.root / "bundle"

    def git(self, *args):
        return subprocess.check_output(["git", *args]).decode()

    def adapter(self):
        self.assertTrue(ADAPTER.exists(), "MRA has no collector-bound adapter; raw fallback is unsafe")
        spec = importlib.util.spec_from_file_location("mra_project_input", ADAPTER)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def commit_change(self):
        self.git("add", ".")
        self.git("commit", "-qm", "candidate")
        head = self.git("rev-parse", "HEAD").strip()
        self.git("checkout", "-q", "--detach", self.base)
        return head

    def mixed_change(self):
        self.state.unlink()
        (self.repo / "app.txt").write_text("new\n")
        return self.commit_change(), [
            {"filename": "terraform/example.tfstate", "status": "removed", "changes": 1,
             "additions": 0, "deletions": 1, "sha": "a" * 40,
             "patch": "@@ -1 +0,0 @@\n-" + json.dumps({"fixture": MARKER})},
            {"filename": "app.txt", "status": "modified", "changes": 2,
             "additions": 1, "deletions": 1, "sha": "b" * 40,
             "patch": "@@ -1 +1 @@\n-old\n+new"},
        ]

    def collect(self, head, files, before=None, after=None):
        snapshot = {"head_sha": head, "base_sha": self.base}
        module = self.adapter()
        module.collect(
            files, self.bundle, head=head, base=self.base, merge_base=self.base,
            before=before or snapshot, after=after or snapshot,
        )
        return module

    def prepare(self, module, head, supplied=None):
        return module.prepare(
            head, self.base, self.base, self.root / "work",
            supplied or self.bundle / "panel.diff",
        )

    def test_mixed_state_deletion_never_leaves_collector_bundle(self):
        head, files = self.mixed_change()
        module = self.collect(head, files)
        result = self.prepare(module, head)
        self.assertIn(b"-old\n+new", result["diff"])
        self.assertNotIn(MARKER.encode(), result["diff"])
        for path in self.bundle.rglob("*"):
            if path.is_file():
                self.assertNotIn(MARKER.encode(), path.read_bytes(), str(path))
        self.assertEqual(result["paths"], ["app.txt"])
        self.assertEqual(result["provenance"]["scope_paths"],
                         ["app.txt", "terraform/example.tfstate"])
        self.assertEqual(result["provenance"]["excluded"][0]["classification"],
                         "state_deleted")

    def test_state_only_deletion_has_explicit_exception_without_body(self):
        self.state.unlink()
        head = self.commit_change()
        files = [{"filename": "terraform/example.tfstate", "status": "removed",
                  "changes": 1, "patch": "@@ -1 +0,0 @@\n-" + MARKER}]
        result = self.prepare(self.collect(head, files), head)
        self.assertEqual(result["diff"], b"")
        self.assertEqual(result["paths"], [])
        self.assertEqual(result["provenance"]["exception"], "adr004_deletions_only")
        self.assertNotIn(MARKER, json.dumps(result["provenance"]))

    def test_public_collection_metadata_explains_exception_without_patches(self):
        self.state.unlink()
        head = self.commit_change()
        files = [{"filename": "terraform/example.tfstate", "status": "removed",
                  "changes": 1, "patch": "@@ -1 +0,0 @@\n-" + MARKER}]
        self.collect(head, files)
        public = self.bundle / "collection-meta.json"
        self.assertTrue(public.exists(), "Deletion shortcut needs a publishable artifact")
        metadata = json.loads(public.read_text())
        self.assertEqual(metadata["exception"], "adr004_deletions_only")
        self.assertEqual(metadata["head_sha"], head)
        self.assertEqual(metadata["scope_paths"], ["terraform/example.tfstate"])
        self.assertNotIn("patch", metadata["files"][0])
        self.assertNotIn(MARKER, public.read_text())

    def test_scope_provenance_retains_safe_files_api_metadata(self):
        head, files = self.mixed_change()
        files[0]["sha"] = self.git("rev-parse", f"{self.base}:terraform/example.tfstate").strip()
        files[1]["sha"] = self.git("rev-parse", f"{head}:app.txt").strip()
        result = self.prepare(self.collect(head, files), head)
        public = json.loads((self.bundle / "collection-meta.json").read_text())
        for records in (result["provenance"]["files"], public["files"]):
            by_path = {entry["filename"]: entry for entry in records}
            for entry in files:
                preserved = by_path[entry["filename"]]
                self.assertEqual(preserved.get("sha"), entry["sha"])
                self.assertEqual(preserved.get("changes"), entry["changes"])
                self.assertEqual(preserved.get("additions"), entry["additions"])
                self.assertEqual(preserved.get("deletions"), entry["deletions"])
                self.assertNotIn("patch", preserved)

    def test_state_modification_and_rename_remain_forbidden(self):
        self.state.write_text("changed\n")
        head = self.commit_change()
        for entry in [
            {"filename": "terraform/example.tfstate", "status": "modified",
             "changes": 2, "patch": "@@ -1 +1 @@\n-old\n+new"},
            {"filename": "app.txt", "previous_filename": "terraform/example.tfstate",
             "status": "renamed", "changes": 0},
        ]:
            with self.subTest(status=entry["status"]):
                with self.assertRaisesRegex(ValueError, "collector|state"):
                    self.collect(head, [entry])

    def test_changed_snapshot_and_wrong_requested_head_are_rejected(self):
        head, files = self.mixed_change()
        with self.assertRaisesRegex(ValueError, "snapshot"):
            self.collect(head, files, after={"head_sha": "f" * 40, "base_sha": self.base})
        module = self.collect(head, files)
        with self.assertRaisesRegex(ValueError, "snapshot"):
            module.prepare("f" * 40, self.base, self.base, self.root / "work",
                           self.bundle / "panel.diff")

    def test_missing_file_in_api_metadata_blocks_even_if_patch_is_valid(self):
        head, files = self.mixed_change()
        with self.assertRaisesRegex(ValueError, "scope"):
            self.collect(head, files[:1])

    def test_missing_bundle_and_raw_diff_cannot_fall_back(self):
        head, files = self.mixed_change()
        raw = self.root / "raw.diff"
        raw.write_bytes(subprocess.check_output(["git", "diff", self.base, head]))
        module = self.adapter()
        with self.assertRaisesRegex(ValueError, "collector|bundle"):
            self.prepare(module, head, raw)
        self.collect(head, files)
        (self.bundle / "panel.diff").write_bytes(raw.read_bytes())
        with self.assertRaisesRegex(ValueError, "digest|collector"):
            self.prepare(module, head)

    def test_truncated_hunk_is_rejected_before_role_preparation(self):
        head, files = self.mixed_change()
        files[1]["patch"] = "@@ -1 +1 @@\n-old"
        with self.assertRaisesRegex(ValueError, "hunk|patch"):
            self.collect(head, files)

    def test_canonical_base_rules_and_adr_summary_reach_tools_free_roles(self):
        (self.repo / "CLAUDE.md").write_text("UNTRUSTED candidate instructions.\n")
        head = self.commit_change()
        files = [{"filename": "CLAUDE.md", "status": "modified", "changes": 2,
                  "patch": "@@ -1 +1 @@\n-Canonical rule: preserve CloudFront ownership."
                           "\n+UNTRUSTED candidate instructions."}]
        result = self.prepare(self.collect(head, files), head)
        self.assertIn(b"Canonical rule: preserve CloudFront ownership.", result["context"])
        self.assertIn(b"ADR-004", result["context"])
        self.assertIn(b"ADR-003", result["context"])
        self.assertNotIn(b"Thin navigation only.", result["context"])
        self.assertNotIn(b"UNTRUSTED candidate", result["context"])

    def test_spaces_and_rename_paths_use_api_metadata(self):
        old = self.repo / "app.txt"
        new = self.repo / "new name.txt"
        old.rename(new)
        head = self.commit_change()
        files = [{"filename": "new name.txt", "previous_filename": "app.txt",
                  "status": "renamed", "changes": 0}]
        result = self.prepare(self.collect(head, files), head)
        self.assertEqual(result["paths"], ["new name.txt"])
        self.assertEqual(result["provenance"]["scope_paths"], ["app.txt", "new name.txt"])
        self.assertIn(b"rename from app.txt\nrename to new name.txt", result["diff"])

    def test_oversized_source_is_retained_and_explicitly_blocked(self):
        large = "x" * 96000
        (self.repo / "app.txt").write_text(large + "\n")
        head = self.commit_change()
        files = [{"filename": "app.txt", "status": "modified", "changes": 2,
                  "patch": "@@ -1 +1 @@\n-old\n+" + large}]
        result = self.prepare(self.collect(head, files), head)
        self.assertIn(large.encode(), result["diff"])
        self.assertIn("diff_byte_limit", result["input_failures"])

    def test_unreviewed_binary_addition_is_not_deletion_only_exception(self):
        (self.repo / "new.png").write_bytes(b"\x89PNG\0fixture")
        head = self.commit_change()
        files = [{"filename": "new.png", "status": "added", "changes": 0}]
        result = self.prepare(self.collect(head, files), head)
        self.assertIsNone(result["provenance"]["exception"])
        self.assertIn("no_reviewable_input", result["input_failures"])

    def test_added_state_cannot_claim_deletion_metadata(self):
        (self.repo / "terraform/new.tfstate").write_text("fixture\n")
        head = self.commit_change()
        files = [{"filename": "terraform/new.tfstate", "status": "removed",
                  "changes": 1, "patch": "@@ -1 +0,0 @@\n-fixture"}]
        with self.assertRaisesRegex(ValueError, "scope|status"):
            self.collect(head, files)

    def engine_plan(self, result, head):
        work = self.root / "engine"
        (self.root / "engine.diff").write_bytes(result["diff"])
        (self.root / "engine.context").write_bytes(result["context"])
        (self.root / "engine.paths").write_text(json.dumps(result["paths"]))
        (self.root / "engine.provenance").write_text(json.dumps(result["provenance"]))
        status = role_review.main([
            "prepare", "--head", head, "--base", self.base, "--work", str(work),
            "--diff", str(self.root / "engine.diff"),
            "--context", str(self.root / "engine.context"),
            "--paths", str(self.root / "engine.paths"),
            "--provenance", str(self.root / "engine.provenance"),
        ])
        return status, json.loads((work / "role-plan.json").read_text())

    def test_existing_engine_accepts_complete_collector_view(self):
        head, files = self.mixed_change()
        result = self.prepare(self.collect(head, files), head)
        status, plan = self.engine_plan(result, head)
        self.assertEqual(status, 0, plan["input_failures"])
        self.assertTrue(plan["input_complete"])
        self.assertEqual(plan["paths"], ["app.txt"])

    def test_large_deleted_text_stays_metadata_only_and_engine_compatible(self):
        (self.repo / "large.txt").write_text("SYNTHETIC_OLD_TEXT\n" * 20)
        self.git("add", ".")
        self.git("commit", "-qm", "base large file")
        self.base = self.git("rev-parse", "HEAD").strip()
        (self.repo / "large.txt").unlink()
        head = self.commit_change()
        files = [{"filename": "large.txt", "status": "removed",
                  "changes": 20, "deletions": 20, "additions": 0}]
        result = self.prepare(self.collect(head, files), head)
        self.assertNotIn(b"SYNTHETIC_OLD_TEXT", result["diff"])
        status, plan = self.engine_plan(result, head)
        self.assertEqual(status, 0, plan["input_failures"])
        self.assertEqual(plan["paths"], ["large.txt"])
        self.assertEqual(result["provenance"]["path_only"], ["large.txt"])

    def test_oversized_candidate_context_is_rejected_not_promoted(self):
        oversized = "UNTRUSTED " * 3000
        (self.repo / "CLAUDE.md").write_text(oversized + "\n")
        head = self.commit_change()
        files = [{"filename": "CLAUDE.md", "status": "modified", "changes": 2,
                  "patch": "@@ -1 +1 @@\n-Canonical rule: preserve CloudFront ownership."
                           "\n+" + oversized}]
        module = self.collect(head, files)
        with self.assertRaisesRegex(ValueError, "context"):
            self.prepare(module, head)


if __name__ == "__main__":
    unittest.main()
