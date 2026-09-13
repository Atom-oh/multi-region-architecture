"""Run MRA's real shared entrypoints with local Git and fake provider CLIs."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parent
CORE = Path(os.environ.get("ROLE_REVIEW_TEST_CORE", str(SOURCE))).resolve()
REAL_GIT = shutil.which("git")
SECRET = "SYNTHETIC_STATE_CONTENT_MUST_STAY_WITHHELD"
CANONICAL = "Canonical MRA rule: preserve independent Terraform state ownership."
FAKE = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(ROOT)
args = sys.argv[1:]
name = pathlib.Path(sys.argv[0]).name
if name in ("gh", "claude") and (root / "require-fresh-workspace").exists():
    work = pathlib.Path((root / "work-path").read_text())
    assert not (work / "kiro-quota.flag").exists(), "stale execution flag reached preparation"
if name == "claude" and args == ["--version"]:
    print("offline fixture CLI")
    raise SystemExit(0)
if name == "git":
    if "diff" in args and not any(x in args for x in ("--name-only", "--name-status", "--numstat")):
        with (root / "raw-git.jsonl").open("a") as stream:
            stream.write(json.dumps(args) + "\n")
    os.execv(REAL_GIT, [REAL_GIT] + args)
if name == "gh":
    assert args[:1] == ["api"], args
    if "--slurp" in args:
        print(json.dumps([json.loads((root / "api-files.json").read_text())]))
    elif any("/compare/" in x for x in args):
        print((root / "base").read_text().strip())
    else:
        assert any("/pulls/" in x for x in args), args
        print((root / "head").read_text().strip(), (root / "base").read_text().strip())
    raise SystemExit(0)
data = sys.stdin.read()
with (root / "calls.jsonl").open("a") as stream:
    stream.write(json.dumps({"name": name, "args": args, "stdin": data,
                            "env": {key: os.environ.get(key) for key in
                                    ("GH_TOKEN", "GITHUB_TOKEN", "AWS_ACCESS_KEY_ID")}}) + "\n")
if name == "kiro-cli" and args[1].startswith("Kiro startup safety check."):
    assert data == ""
    if (root / "fail-preflight").exists():
        print("[warn] failed to set model: Method not found", file=sys.stderr)
        raise SystemExit(1)
    print("NO_TOOLS")
    raise SystemExit(0)
model = args[args.index("--model") + 1]
if name == "claude" and args[1].startswith("You chair"):
    if model == "global.anthropic.claude-fable-5-1":
        print("[warn] failed to set model: Method not found", file=sys.stderr)
        raise SystemExit(1)
    print("The candidate is resolved by the supplied evidence.\nVERDICT: PASS")
    raise SystemExit(0)
tag = {"global.openai.gpt-6-astra": "codex", "claude-opus-5": "kiro-fable",
       "gpt-5.6-sol": "kiro-sol", "global.anthropic.claude-fable-5-1": "claude-self"}[model]
work = pathlib.Path((root / "work-path").read_text())
plan = json.loads((work / "role-plan.json").read_text())
role = plan["roles"][tag]
response = {
    "head_sha": plan["head_sha"], "role": role["role"], "scope_complete": True,
    "reviewed_paths": role["paths"],
    "checks": [{"path": role["paths"][0], "evidence": "Checked the complete collector entry."}],
    "findings": [], "uncertainties": [],
}
if (root / "major").exists() and tag == "codex":
    response["findings"] = [{"severity": "MAJOR", "path": role["paths"][0],
                            "condition": "When this fixture changes",
                            "evidence": "Candidate requires chair adjudication."}]
if name == "codex":
    assert "--json" in args and args[-1] == "-", args
    final_path = pathlib.Path(args[args.index("--output-last-message") + 1])
    final_path.write_text(json.dumps(response))
    print(json.dumps({"type": "turn.started"}))
    print(json.dumps({"type": "item.completed", "item": {
        "id": "tool", "type": "command_execution",
        "aggregated_output": "Monthly request limit reached"}}))
    print(json.dumps({"type": "item.completed", "item": {
        "id": "progress", "type": "agent_message", "text": "Checking the supplied diff."}}))
    print(json.dumps({"type": "item.completed", "item": {
        "id": "reply", "type": "agent_message", "text": json.dumps(response)}}))
    print(json.dumps({"type": "turn.completed", "usage": {
        "input_tokens": 1, "cached_input_tokens": 0, "output_tokens": 1}}))
else:
    print(json.dumps(response))
'''


class ProjectEntrypointTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.target = self.repo / "scripts/pr-review"
        self.target.mkdir(parents=True)
        # Optional test-only source selects the parent's in-progress core without
        # overwriting either clone's shared files.
        for path in CORE.glob("*.py"):
            if not path.name.startswith("test_"):
                shutil.copy2(path, self.target / path.name)
        for name in ("run-specialists.sh", "role-controls.sh"):
            shutil.copy2(CORE / name, self.target / name)
        for name in ("collect-diff.sh", "prepare_project_roles.py", "role-project.json",
                     "mra-review-context.md", "lib.sh", "run-panel.sh", "synthesize.sh"):
            shutil.copy2(SOURCE / name, self.target / name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("git", "gh", "codex", "claude", "kiro-cli"):
            path = self.bin / name
            path.write_text(FAKE.replace("ROOT", repr(str(self.root))).replace(
                "REAL_GIT", repr(REAL_GIT)))
            path.chmod(0o755)
        self.environment = {
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "HOME": str(self.root), "GH_REPO": "example/mra",
            "TMPDIR": tempfile.gettempdir(),
            "PYTHONDONTWRITEBYTECODE": "1", "PANEL_RETRIES": "1",
            "PANEL_TIMEOUT": "10", "KIRO_PREFLIGHT_TIMEOUT": "10",
            "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1",
        }
        (self.repo / "CLAUDE.md").write_text(CANONICAL + "\n")
        (self.repo / "AGENTS.md").write_text("Thin navigation must not replace canonical rules.\n")
        (self.repo / "app.txt").write_text("old\n")
        (self.repo / "terraform").mkdir()
        (self.repo / "terraform/example.tfstate").write_text(SECRET + "\n")
        self.git("init", "-q")
        self.git("config", "user.name", "MRA test")
        self.git("config", "user.email", "review@example.invalid")
        self.git("add", ".")
        self.git("commit", "-qm", "trusted base")
        self.base = self.git("rev-parse", "HEAD").strip()
        (self.root / "base").write_text(self.base)
        (self.repo / "app.txt").write_text("new\n")
        (self.repo / "terraform/example.tfstate").unlink()
        self.git("add", ".")
        self.git("commit", "-qm", "candidate")
        self.head = self.git("rev-parse", "HEAD").strip()
        (self.root / "head").write_text(self.head)
        self.git("checkout", "-q", "--detach", self.base)
        self.git("remote", "add", "origin", str(self.repo))
        self.environment.update(HEAD_SHA=self.head, BASE_SHA=self.base)
        self.work = self.root / "work"
        (self.root / "work-path").write_text(str(self.work))
        self.bundle = self.root / "bundle"
        self.files = [
            {"filename": "app.txt", "status": "modified", "changes": 2,
             "patch": "@@ -1 +1 @@\n-old\n+new"},
            {"filename": "terraform/example.tfstate", "status": "removed", "changes": 1,
             "patch": "@@ -1 +0,0 @@\n-" + SECRET},
        ]

    def git(self, *args):
        return subprocess.check_output([REAL_GIT, *args], cwd=self.repo,
                                       env=self.environment).decode()

    def command(self, *args, environment=None):
        return subprocess.run(args, cwd=self.repo, env=environment or self.environment,
                              capture_output=True, text=True, timeout=30)

    def collect(self):
        raw = self.root / "files.json"
        raw.write_text(json.dumps(self.files))
        snapshot = self.root / "snapshot.json"
        snapshot.write_text(json.dumps({"head_sha": self.head, "base_sha": self.base}))
        result = self.command(
            sys.executable, "scripts/pr-review/prepare_project_roles.py",
            "--files", str(raw), "--before", str(snapshot), "--after", str(snapshot),
            "--head", self.head, "--base", self.base, "--merge-base", self.base,
            "--output", str(self.bundle),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        raw.unlink()  # The workflow removes its raw API response before reviewers.

    def prepare(self):
        return self.command(
            sys.executable, "scripts/pr-review/prepare_roles.py",
            "--prepared-diff", str(self.bundle / "panel.diff"), "--work", str(self.work),
        )

    def read_calls(self):
        path = self.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def pipeline(self, major=False):
        self.collect()
        if major:
            (self.root / "major").touch()
        result = self.command(
            "bash", "scripts/pr-review/run-specialists.sh",
            str(self.bundle / "panel.diff"), "unused", str(self.work),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads((self.work / "role-plan.json").read_text())

    def test_real_prepare_rejects_missing_bundle_before_raw_git_diff(self):
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("unrecognized arguments", result.stderr)
        self.assertFalse((self.root / "raw-git.jsonl").exists())
        self.assertEqual(self.read_calls(), [])

    def test_real_pipeline_preserves_state_privacy_and_complete_provenance(self):
        self.environment.update(GH_TOKEN="SYNTHETIC_GH_TOKEN",
                                GITHUB_TOKEN="SYNTHETIC_GITHUB_TOKEN",
                                AWS_ACCESS_KEY_ID="SYNTHETIC_AWS_ID")
        plan = self.pipeline()
        self.assertTrue(plan["input_complete"])
        self.assertEqual(plan["paths"], ["app.txt"])
        self.assertEqual((self.work / "chair-mode.txt").read_text().strip(), "deterministic")
        self.assertEqual(plan["provenance"]["scope_paths"],
                         ["app.txt", "terraform/example.tfstate"])
        source = json.loads((self.work / "role-source.json").read_text())
        self.assertIn(plan["provenance"]["collection_digest"], json.dumps(source))
        calls = self.read_calls()
        for call in calls:
            self.assertIsNone(call["env"]["GH_TOKEN"])
            self.assertIsNone(call["env"]["GITHUB_TOKEN"])
            self.assertEqual(call["env"]["AWS_ACCESS_KEY_ID"],
                             None if call["name"] == "kiro-cli" else "SYNTHETIC_AWS_ID")
        reviews = [call for call in calls if
                   not call["args"][1].startswith("Kiro startup safety check.")]
        self.assertEqual(len(reviews), 4)
        for call in reviews:
            request = json.dumps(call)
            self.assertIn(CANONICAL, request)
            self.assertIn("ADR-004", request)
            self.assertIn("terraform/example.tfstate", request)
            self.assertNotIn(SECRET, request)
        for tag, role in plan["roles"].items():
            if not role["required"]:
                continue
            receipt = json.loads((self.work / "slot" / f"{tag}-request.json").read_text())
            recorded = json.loads((self.work / "slot" / f"{tag}-result.json").read_text())
            self.assertEqual(receipt["invocation_nonce"], recorded["invocation_nonce"])
            self.assertEqual(receipt["request_digest"], recorded["request_digest"])
            prompt = (self.work / "requests" / f"{tag}.prompt").read_bytes().decode()
            payload = (self.work / "requests" / f"{tag}.input").read_bytes().decode()
            call = next(call for call in reviews
                        if call["args"][call["args"].index("--model") + 1] == role["model"])
            if tag == "codex":
                self.assertEqual(call["stdin"], prompt + "\n" + payload)
            elif tag.startswith("kiro-"):
                self.assertEqual(call["args"][1], prompt + "\n" + payload)
            else:
                self.assertEqual(call["args"][1], prompt)
                self.assertEqual(call["stdin"], payload)
                self.assertEqual(call["args"][call["args"].index("--tools") + 1], "")
                self.assertIn("--strict-mcp-config", call["args"])
        self.assertFalse((self.root / "raw-git.jsonl").exists())
        for path in self.work.rglob("*"):
            if path.is_file():
                self.assertNotIn(SECRET.encode(), path.read_bytes(), str(path))

    def test_changed_provenance_invalidates_previously_valid_coverage(self):
        plan = self.pipeline()
        self.assertIn("provenance", plan)
        plan["provenance"]["scope_paths"] = ["app.txt"]
        (self.work / "role-plan.json").write_text(json.dumps(plan))
        result = self.command(
            sys.executable, "scripts/pr-review/role_review.py",
            "aggregate", "--work", str(self.work),
        )
        self.assertEqual(result.returncode, 2)
        self.assertEqual((self.work / "chair-mode.txt").read_text().strip(), "blocked")
        self.assertTrue((self.work / "deterministic-review.md").read_text().endswith("VERDICT: FAIL\n"))

    def test_chair_flags_survive_legacy_removal_and_empty_deny_override(self):
        self.pipeline(major=True)
        (self.target / "synthesize.sh").unlink()
        environment = dict(self.environment, CHAIR_ALLOWED_TOOLS="", CHAIR_DISALLOWED_TOOLS="")
        result = self.command(
            sys.executable, "scripts/pr-review/synthesize_roles.py",
            "--work", str(self.work), "--output", str(self.work / "review.md"),
            environment=environment,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        chairs = [call for call in self.read_calls() if call["args"][1].startswith("You chair")]
        self.assertEqual(len(chairs), 2)
        for call, turns in zip(chairs, ("8", "12")):
            args = call["args"]
            self.assertIn("--max-turns", args)
            self.assertEqual(args[args.index("--max-turns") + 1], turns)
            self.assertIn("--disallowedTools", args)
            denied = set(args[args.index("--disallowedTools") + 1].split(","))
            self.assertTrue({"Bash", "Write", "Edit", "NotebookEdit",
                             "WebFetch", "WebSearch", "Task"} <= denied)
            self.assertNotIn(SECRET, json.dumps(call))
        self.assertTrue((self.work / "review.md").read_text().endswith("VERDICT: PASS\n"))

    def test_mandatory_chair_budget_overrides_fail_before_calling_provider(self):
        self.pipeline(major=True)
        (self.target / "synthesize.sh").unlink()
        before = len(self.read_calls())
        for key, value in (("CHAIR_MAX_TURNS", "0"), ("CHAIR_MAX_TURNS", "9"),
                           ("CHAIR_FALLBACK_MAX_TURNS", "13"), ("CHAIR_TIMEOUT", "601")):
            with self.subTest(setting=key, value=value):
                result = self.command(
                    sys.executable, "scripts/pr-review/synthesize_roles.py",
                    "--work", str(self.work), "--output", str(self.work / "review.md"),
                    environment=dict(self.environment, **{key: value}),
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(self.read_calls()), before)


if __name__ == "__main__":
    unittest.main()
