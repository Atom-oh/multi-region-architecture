"""Exercise the actual activation workflow's collector, runner and artifact paths."""

import json
from pathlib import Path
import re
import unittest

import test_project_integration_roles as integration


WORKFLOW = Path(__file__).resolve().parents[2] / ".github/workflows/pr-review.yml"


class ProjectWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.fixture = integration.ProjectEntrypointTests(
            "test_real_pipeline_preserves_state_privacy_and_complete_provenance")
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.scratch = self.fixture.root / "workflow"
        self.scratch.mkdir()
        self.fixture.work = self.scratch / "pr-review"
        (self.fixture.root / "work-path").write_text(str(self.fixture.work))
        self.fixture.environment.update({
            "REPO": "example/mra", "PR_NUMBER": "1", "PR_TITLE": "Synthetic review",
            "ROLE_REVIEW": "1", "GITHUB_ENV": str(self.scratch / "env"),
            "GITHUB_OUTPUT": str(self.scratch / "output"),
        })
        self.workflow = WORKFLOW.read_text()

    def test_github_token_is_step_scoped(self):
        before_steps = self.workflow.split("    steps:", 1)[0]
        self.assertNotRegex(before_steps, r"(?m)^\s+(?:GH_TOKEN|GITHUB_TOKEN):")
        for name in ("Get PR diff", "Run specialists and conditionally adjudicate findings",
                     "Post review comment (upsert)"):
            self.assertIn("GH_TOKEN: ${{ github.token }}", self.block(name))

    def block(self, name):
        marker = "      - name: " + name + "\n"
        self.assertTrue(marker in self.workflow, "Missing workflow step: " + name)
        return self.workflow.split(marker, 1)[1].split("\n      - ", 1)[0]

    def run_step(self, name, successful=True):
        body = self.block(name).split("        run: |\n", 1)[1]
        lines = []
        for line in body.splitlines():
            if line.strip() and not line.startswith("          "):
                break
            lines.append(line[10:])
        script = "\n".join(lines).replace(
            "${{ github.event.pull_request.head.sha }}", self.fixture.head
        ).replace("/tmp/", str(self.scratch) + "/")
        result = self.fixture.command("bash", "-e", "-c", script)
        if not successful:
            self.assertNotEqual(result.returncode, 0)
            return
        self.assertEqual(result.returncode, 0, name + "\n" + result.stderr)
        env_file = self.scratch / "env"
        if env_file.exists():
            for line in env_file.read_text().splitlines():
                key, separator, value = line.partition("=")
                if separator:
                    self.fixture.environment[key] = value

    def run_workflow(self, expected="pass", before_review=None):
        (self.fixture.root / "api-files.json").write_text(json.dumps(self.fixture.files))
        names = (
            "Prepare fresh review workspace",
            "Verify CLIs present (runner image)",
            "Get PR diff",
            "Build lens prompts (L2-L5 — each self-contained, one lens only)",
            "Run specialists and conditionally adjudicate findings",
            "Check for blocking issues",
        )
        # Execute the selected blocks in their actual YAML order. A cleanup step
        # accidentally moved after collection must not be rescued by test order.
        names = [name for name in names if "      - name: " + name + "\n" in self.workflow]
        names.sort(key=lambda name: self.workflow.index("      - name: " + name + "\n"))
        for name in names:
            if name == "Run specialists and conditionally adjudicate findings" and before_review:
                before_review()
            self.run_step(name)
        self.assertIn("result=" + expected, (self.scratch / "output").read_text())
        upload = self.block("Preserve specialist scope and execution evidence")
        match = re.search(r"(?m)^          path: \|\n((?:            .*\n)+)", upload)
        self.assertIsNotNone(match)
        paths = [line.strip().removeprefix("/tmp/") for line in match.group(1).splitlines()]
        matches = [p for pattern in paths for p in self.scratch.glob(pattern)]
        self.assertTrue(matches, "The actual artifact upload would have no matching files")
        self.assertFalse((self.scratch / "pr-files.json").exists())
        self.assertFalse((self.scratch / "pr-files-pages.json").exists())
        return matches

    def test_mixed_state_deletion_reaches_review_without_its_contents(self):
        artifacts = self.run_workflow()
        calls = self.fixture.read_calls()
        self.assertEqual(len(calls), 6)  # Four required reviews and two no-tools checks.
        self.assertNotIn(integration.SECRET, json.dumps(calls))
        self.assertFalse((self.fixture.root / "raw-git.jsonl").exists())
        plan = json.loads((self.fixture.work / "role-plan.json").read_text())
        self.assertIn(self.fixture.work / "role-source.json", artifacts)
        receipts = list((self.fixture.work / "slot").glob("*-request.json"))
        self.assertEqual(len(receipts), 4)
        self.assertTrue(all(receipt in artifacts for receipt in receipts))
        self.assertFalse(any(self.fixture.work / "requests" in path.parents for path in artifacts))
        self.assertEqual(plan["provenance"]["scope_paths"],
                         ["app.txt", "terraform/example.tfstate"])
        for path in self.scratch.rglob("*"):
            if path.is_file():
                self.assertNotIn(integration.SECRET.encode(), path.read_bytes(), str(path))

    def test_state_only_shortcut_has_evidence_and_invokes_no_provider(self):
        self.fixture.git("checkout", "-q", "--detach", self.fixture.base)
        (self.fixture.repo / "terraform/example.tfstate").unlink()
        self.fixture.git("add", ".")
        self.fixture.git("commit", "-qm", "delete tracked state only")
        self.fixture.head = self.fixture.git("rev-parse", "HEAD").strip()
        self.fixture.git("checkout", "-q", "--detach", self.fixture.base)
        self.fixture.environment["HEAD_SHA"] = self.fixture.head
        (self.fixture.root / "head").write_text(self.fixture.head)
        self.fixture.files = self.fixture.files[1:]
        matches = self.run_workflow()
        self.assertEqual(self.fixture.read_calls(), [])
        self.assertIn(self.scratch / "pr-review-collect/collection-meta.json", matches)
        evidence = json.loads((self.scratch / "pr-review-collect/collection-meta.json").read_text())
        self.assertEqual(evidence["exception"], "adr004_deletions_only")
        self.assertEqual(evidence["head_sha"], self.fixture.head)
        self.assertNotIn(integration.SECRET, json.dumps(evidence))

    def test_prior_flags_are_cleared_before_cli_checks_and_collection(self):
        self.fixture.work.mkdir()
        (self.fixture.work / "kiro-quota.flag").write_text("prior execution\n")
        (self.fixture.work / "source-omission.flag").write_text("prior input\n")
        (self.fixture.root / "require-fresh-workspace").touch()
        self.run_workflow()
        self.assertFalse((self.fixture.work / "kiro-quota.flag").exists())
        self.assertFalse((self.fixture.work / "source-omission.flag").exists())
        self.assertEqual((self.fixture.work / "chair-mode.txt").read_text().strip(), "deterministic")

    def test_current_omission_flag_survives_preparation_and_blocks(self):
        flag = self.fixture.work / "source-omission.flag"
        self.run_workflow(expected="fail", before_review=lambda: flag.write_text("current input\n"))
        self.assertTrue(flag.exists())
        summary = json.loads((self.fixture.work / "role-summary.json").read_text())
        self.assertIn("upstream_omission_flag", summary["failure_codes"])
        self.assertEqual(summary["mode"], "blocked")
        self.assertFalse(any(call["args"][1].startswith("You chair")
                             for call in self.fixture.read_calls()))

    def test_current_preflight_failure_survives_and_blocks(self):
        (self.fixture.root / "fail-preflight").touch()
        self.run_workflow(expected="fail")
        self.assertTrue(list((self.fixture.work / "slot").glob("kiro-preflight-*.flag")))
        summary = json.loads((self.fixture.work / "role-summary.json").read_text())
        self.assertEqual(summary["mode"], "blocked")
        self.assertIn("upstream_preflight_flag", summary["failure_codes"])
        self.assertFalse(any(call["args"][1].startswith("You chair")
                             for call in self.fixture.read_calls()))

    def test_fresh_workspace_rejects_symlink_without_removing_its_target(self):
        outside = self.fixture.root / "outside"
        outside.mkdir()
        sentinel = outside / "keep.txt"
        sentinel.write_text("preserve\n")
        self.fixture.work.symlink_to(outside, target_is_directory=True)
        self.run_step("Prepare fresh review workspace", successful=False)
        self.assertTrue(self.fixture.work.is_symlink())
        self.assertEqual(sentinel.read_text(), "preserve\n")


if __name__ == "__main__":
    unittest.main()
