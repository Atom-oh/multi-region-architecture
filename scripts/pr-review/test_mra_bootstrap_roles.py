"""MRA bootstrap must block raw fallback and retain its execution controls."""

import os
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import prepare_roles
import run_role
import synthesize_roles
import test_integrity_roles as fixtures


class MraBootstrapTests(unittest.TestCase):
    def test_required_adapter_blocks_before_raw_git_diff(self):
        base = "b" * 40
        calls = []
        def command(*args):
            calls.append(args)
            if args[:2] in (("git", "rev-parse"), ("gh", "api")):
                return base
            self.fail("Raw Git preparation reached before the required MRA adapter")
        with tempfile.TemporaryDirectory() as work, \
                patch.dict(os.environ, {"GH_REPO": "example/mra"}), \
                patch.object(prepare_roles, "command", side_effect=command), \
                patch.object(prepare_roles, "git_file", return_value=None), \
                patch.object(prepare_roles.subprocess, "run",
                             return_value=subprocess.CompletedProcess([], 0)):
            with self.assertRaisesRegex(ValueError, "Project adapter differs"):
                prepare_roles.prepare("a" * 40, base, Path(work), Path(work) / "panel.diff")
        self.assertFalse(any("diff" in args for args in calls))

    def test_installed_mra_profile_enforces_chair_limits(self):
        policy = prepare_roles.project_policy()
        self.assertEqual(policy["input_adapter"], "prepare_project_roles.py")
        options = synthesize_roles.chair_options(policy)
        self.assertEqual((options["timeout"], options["turns"]), (600, (8, 12)))
        for tool in ("Bash", "Write", "Edit", "NotebookEdit", "WebFetch", "WebSearch", "Task"):
            self.assertIn(tool, options["deny"])

    def test_mra_evidence_cap_blocks_without_truncation_or_provider_call(self):
        with tempfile.TemporaryDirectory() as folder:
            work = Path(folder)
            (work / "chair-mode.txt").write_text("review\n")
            (work / "role-summary.json").write_text('{"findings":[]}')
            (work / "project-context.md").write_text("Trusted context.")
            (work / "roles").mkdir()
            (work / "roles/codex.diff").write_text("Complete diff.")
            (work / "slot").mkdir()
            result = work / "slot/codex-result.json"
            body = json.dumps({"response": {"evidence": "é" * 11000}}, ensure_ascii=False)
            result.write_text(body)
            output = work / "review.md"
            with patch.object(synthesize_roles, "execute", return_value=(
                    0, "Must not run.\nVERDICT: PASS\n", "")) as invoke:
                synthesize_roles.synthesize(work, output)
            self.assertEqual(invoke.call_count, 0)
            self.assertTrue(output.read_text().endswith("VERDICT: FAIL\n"))
            self.assertIn("PANEL_CELL_CAP", output.read_text())
            self.assertEqual(result.read_text(), body)

    def test_claude_specialist_has_no_tools_or_github_token(self):
        fixture = fixtures.IntegrityTests("test_codex_tool_data_is_not_a_diagnostic_or_review")
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        with patch.dict(os.environ, {"GH_TOKEN": "SYNTHETIC_TOKEN",
                                    "GITHUB_TOKEN": "SYNTHETIC_TOKEN"}), \
                patch.object(run_role, "execute",
                             return_value=(0, fixture.response("claude-self"), "")) as invoke:
            run_role.run(fixture.work, "claude-self")
        command, _, environment, _, _ = invoke.call_args.args
        self.assertEqual(command[command.index("--tools") + 1], "")
        self.assertIn("--strict-mcp-config", command)
        self.assertNotIn("GH_TOKEN", environment)
        self.assertNotIn("GITHUB_TOKEN", environment)


if __name__ == "__main__":
    unittest.main()
