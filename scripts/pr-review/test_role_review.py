"""Behavioral CLI tests; no network, credentials or model calls."""

from concurrent.futures import ThreadPoolExecutor
import importlib.util
import hashlib
import threading
from types import SimpleNamespace
from unittest.mock import patch as mock_patch
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ENGINE = Path(__file__).with_name("role_review.py")
HEAD = "a" * 40
BASE = "b" * 40
FRONTEND = "dashboard/frontend/components/Button.tsx"
TAGS = ("codex", "kiro-fable", "kiro-sol", "claude-self")


def patch(path=FRONTEND, before="old label", after="new label"):
    return (
        f"diff --git a/{path} b/{path}\n"
        f"--- a/{path}\n+++ b/{path}\n"
        f"@@ -1 +1 @@\n-{before}\n+{after}\n"
    )


class RoleReviewTests(unittest.TestCase):
    def test_publication_redacts_expression_defaults_and_punctuated_keys(self):
        import run_role
        import synthesize_roles

        canary = "SYNTHETIC_ROLLOUT_CANARY"
        cases = [f'password = settings.PASSWORD {operator} "{canary}"\nPUBLIC_AFTER'
                 for operator in ("||", "??", "or")]
        cases += [f'password = (old {operator}\n "{canary}")'
                  for operator in ("||", "??", "or")]
        cases += [f'password: "old {operator}\n{canary}"\nPUBLIC_AFTER'
                  for operator in ("||", "??", "or")]
        cases += [f'password = settings.PASSWORD{before}{operator}{after}"{canary}"\nPUBLIC_AFTER'
                  for operator in ("||", "??", "or")
                  for before, after in ((" ", "\n    "), ("\n    ", " "))]
        cases += [
            f'password = prior || "default"; api_key =\n"{canary}"; PUBLIC_AFTER',
            f'password: "first\n{canary} token=value or last"\nPUBLIC_AFTER',
            f'password = prior || "{canary}"; PUBLIC_AFTER',
        ]
        cases += [
            f'The new secret: name="PASSWORD", value="{canary}"',
            f"""curl -d "password="'{canary}'"&user=demo" https://example.invalid""",
        ]
        cases += [
            f"password = prior  # don't use token='prefix,{canary}'",
            f"password = prior  // don't use token='prefix,{canary}'",
            f"password=https://example.invalid/#{canary}\nPUBLIC_AFTER",
        ]
        cases += [
            f'password = previous ||\n  // local fallback\n  "{canary}"\nPUBLIC_AFTER',
            f'password = previous || // local fallback\n  "{canary}"\nPUBLIC_AFTER',
        ]
        cases += [
            f"The secret: don't use token='prefix,{canary}'\nPUBLIC_AFTER",
            f"password = prior /* don't use token='prefix,{canary}' */\nPUBLIC_AFTER",
        ]
        cases.append(f"""curl -d "password="prefix,{canary}"&user=demo" https://example.invalid""")
        cases += [prefix + json.dumps({key: canary}) + suffix
                  for key in ("/prod/db/password", "password[0]", "api key (prod)")
                  for prefix, suffix in (("", ""), ("Evidence: ", "\nPUBLIC_AFTER"))]
        cases += [f'password = previous {operator} /* local fallback */ "{canary}"\nPUBLIC_AFTER'
                  for operator in ("||", "??")]
        cases += ["Evidence: " + json.dumps({key: item})
                  for key in ("/prod/db/password", "password[0]", "api key (prod)")
                  for item in ({"note": canary}, [canary])]
        cases += [json.dumps({key: canary}, ensure_ascii=False)
                  for key in ("paſſword", "apiKey")]
        cases += [f'password = previous {operator}// local fallback\n"{canary}"\nPUBLIC_AFTER'
                  for operator in ("||", "??")]
        cases += ['Evidence: {"' + key + '": "\\q password=\'prefix", ' + canary + "'}"
                  for key in ("password[0]", "api key (prod)")]
        cases += [prefix + '\"name\" = \"PASSWORD\"\n\"value\" = <<EOF\n' + canary + '\nEOF'
                  for prefix in ("The secret: ", "The new secret: ")]
        cases += [f"```bash\ncat <<'EOF'\n> ```\nEOF\necho '`'\npassword=`printf '{canary}'`\n```",
                  f"<pre>\necho '`'\npassword=`printf '{canary}'`\n</pre>"]
        cases += [f"<script>\n</{tag}>\necho '`'\npassword=`printf '{canary}'`\n</script>"
                  for tag in ("ſcript", "scrİpt", "scrıpt")]
        for index, evidence in enumerate(cases):
            with self.subTest(case=index):
                self.work = self.root / f"publication-{index}"
                plan = self.prepare()
                response = self.response("claude-self", findings=[{
                    "severity": "MINOR", "path": FRONTEND,
                    "condition": "When quoting a configuration example", "evidence": evidence,
                }])
                with mock_patch.object(run_role, "execute", return_value=(0, json.dumps(response), "")):
                    run_role.run(self.work, "claude-self")
                result = self.read("slot/claude-self-result.json")
                self.assertTrue(result["valid"], result["failure_codes"])
                self.assertEqual(result["response"]["reviewed_paths"], [FRONTEND])
                self.assertEqual(result["response"]["findings"][0]["path"], FRONTEND)
                for tag, role in plan["roles"].items():
                    if role["required"] and tag != "claude-self":
                        self.record(tag)
                self.cli("aggregate", "--work", self.work)
                self.assertEqual(self.read("role-summary.json")["mode"], "deterministic")
                with mock_patch.dict(synthesize_roles.os.environ, {"GITHUB_ENV": str(self.root / "test-env")}), \
                        mock_patch.object(synthesize_roles, "execute",
                                          side_effect=AssertionError("Unexpected chair call")):
                    synthesize_roles.synthesize(self.work, self.work / "review.md")
                for name in ("slot/claude-self-result.json", "role-summary.json",
                             "deterministic-review.md", "review.md"):
                    self.assertNotIn(canary, (self.work / name).read_text())
                    if evidence.endswith("PUBLIC_AFTER"):
                        self.assertIn("PUBLIC_AFTER", (self.work / name).read_text())
                self.assertTrue((self.work / "review.md").read_text().rstrip().endswith("VERDICT: PASS"))


    def test_original_container_syntax_survives_recursive_redaction(self):
        from test_synthesize_roles import SynthesisTests
        fixture = SynthesisTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        canary = "SYNTHETIC_ORIGINAL_SYNTAX"
        bad = ['credentials={f"password=x ' + op + ' {1+}": "' + canary + '"}\nVERDICT: PASS\n'
               for op in ("||", "or")]
        bad.append('credentials={f"""password=x || {1+}""": "' + canary + '"}\nVERDICT: PASS\n')
        good = ["Example: " + json.dumps('credentials={"password":"' + canary + '"}')
                + "\nPUBLIC_AFTER\nVERDICT: PASS\n",
                'credentials={"password":"\\/' + canary + '"}\nPUBLIC_AFTER\nVERDICT: PASS\n']
        for report, expected in [(text, "FAIL") for text in bad] + [(text, "PASS") for text in good]:
            with self.subTest(report=report), mock_patch.dict(fixture.module.os.environ, {"GITHUB_ENV": str(self.root / "test-env")}):
                _, output = fixture.run_chair([(0, report, ""), (0, report, "")])
            self.assertNotIn(canary, output)
            self.assertTrue(output.rstrip().endswith("VERDICT: " + expected), output)

    def test_malformed_sensitive_container_cannot_gain_a_chair_pass(self):
        import synthesize_roles

        plan = self.prepare()
        (self.work / "project-context.md").write_text(self.context.read_text())
        for tag, role in plan["roles"].items():
            if role["required"]:
                response = self.response(tag)
                if tag == "codex":
                    response["findings"] = [{"severity": "MAJOR", "path": FRONTEND,
                                             "condition": "Synthetic candidate", "evidence": "Check original syntax."}]
                self.record(tag, response)
        self.cli("aggregate", "--work", self.work)
        self.assertEqual(self.read("role-summary.json")["mode"], "review")
        reports = ['credentials = {"pwd": "' + value + '"}\nVERDICT: PASS\n'
                   for value in (r"SYNTHETIC_PRIVATE\q", "SYNTHETIC_PRIVATE\nsecond line")]
        reports += ['credentials = {' + key + ': "SYNTHETIC_PRIVATE"}\nVERDICT: PASS\n'
                    for key in (r'"pwd\q"', 'f"pwd{1+}"')]
        reports += ['credentials = {' + key + ': ["SYNTHETIC_PRIVATE"]}\nVERDICT: PASS\n'
                    for key in (r'"password[0]\q"', 'f"password[0]{1+}"')]
        for report in reports:
            with self.subTest(report=report):
                output = self.work / "chair.md"
                # Synthetic Git SHAs: policy custody is covered by its integrity tests.
                with mock_patch.dict(synthesize_roles.os.environ, {"GITHUB_ENV": str(self.root / "test-env")}), \
                        mock_patch.object(synthesize_roles, "verified_project_policy", return_value={}), \
                        mock_patch.object(synthesize_roles, "execute", return_value=(0, report, "")):
                    synthesize_roles.synthesize(self.work, output)
                published = output.read_text()
                self.assertNotIn("SYNTHETIC_PRIVATE", published)
                self.assertTrue(published.rstrip().endswith("VERDICT: FAIL"))

    def test_chair_keeps_valid_prose_and_shell_tails(self):
        from test_synthesize_roles import SynthesisTests

        fixture = SynthesisTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        canary = "SYNTHETIC_CHAIR_PRIVATE_VALUE"
        reports = [
            f"password=\"{canary}\" isn't rotated\nPUBLIC_AFTER\nVERDICT: PASS\n",
            f"""curl -d "password="'{canary}'"&user=demo" https://example.invalid
PUBLIC_AFTER
VERDICT: PASS
""",
        ]
        reports += [f"```dotenv\npassword=prefix{opening}{canary}\n```\nPUBLIC_AFTER\nVERDICT: PASS\n"
                    for opening in ("[", "{")]
        reports += [
            f"```dotenv\npassword=prefix[{canary}\n```\n[PUBLIC_AFTER](https://example.invalid)\nVERDICT: PASS\n",
        ]
        reports += [
            "The secret: user's identity is validated.\nPUBLIC_AFTER\nVERDICT: PASS\n",
            "password: customer's default is documented.\nPUBLIC_AFTER\nVERDICT: PASS\n",
            "secret: we're using the documented identity.\nPUBLIC_AFTER\nVERDICT: PASS\n",
        ]
        reports += [
            f"Example: `password=prefix[{canary}` PUBLIC_AFTER\nVERDICT: PASS\n",
            f"Example: `export password=prefix{{{canary}` PUBLIC_AFTER\nVERDICT: PASS\n",
            f"Example: ``password=prefix[{canary}`` PUBLIC_AFTER\nVERDICT: PASS\n",
        ]
        reports += [
            "secret: customer's default\nPUBLIC_AFTER deployment retry is required\nIt isn't recoverable.\nVERDICT: PASS\n",
            f'secret: |\n  password="{canary}\nPUBLIC_AFTER\nVERDICT: PASS\n',
            f"name: PASSWORD\nvalue: 'password=\"{canary}'\nPUBLIC_AFTER\nVERDICT: PASS\n",
        ]
        reports.append(f'secret=<<EOF\npassword="{canary}\nEOF\nPUBLIC_AFTER\nVERDICT: PASS\n')
        reports += [
            f'- Outer item\n    - Checked `export password="{canary}"` here.\nPUBLIC_AFTER\nVERDICT: PASS\n',
            f'```dotenv\npassword=prefix({canary}\n```\nPUBLIC_AFTER\nVERDICT: PASS\n',
            f'```python\npassword = "{canary}\\"suffix"\n```\nPUBLIC_AFTER\nVERDICT: PASS\n',
        ]
        reports += [
            "secret=customer's default\nPUBLIC_AFTER deployment retry is required\nIt isn't recoverable.\nVERDICT: PASS\n",
            "secret=we're using the documented identity\nPUBLIC_AFTER is required\nIt isn't optional.\nVERDICT: PASS\n",
        ]
        reports += ["printf '%s\\n' '" + json.dumps(item) + "'\nPUBLIC_AFTER\nVERDICT: PASS\n"
                    for item in ({"password": canary}, {"public": "x", "password": canary},
                                 {"password": canary, "public": "x"}, [{"password": canary}],
                                 {"name": "TOKEN", "value": None, "password": canary},
                                 {"name": "TOKEN", "value": 123, "password": canary})]
        reports += [f"curl -d 'password=prefix{opening}{canary}' https://example.invalid\nPUBLIC_AFTER\nVERDICT: PASS\n"
                    for opening in ("[", "{")]
        reports += [f"> ```dotenv\n> password=prefix{opening}{canary}\n> ```\nPUBLIC_AFTER\nVERDICT: PASS\n"
                    for opening in ("[", "{")]
        reports.append('printf \'%s\\n\' \'"password": "' + canary + '"\'\nPUBLIC_AFTER\nVERDICT: PASS\n')
        reports += [f'1. Rule\n    Checked `export password="{canary}"` here.\nPUBLIC_AFTER\nVERDICT: PASS\n',
                    f'Checked `export\npassword="{canary}"` here.\nPUBLIC_AFTER\nVERDICT: PASS\n',
                    f'1. Rule\n    Checked `export\n    password="{canary}"` here.\nPUBLIC_AFTER\nVERDICT: PASS\n']
        reports += ['Checked `password=`; empty values are rejected.\nPUBLIC_AFTER\nVERDICT: PASS\n',
                    '```dotenv\npassword=\n```\nPUBLIC_AFTER\nVERDICT: PASS\n']
        reports.append(f"password=\n```text\n{canary}\n```\nPUBLIC_AFTER\nVERDICT: PASS\n")
        reports += [f"```bash\ncat <<'EOF'\n> ```\nEOF\necho '`'\npassword=`printf '{canary}'`\n```\nPUBLIC_AFTER\nVERDICT: PASS\n",
                    f"<pre>\necho '`'\npassword=`printf '{canary}'`\n</pre>\nPUBLIC_AFTER\nVERDICT: PASS\n"]
        reports += [f"<script>\n</{tag}>\necho '`'\npassword=`printf '{canary}'`\n</script>\nPUBLIC_AFTER\nVERDICT: PASS\n"
                    for tag in ("ſcript", "scrİpt", "scrıpt")]
        for report in reports:
            with self.subTest(report=report):
                calls, published = fixture.run_chair([(0, report, ""), (0, report, "")])
                self.assertEqual(calls, 1)
                self.assertNotIn(canary, published)
                self.assertIn("PUBLIC_AFTER", published)
                self.assertTrue(published.rstrip().endswith("VERDICT: PASS"))

    def test_apostrophe_handling_keeps_quoted_credentials_opaque(self):
        import role_review
        canary = "SYNTHETIC_QUOTED_VALUE"
        for value in (f"prefix'{canary} tail'", f"\"owner's {canary}\"", f'"head"middle"{canary}\nTAIL"'):
            clean = role_review.scrub("password=" + value + "\nPUBLIC_AFTER")
            self.assertNotIn(canary, clean)
            self.assertIn("PUBLIC_AFTER", clean)
        for closer in ")]}":
            clean = role_review.scrub("password=literal" + closer + canary + "\nPUBLIC_AFTER")
            self.assertNotIn(canary, clean)
            self.assertIn("PUBLIC_AFTER", clean)
        fenced = "```bash\npassword=prefix'" + canary + "\nTAIL'\n```\nPUBLIC_AFTER"
        clean = role_review.scrub(fenced)
        self.assertNotIn(canary, clean)
        self.assertNotIn("TAIL", clean)
        self.assertIn("PUBLIC_AFTER", clean)
        fenced = "```bash\npassword=owner's\n" + canary + "\n'\n```\nPUBLIC_AFTER"
        clean = role_review.scrub(fenced)
        self.assertNotIn(canary, clean)
        self.assertIn("PUBLIC_AFTER", clean)
        indented = "    password=owner's\n    " + canary + "\n    '\nPUBLIC_AFTER"
        clean = role_review.scrub(indented)
        self.assertNotIn(canary, clean)
        self.assertIn("PUBLIC_AFTER", clean)
        for value in (f"'{canary}", f"(prefix'{canary}", f"os.getenv('NAME', '{canary}'"):
            clean = role_review.scrub("password=" + value + "\nVERDICT: PASS")
            self.assertNotIn(canary, clean)
            self.assertNotIn("VERDICT: PASS", clean)

    def test_json_enclosing_boundaries_require_original_strict_json(self):
        import role_review
        text = 'echo \'{"items":[{"password":"x"}]}\''
        expected = {index for index, char in enumerate(text) if char in "}]"}
        self.assertEqual(role_review._json_enclosing_closers(text), expected)
        for text in ('{"password":"x", "password":"y"}',
                     '{"password":"\\q", "nested":{"public":"x"}}',
                     '{"password":"x", "nested":{"public":"x"},}',
                     '{"password":"x", "nested":{"public":"x"}',
                     "{'password':'x'}"):
            with self.subTest(text=text):
                self.assertEqual(role_review._json_enclosing_closers(text), set())

    def test_container_key_literal_scan_handles_repeated_escaped_quotes(self):
        script = ("import json,sys; from role_review import _normalize_container_keys; "
                  "value=json.load(sys.stdin); print(json.dumps(_normalize_container_keys(value)))")
        value = "Ordinary text\n" + "\\\"" * 20000
        result = subprocess.run([sys.executable, "-c", script], input=json.dumps(value),
                                text=True, capture_output=True, cwd=ENGINE.parent, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), value)

    def test_inline_sensitive_containers_keep_legacy_rejection(self):
        import role_review
        from run_role import scrub as scrub_raw
        from synthesize_roles import valid
        for item in ({"password": {"note": "SYNTHETIC_CONTAINER_VALUE"}},
                     {"api key (one)": {"note": "SYNTHETIC_CONTAINER_VALUE"},
                      "api key (two)": {"note": "SYNTHETIC_CONTAINER_VALUE"}}):
            text = "printf '%s\\n' '" + json.dumps(item) + "'\nPUBLIC_AFTER\nVERDICT: PASS\n"
            clean = role_review.scrub(scrub_raw(text))
            self.assertNotIn("SYNTHETIC_CONTAINER_VALUE", clean)
            self.assertFalse(valid(clean, 0))

    def test_named_heredoc_keeps_legacy_tail_rejection(self):
        import role_review
        from run_role import scrub as scrub_raw
        from synthesize_roles import valid
        for prefix in ("The secret: ", "The new secret: "):
            text = prefix + '\"name\" = \"PASSWORD\"\n\"value\" = <<EOF\nSYNTHETIC_HEREDOC_BODY\nEOF\nVERDICT: PASS\n'
            clean = role_review.scrub(scrub_raw(text))
            self.assertNotIn("SYNTHETIC_HEREDOC_BODY", clean)
            self.assertFalse(valid(clean, 0))

    def test_empty_assignment_does_not_skip_nonclosing_fences(self):
        import role_review
        canary = "SYNTHETIC_FENCE_VALUE"
        examples = ["password=\n```dotenv\n" + canary + "\n```\nPUBLIC_AFTER",
                    "````text\npassword=\n```\n" + canary + "\n````\nPUBLIC_AFTER",
                    "~~~text\npassword=\n```\n" + canary + "\n~~~\nPUBLIC_AFTER"]
        for text in examples:
            with self.subTest(text=text):
                self.assertNotIn(canary, role_review.scrub(text))

    def test_commented_bracket_lookahead_has_bounded_runtime(self):
        script = "import json,sys; from role_review import scrub; print(json.dumps(scrub(json.load(sys.stdin))))"
        lines = [prefix + "password=prefix" + "[" * depth + suffix
                 for prefix, suffix in (("# ", "\n"), ("// ", "\n"), ("/* ", " */\n"))
                 for depth in (1, 2, 8)]
        for line in lines:
            with self.subTest(line=line):
                text = line * 4096
                result = subprocess.run([sys.executable, "-c", script], input=json.dumps(text),
                                        text=True, capture_output=True, cwd=ENGINE.parent, timeout=3)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("prefix", json.loads(result.stdout))

        unique = "".join("# password=prefix" + "".join("{" if number & (1 << bit) else "["
                         for bit in range(11)) + "\n" for number in range(2048))
        # Bound this test child only; production/provider limits are unchanged.
        limited = "import resource; resource.setrlimit(resource.RLIMIT_AS, (256 * 1024 * 1024,) * 2); " + script
        result = subprocess.run([sys.executable, "-c", limited], input=json.dumps(unique),
                                text=True, capture_output=True, cwd=ENGINE.parent, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("prefix", json.loads(result.stdout))

    def test_thematic_break_near_match_has_bounded_runtime(self):
        script = "import json,sys; from role_review import scrub; print(json.dumps(scrub(json.load(sys.stdin))))"
        for marker in ("*", "_"):
            with self.subTest(marker=marker):
                text = marker * 3 + " " * 50000 + "X"
                result = subprocess.run([sys.executable, "-c", script], input=json.dumps(text),
                                        text=True, capture_output=True, cwd=ENGINE.parent, timeout=3)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), text)

    def test_ordinary_prose_scrub_has_bounded_runtime(self):
        prose = "The password is required and the token is optional. " * 80
        script = "import json,sys; from role_review import scrub; print(json.dumps(scrub(json.load(sys.stdin))))"
        result = subprocess.run([sys.executable, "-c", script], input=json.dumps(prose),
                                text=True, capture_output=True, cwd=ENGINE.parent, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), prose)
        canary = "SYNTHETIC_ROLLOUT_CANARY"
        repeated = "Evidence: " + json.dumps([{"password": canary}] * 300, separators=(",", ":"))
        result = subprocess.run([sys.executable, "-c", script], input=json.dumps(repeated),
                                text=True, capture_output=True, cwd=ENGINE.parent, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(canary, json.loads(result.stdout))

        container = "credentials = {'note': '" + "password_" * 500 + "'}\nPUBLIC_AFTER\n"
        container += 'api_key="' + canary + '"\nVERDICT: PASS\n'
        result = subprocess.run([sys.executable, "-c", script], input=json.dumps(container),
                                text=True, capture_output=True, cwd=ENGINE.parent, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        published = json.loads(result.stdout)
        self.assertNotIn("password_" * 10, published)
        self.assertNotIn(canary, published)
        self.assertIn("PUBLIC_AFTER", published)
        self.assertTrue(published.rstrip().endswith("VERDICT: PASS"))

        unmatched = "password=bareprefix[\n" * 4096
        result = subprocess.run([sys.executable, "-c", script], input=json.dumps(unmatched),
                                text=True, capture_output=True, cwd=ENGINE.parent, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout).count("[REDACTED]"), 4096)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.work = self.root / "work"
        self.diff = self.root / "raw.diff"
        self.context = self.root / "context.md"
        self.context.write_text("Trusted base: preserve accepted ADR scopes.\n")

    def tearDown(self):
        self.temp.cleanup()

    def cli(self, *args, expected=0):
        result = subprocess.run(
            [sys.executable, str(ENGINE), *map(str, args)],
            capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(
            result.returncode, expected,
            f"command={args!r}\nstdout={result.stdout}\nstderr={result.stderr}",
        )
        return result

    def prepare(self, diff=None, expected=0, head=HEAD, extra=(), case=None):
        if case is not None:
            self.work = self.root / case
        self.diff.write_text(patch() if diff is None else diff)
        self.cli(
            "prepare", "--diff", self.diff, "--context", self.context,
            "--head", head, "--base", BASE, "--work", self.work, *extra, expected=expected,
        )
        return self.plan()

    def read(self, name):
        return json.loads(self.text(name))

    def text(self, name):
        return (self.work / name).read_text()

    def plan(self):
        return self.read("role-plan.json")

    def summary(self):
        return self.read("role-summary.json")

    def aggregate(self, expected=0):
        return self.cli("aggregate", "--work", self.work, expected=expected)

    def issue(self, tag, expected=0):
        return self.cli("issue", "--work", self.work, "--tag", tag, expected=expected)

    def response(self, tag, **changes):
        plan = self.plan()
        paths = plan["roles"][tag]["paths"]
        result = {
            "head_sha": plan["head_sha"],
            "role": plan["roles"][tag]["role"],
            "scope_complete": True,
            "reviewed_paths": paths,
            "checks": [{"path": paths[0], "evidence": "Checked the changed branch and its caller."}],
            "findings": [],
            "uncertainties": [],
        }
        result.update(changes)
        return result

    def record(self, tag, response=None, raw=None, stderr="", rc=0, expected=0):
        output = self.root / f"{tag}-output.txt"
        diagnostic = self.root / f"{tag}-stderr.txt"
        output.write_text(raw if raw is not None else json.dumps(
            self.response(tag) if response is None else response
        ))
        diagnostic.write_text(stderr)
        receipt = self.work / "slot" / f"{tag}-request.json"
        if not receipt.exists():
            self.issue(tag)
        nonce = json.loads(receipt.read_text())["invocation_nonce"]
        self.cli(
            "record", "--work", self.work, "--tag", tag, "--output", output,
            "--stderr", diagnostic, "--exit-code", rc, "--nonce", nonce, expected=expected,
        )
        return self.read(f"slot/{tag}-result.json")

    def finish(self, overrides=None):
        for tag, role in self.plan()["roles"].items():
            if role["required"]:
                self.record(tag, response=(overrides or {}).get(tag))
        self.aggregate()
        return self.summary()

    def assert_blocked(self):
        self.aggregate(expected=2)
        self.assertEqual(self.summary()["mode"], "blocked")
        self.assertTrue((self.work / "coverage-severe.flag").exists())
        self.assertEqual(self.text("chair-mode.txt"), "blocked\n")
        self.assertTrue(self.text("deterministic-review.md").endswith("VERDICT: FAIL\n"))

    def test_frontend_routing_has_two_independent_full_scope_requests(self):
        raw = patch() + patch("dashboard/frontend/app/styles.css", "blue", "green")
        plan = self.prepare(raw)
        self.assertEqual(plan["schema_version"], 1)
        self.assertEqual(plan["head_sha"], HEAD)
        self.assertEqual(plan["base_sha"], BASE)
        self.assertEqual(set(plan["roles"]), set(TAGS))
        self.assertEqual(plan["roles"]["codex"]["role"], "implementation")
        self.assertEqual(
            {tag for tag, role in plan["roles"].items() if role["required"]},
            {"codex", "claude-self"},
        )
        self.assertNotEqual(plan["roles"]["codex"]["family"], plan["roles"]["claude-self"]["family"])
        for tag in ("codex", "claude-self"):
            role = plan["roles"][tag]
            self.assertEqual(set(role["paths"]), {FRONTEND, "dashboard/frontend/app/styles.css"})
            self.assertEqual(self.text(f"roles/{tag}.diff"), raw)
            prompt = self.text(f"roles/{tag}.txt")
            self.assertIn("Trusted base: preserve accepted ADR scopes.", prompt)
            self.assertIn("untrusted", prompt.lower())
            self.assertIn("scope_complete", prompt)
            self.assertEqual(len(role["request_digest"]), 64)
        self.assertFalse((self.work / "roles/kiro-fable.txt").exists())
        self.assertEqual(self.finish()["mode"], "deterministic")
        self.assertEqual(set(self.text("responded.txt").split()), {"codex", "claude-self"})

    def test_aws_docs_runbooks_and_adrs_activate_all_roles(self):
        for path in ("docs/aws.md", "docs/runbooks/ecs.md", "docs/decisions/ADR-999.md"):
            with self.subTest(path=path):
                plan = self.prepare(patch(path, "old policy", "ECS IAM role and recovery"))
                self.assertTrue(all(role["required"] for role in plan["roles"].values()))

    def test_aws_semantics_in_frontend_and_unknown_paths_are_conservative(self):
        for raw in (
            patch(after='import { S3Client } from "@aws-sdk/client-s3";'),
            patch(after='const region = "us-west-2";'),
            patch(after='const origin = "internal-app.ap-northeast-2.elb.amazonaws.com";'),
            patch(after='const resource = "aws_iam_role";'),
            patch("misc/unknown.xyz"),
            patch("app/src/app/history/page.tsx"),
            patch("dashboard/frontend/app/page.tsx"),
        ):
            with self.subTest(raw=raw):
                plan = self.prepare(raw)
                self.assertTrue(all(role["required"] for role in plan["roles"].values()))

    def test_rename_scope_uses_destination_and_routes_from_full_raw_content(self):
        raw = (
            'diff --git "a/docs/old name.md" "b/docs/new name.md"\n'
            "similarity index 100%\nrename from docs/old name.md\nrename to docs/new name.md\n"
        )
        plan = self.prepare(raw)
        self.assertEqual(plan["roles"]["codex"]["paths"], ["docs/new name.md"])

    def test_unquoted_spaces_use_patch_metadata_not_shlex(self):
        path = "dashboard/frontend/components/A large Button.tsx"
        plan = self.prepare(patch(path))
        self.assertEqual(plan["roles"]["codex"]["paths"], [path])

    def test_authoritative_path_manifest_and_incomplete_manifest(self):
        manifest = self.root / "paths.json"
        manifest.write_text(json.dumps([FRONTEND]))
        self.prepare(extra=("--paths", manifest))
        manifest.write_text(json.dumps(["wrong.tsx"]))
        self.prepare(extra=("--paths", manifest), expected=2)
        self.assert_blocked()

    def test_regular_file_to_symlink_has_two_blocks_for_one_path(self):
        raw = (
            "diff --git a/link b/link\ndeleted file mode 100644\n"
            "--- a/link\n+++ /dev/null\n@@ -1 +0,0 @@\n-old\n"
            "diff --git a/link b/link\nnew file mode 120000\n"
            "--- /dev/null\n+++ b/link\n@@ -0,0 +1 @@\n+target\n"
        )
        manifest = self.root / "paths.json"
        manifest.write_text('["link"]')
        self.assertEqual(self.prepare(raw, extra=("--paths", manifest))["paths"], ["link"])
        self.assertEqual(self.prepare(raw)["paths"], ["link"])

    def test_validated_paths_survive_redaction_without_preserving_sensitive_prose(self):
        for index, path in enumerate(("infra/task-definition-worker.tf",
                                      "tests/surveyJob.test.tsx", "fixtures/password=example.txt")):
            with self.subTest(path=path):
                self.prepare(patch(path), case=f"redacted-path-{index}")
                response = self.response("codex", findings=[{
                    "severity": "MINOR", "path": path, "condition": "Relevant condition",
                    "evidence": "password=private-prose-value",
                }])
                summary = self.finish({"codex": response})
                self.assertEqual(summary["findings"][0]["path"], path)
                result = self.read("slot/codex-result.json")["response"]
                self.assertEqual(result["reviewed_paths"], [path])
                self.assertEqual(result["checks"][0]["path"], path)
                self.assertNotIn("private-prose-value", json.dumps(summary))

    def test_context_default_supports_24000_bytes_and_lower_configured_cap(self):
        self.context.write_text("x" * 22892)
        self.prepare()
        self.prepare(extra=("--context-cap", "12288"), expected=2)
        self.assert_blocked()

    def test_revision_identifiers_must_be_full_hex_sha(self):
        self.prepare(head="HEAD", expected=2)
        self.assert_blocked()

    def test_decoded_credential_strings_are_scrubbed_before_public_json(self):
        self.prepare()
        secret = "ghp_" + "A" * 36
        response = self.response("codex", findings=[{
            "severity": "MINOR", "path": FRONTEND, "condition": "On submission",
            "evidence": "Credential " + secret,
        }])
        raw = json.dumps(response).replace("ghp_", "\\u0067hp_")
        result = self.record("codex", raw=raw)
        self.assertTrue(result["valid"])
        self.assertNotIn(secret, json.dumps(result))
        self.record("claude-self")
        self.aggregate()
        self.assertNotIn(secret, self.text("deterministic-review.md"))

    def test_decoded_values_cover_existing_repository_credential_patterns(self):
        cases = [
            ("xox" + "b-" + "A" * 35, "A" * 35),
            ("AI" + "za" + "B" * 35, "B" * 35),
            ("Authorization: Basic " + "C" * 40, "C" * 40),
            ('{"Authorization": "Basic ' + "Q" * 12 + '"}', "Q" * 12),
            ('access_token="' + "D" * 35 + '"', "D" * 35),
            ('client_secret="' + "E" * 35 + '"', "E" * 35),
            ("aws_access_key_id=" + "F" * 35, "F" * 35),
            ("AWS_SESSION_TOKEN=\n" + "G" * 35, "G" * 35),
            ("postgresql://user:database-private-value@database.local/app", "database-private-value"),
            ("mongodb+srv://user:document-private-value@database.local/app", "document-private-value"),
            ("https://hooks.slack.com/services/T123/B123/webhook-private-value", "webhook-private-value"),
            ('MasterUserPassword = "master-private-value"', "master-private-value"),
            ('dbPassword: "database-private-value"', "database-private-value"),
            ("password: |\n  block-private-value\nnext: safe", "block-private-value"),
            ("- name: DATABASE_PASSWORD\n  value: env-private-value", "env-private-value"),
            ("+  - name: DATABASE_PASSWORD\n+    value: added-env-private", "added-env-private"),
            ("-password: |\n-  removed-block-private\n next: safe", "removed-block-private"),
            ("mongodb://:empty-user-private@database.local/app", "empty-user-private"),
            ("Cookie: session=cookie-private-value", "cookie-private-value"),
            ('originSecret="origin-private-value"', "origin-private-value"),
            ('mcpToken="mcp-private-value"', "mcp-private-value"),
            ("x-origin-verify: origin-header-private", "origin-header-private"),
            ("- name: DATABASE_PASSWORD\n  value: |-\n    yaml-block-private", "yaml-block-private"),
            ("+ - name: DB_PASSWORD\n+   value: >-\n+     diff-block-private", "diff-block-private"),
            ("master_password = <<-EOT\n  heredoc-private\nEOT", "heredoc-private"),
            ("+master_password = <<-END\n+ diff-heredoc-private\n+END", "diff-heredoc-private"),
            ("master_password = <<EOT\ncut-heredoc-private", "cut-heredoc-private"),
            ('master_password = "\\\"escaped-private"', "escaped-private"),
            ('password: "abc\\\"quote-private"', "quote-private"),
            ("password: 'it''s-single-private'", "single-private"),
            ("name: DB_PASSWORD\nvalue: 'it''s-named-private'", "named-private"),
            (r'{\"password\":\"abc\\\"nested-private\"}', "nested-private"),
            ('{"auth":"registry-private"}', "registry-private"),
            (".dockerconfigjson: docker-private", "docker-private"),
        ]
        for index, (text, secret) in enumerate(cases):
            with self.subTest(kind=text.split("=", 1)[0][:24]):
                self.prepare(case=f"decoded-pattern-{index}")
                response = self.response("codex")
                response["checks"][0]["evidence"] = text
                escaped = json.dumps(response).replace(secret, "".join("\\u" + format(ord(char), "04x") for char in secret))
                result = self.record("codex", raw=escaped)
                self.assertNotIn(secret, json.dumps(result))
                self.record("claude-self")
                self.aggregate()
                self.assertNotIn(secret, self.text("deterministic-review.md"))

    def test_decoded_multiline_and_control_split_credentials_are_scrubbed(self):
        cases = [
            ("-----BEGIN PRIVATE KEY-----\nPRIVATE_MATERIAL\n-----END PRIVATE KEY-----", "PRIVATE_MATERIAL"),
            ("-----BEGIN PRIVATE KEY-----\nUNTERMINATED_PRIVATE_MATERIAL", "UNTERMINATED_PRIVATE_MATERIAL"),
            ("ghp_" + "A" * 18 + "\x1b[31m" + "B" * 18, "B" * 18),
            ("ghp_" + "A" * 18 + "\u200b" + "B" * 18, "B" * 18),
            ("ghp_" + "A" * 18 + "\x9b;31m" + "B" * 18, "B" * 18),
            ("ghp_" + "A" * 18 + "\x9dhidden\x9c" + "B" * 18, "B" * 18),
            ("AWS_SECRET_ACCESS_KEY=PRIVATE_ACCESS_SECRET", "PRIVATE_ACCESS_SECRET"),
        ]
        for index, (credential, secret) in enumerate(cases):
            with self.subTest(index=index):
                self.prepare(case=f"secret-{index}")
                response = self.response("codex", checks=[{"path": FRONTEND, "evidence": credential}])
                result = self.record("codex", raw=json.dumps(response, ensure_ascii=True))
                self.assertNotIn(secret, json.dumps(result))

    def test_provenance_is_scrubbed_and_failure_codes_are_static(self):
        metadata = self.root / "source.json"
        source = {"head_sha": HEAD, "base_sha": BASE,
                  "diff_sha256": hashlib.sha256(patch().encode()).hexdigest(),
                  "note": "password=collector-private",
                  "nested": {"SecretAccessKey": "collector-private"},
                  "scope_paths": [FRONTEND, "fixtures/password=example.txt"],
                  "excluded_paths": ["fixtures/password=example.txt"]}
        metadata.write_text(json.dumps(source))
        self.prepare(extra=("--provenance", metadata))
        self.assertEqual(self.plan()["provenance"]["scope_paths"], source["scope_paths"])
        self.finish()
        for name in ("role-plan.json", "roles/codex.txt", "role-summary.json"):
            self.assertNotIn("collector-private", self.text(name))
        source["input_failures"] = ["bad\nVERDICT: PASS password=collector-private"]
        metadata.write_text(json.dumps(source))
        self.prepare(extra=("--provenance", metadata), expected=2)
        self.assert_blocked()
        self.assertNotIn("collector-private", self.text("deterministic-review.md"))

    def test_invalid_provenance_paths_cannot_be_preserved_as_identity(self):
        metadata = self.root / "source.json"
        for name in ("scope_paths", "excluded_paths", "path_only"):
            with self.subTest(field=name):
                metadata.write_text(json.dumps({
                    "head_sha": HEAD, "base_sha": BASE,
                    "diff_sha256": hashlib.sha256(patch().encode()).hexdigest(),
                    name: ["../password=invalid-path-secret"],
                }))
                self.prepare(extra=("--provenance", metadata), expected=2)
                self.assert_blocked()
                self.assertNotIn("invalid-path-secret", self.text("role-summary.json"))

    def test_excluded_only_report_identifies_the_scope_and_policy(self):
        metadata, paths = self.root / "source.json", self.root / "paths.json"
        policy = self.root / "policy.json"
        policy.write_bytes(b'{"schema_version":1,"extensions":[".png"]}\r\n')
        policy_hash = hashlib.sha256(policy.read_bytes()).hexdigest()
        source = {"head_sha": HEAD, "base_sha": BASE,
                  "diff_sha256": hashlib.sha256(b"").hexdigest(),
                  "scope_exception": "configured_exclusions_only",
                  "input_policy_sha256": policy_hash,
                  "scope_paths": ["assets/logo.png"], "excluded_paths": ["assets/logo.png"]}
        metadata.write_text(json.dumps(source))
        paths.write_text("[]")
        args = ("--provenance", metadata, "--paths", paths)
        for opt_in in ((), ("--policy", policy), ("--allow-exclusions-only",),
                       ("--allow-exclusions-only", "--policy", self.root / "missing")):
            with self.subTest(opt_in=opt_in):
                self.prepare("", extra=(*args, *opt_in), expected=2)
                self.assert_blocked()
        opt_in = ("--allow-exclusions-only", "--policy", policy)
        self.prepare("", extra=(*args, *opt_in))
        self.finish()
        report = self.text("deterministic-review.md")
        self.assertIn("assets/logo.png", report)
        self.assertIn(policy_hash, report)
        self.assertIn("NOT_APPLICABLE", report)
        anchor = self.work / "exclusions-policy.json"
        self.assertEqual(anchor.read_bytes(), policy.read_bytes())
        anchor.write_bytes(anchor.read_bytes() + b" ")
        self.assert_blocked()
        policy.write_bytes(policy.read_bytes().replace(b"\r\n", b"\n"))
        self.prepare("", extra=(*args, *opt_in), expected=2)
        self.assert_blocked()
        source["diff_sha256"] = hashlib.sha256(patch().encode()).hexdigest()
        source["input_policy_sha256"] = hashlib.sha256(policy.read_bytes()).hexdigest()
        metadata.write_text(json.dumps(source))
        paths.write_text(json.dumps([FRONTEND]))
        self.prepare(extra=(*args, *opt_in), expected=2)
        self.assert_blocked()

    def test_sensitive_key_and_name_value_shapes_never_reach_public_evidence(self):
        secret = "SYNTHETIC_PRIVATE_SHAPE"
        cases = [{key: secret} for key in (
            "spring.datasource.password", "aws.secret_access_key", "X-Origin-Verify",
            "Authorization", "pwd", "dsn", "connectionString", "auth", ".dockerconfigjson")]
        cases += [
            {"name": "DATABASE_PASSWORD", "value": secret},
            {"HeaderName": "X-Origin-Verify", "HeaderValue": secret},
            'name = "DB_PASSWORD", value = "' + secret + '"',
            json.dumps({"name": "DATABASE_PASSWORD", "value": secret}),
            json.dumps({"SecretString": json.dumps({"password": secret})}),
            'Evidence: ' + json.dumps({"detail": json.dumps({"password": secret})}),
            r'{\"password\":\"' + secret + r'\"}',
        ]
        metadata = self.root / "source.json"
        metadata.write_text(json.dumps({
            "head_sha": HEAD, "base_sha": BASE,
            "diff_sha256": hashlib.sha256(patch().encode()).hexdigest(),
            "cases": cases, "safe": "PUBLIC_KEEP", "author": "PUBLIC_AUTHOR",
        }))
        self.prepare(extra=("--provenance", metadata))
        for name in ("role-plan.json", "roles/codex.txt"):
            self.assertNotIn(secret, self.text(name))
            self.assertIn("PUBLIC_KEEP", self.text(name))
            self.assertIn("PUBLIC_AUTHOR", self.text(name))
        for index, evidence in enumerate(cases):
            with self.subTest(index=index):
                self.prepare(case=f"shapes-{index}")
                text = evidence if isinstance(evidence, str) else json.dumps(evidence)
                response = self.response("codex", checks=[{"path": FRONTEND, "evidence": text}])
                self.record("codex", response)
                self.record("claude-self")
                self.aggregate()
                for name in ("slot/codex-result.json", "role-summary.json", "deterministic-review.md"):
                    self.assertNotIn(secret, self.text(name))

    def test_valid_results_cannot_be_reissued_to_discard_findings_or_uncertainty(self):
        for kind in ("CRITICAL", "MAJOR", "uncertain", "clean"):
            with self.subTest(kind=kind):
                self.prepare(case=kind)
                update = {} if kind == "clean" else (
                    {"uncertainties": ["Caller contract is unavailable."]} if kind == "uncertain" else
                    {"findings": [{"severity": kind, "path": FRONTEND,
                                  "condition": "On concurrent submissions", "evidence": "Update is lost."}]})
                self.record("codex", self.response("codex", **update))
                self.record("claude-self")
                before = {p: p.read_bytes() for p in self.work.rglob("*") if p.is_file()}
                self.issue("codex", expected=2)
                self.assertEqual(before, {p: p.read_bytes() for p in self.work.rglob("*") if p.is_file()})
                self.aggregate()
                self.assertEqual(self.summary()["mode"],
                                 "deterministic" if kind == "clean" else "review")

    def test_truncated_patch_or_bare_header_cannot_claim_complete_input(self):
        for raw in (
            f"diff --git a/{FRONTEND} b/{FRONTEND}\n",
            patch().rsplit("+new label", 1)[0],
            "diff --git a/new.py b/new.py\nnew file mode 100644\n--- /dev/null\n+++ b/new.py\n",
            "diff --git a/old.py b/old.py\ndeleted file mode 100644\n--- a/old.py\n+++ /dev/null\n",
            "diff --git a/new.py b/new.py\nnew file mode 100644\nindex 0000000..7898192\n",
            "diff --git a/new.py b/new.py\nnew file mode 100644\n",
        ):
            with self.subTest(raw=raw):
                self.prepare(raw, expected=2)
                self.assert_blocked()

    def test_empty_file_creation_has_explicit_empty_blob_evidence(self):
        raw = "diff --git a/empty b/empty\nnew file mode 100644\nindex 0000000..e69de29\n"
        self.assertTrue(self.prepare(raw)["input_complete"])

    def test_reprepare_cannot_reuse_old_successful_results(self):
        self.prepare()
        self.finish()
        self.prepare()
        self.assertFalse(list((self.work / "slot").glob("*-result.json")))
        self.assert_blocked()

    def test_reissue_retains_terminal_failure_and_blocks_clean_replacement(self):
        for index, (stderr, code, rc) in enumerate((
            ("[warn] failed to set model", "model_selection_diagnostic", 0),
            ('[ERROR] HTTP 400 body={"reason":"MONTHLY_REQUEST_COUNT"}', "quota_diagnostic", 1),
        )):
            with self.subTest(code=code):
                self.prepare(case=f"terminal-{index}")
                self.record("codex", stderr=stderr, rc=rc, expected=2)
                self.issue("codex")
                self.record("codex")
                self.record("claude-self")
                self.assert_blocked()
                self.assertIn(code, self.read("slot/codex-attempts.json")[0]["failure_codes"])

    def test_incomplete_record_claim_cannot_be_cleared_by_reissue(self):
        self.prepare()
        self.issue("codex")
        (self.work / "slot/codex.record-claim").touch()
        before = {p: p.read_bytes() for p in self.work.rglob("*") if p.is_file()}
        self.issue("codex", expected=2)
        self.assertEqual(before, {p: p.read_bytes() for p in self.work.rglob("*") if p.is_file()})
        self.assert_blocked()

    def test_issued_request_persists_the_exact_framed_payload(self):
        self.prepare()
        self.issue("codex")
        request = self.read("slot/codex-request.json")
        nonce = request["invocation_nonce"]
        payload = self.text("requests/codex.input")
        self.assertTrue(payload.startswith(f"BEGIN DIFF {nonce}\n"))
        self.assertTrue(payload.endswith(f"\nEND DIFF {nonce}\n"))
        self.assertIn(self.diff.read_text(), payload)
        self.prepare()
        self.assertFalse((self.work / "slot/codex-request.json").exists())

    def test_corrupt_attempt_history_produces_a_blocked_summary(self):
        self.prepare()
        self.finish()
        (self.work / "slot/codex-attempts.json").write_text("{broken")
        self.assert_blocked()
        self.assertIn("invalid_attempt_history:codex", self.summary()["failures"])

    def test_hunkless_content_changes_cannot_claim_complete_input(self):
        headers = "diff --git a/file.txt b/file.txt\n"
        cases = (
            headers + "new file mode 100644\n",
            headers + "new file mode 100644\nindex 0000000..1234567\n",
            headers + "new file mode 100644\nindex 0000000..1234567\n--- /dev/null\n+++ b/file.txt\n",
            headers + "deleted file mode 100644\nindex 1234567..0000000\n",
            headers + "old mode 100644\nnew mode 100755\nindex 1234567..abcdef0\n",
            "diff --git a/old.txt b/new.txt\nsimilarity index 85%\n"
            "rename from old.txt\nrename to new.txt\nindex 1234567..abcdef0\n",
            "diff --git a/old.txt b/new.txt\nsimilarity index 85%\n"
            "copy from old.txt\ncopy to new.txt\n",
        )
        for index, raw in enumerate(cases):
            with self.subTest(index=index):
                self.prepare(raw, expected=2, case=f"cut-metadata-{index}")
                self.assert_blocked()

    def test_genuinely_empty_files_and_pure_copies_need_no_hunk(self):
        for raw, expected_path in (
            ("diff --git a/empty.txt b/empty.txt\nnew file mode 100644\n"
             "index 0000000..e69de29\n", "empty.txt"),
            ("diff --git a/empty.txt b/empty.txt\ndeleted file mode 100644\n"
             "index e69de29..0000000\n", "empty.txt"),
            ("diff --git a/old.txt b/new.txt\nsimilarity index 100%\n"
             "copy from old.txt\ncopy to new.txt\n", "new.txt"),
        ):
            with self.subTest(raw=raw):
                self.assertEqual(self.prepare(raw)["paths"], [expected_path])

    def test_unterminated_private_keys_are_removed_from_public_results(self):
        for index, kind in enumerate(("", "RSA ", "EC ", "OPENSSH ")):
            with self.subTest(kind=kind):
                self.prepare(case=f"unterminated-key-{index}")
                secret = "SYNTHETIC_PRIVATE_FRAGMENT"
                evidence = f"-----BEGIN {kind}PRIVATE KEY-----\n{secret}\ncut off"
                response = self.response("codex", findings=[{
                    "severity": "MINOR", "path": FRONTEND,
                    "condition": "When diagnostics contain a partial key", "evidence": evidence,
                }])
                result = self.record("codex", raw=json.dumps(response))
                self.assertTrue(result["valid"])
                self.assertNotIn(secret, json.dumps(result))
                self.record("claude-self")
                self.aggregate()
                self.assertNotIn(secret, self.text("deterministic-review.md"))

    def test_charset_escapes_cannot_split_recoverable_credentials(self):
        for index, escape in enumerate(("\x1b(B", "\x1b)0", "\x1b#8", "\x1b%G")):
            with self.subTest(escape=repr(escape)):
                self.prepare(case=f"charset-{index}")
                evidence = "ghp_" + "A" * 18 + escape + "B" * 18
                response = self.response("codex", checks=[{"path": FRONTEND, "evidence": evidence}])
                result = self.record("codex", raw=json.dumps(response))
                self.assertNotIn("B" * 18, json.dumps(result))
                self.record("claude-self")
                self.aggregate()
                self.assertNotIn("B" * 18, self.text("deterministic-review.md"))

    def test_aws_sdk_credential_field_names_are_redacted(self):
        for index, key in enumerate(("SecretAccessKey", "SessionToken", "AccessKeyId")):
            with self.subTest(key=key):
                self.prepare(case=f"sdk-key-{index}")
                secret = "SYNTHETIC_PRIVATE_SDK_VALUE"
                evidence = json.dumps({key: secret})
                response = self.response("codex", checks=[{"path": FRONTEND, "evidence": evidence}])
                self.assertNotIn(secret, json.dumps(self.record("codex", response=response)))
                self.record("claude-self")
                self.aggregate()
                self.assertNotIn(secret, self.text("deterministic-review.md"))

    def test_concurrent_record_cannot_overwrite_a_failed_attempt(self):
        self.prepare()
        self.record("claude-self")
        spec = importlib.util.spec_from_file_location("record_race_test", ENGINE)
        engine = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(engine)
        output, stderr = self.root / "held-response.json", self.root / "race.stderr"
        output.write_text(json.dumps(self.response("codex")))
        stderr.write_text("Quota exceeded")
        nonce, _, _ = engine.issue_request(self.work, "codex")
        args = dict(work=self.work, tag="codex", output=output, stderr=stderr, nonce=nonce)
        entered, release = threading.Event(), threading.Event()
        original = engine.text_file

        def hold_response(path):
            if Path(path) == stderr:
                entered.set()
                if not release.wait(10):
                    raise AssertionError("record race did not release the first writer")
            return original(path)

        with mock_patch.object(engine, "text_file", side_effect=hold_response):
            with ThreadPoolExecutor(max_workers=1) as pool:
                pending = pool.submit(engine.record, SimpleNamespace(**args, exit_code=0))
                try:
                    self.assertTrue(entered.wait(5))
                    with self.assertRaises(engine.Invalid):
                        engine.issue_request(self.work, "codex")
                    self.assertEqual(engine.record(SimpleNamespace(**args, exit_code=1)), 2)
                finally:
                    release.set()
                self.assertEqual(pending.result(timeout=5), 2)
        self.assert_blocked()
        engine.issue_request(self.work, "codex")
        self.record("codex")
        self.assert_blocked()

    def test_mode_only_and_git_octal_quoted_paths(self):
        for raw, expected_path in (
            ("diff --git a/a file.sh b/a file.sh\nold mode 100644\nnew mode 100755\n", "a file.sh"),
            ('diff --git "a/caf\\303\\251.ts" "b/caf\\303\\251.ts"\n'
             '--- "a/caf\\303\\251.ts"\n+++ "b/caf\\303\\251.ts"\n@@ -1 +1 @@\n-a\n+b\n',
             "café.ts"),
        ):
            with self.subTest(raw=raw):
                plan = self.prepare(raw)
                self.assertEqual(plan["paths"], [expected_path])

    def test_duplicate_record_cannot_replace_a_failed_attempt_with_pass(self):
        self.prepare()
        self.record("codex", rc=1, expected=2)
        self.record("codex", expected=2)
        self.record("claude-self")
        self.assert_blocked()

    def test_deterministic_report_audits_role_routing_and_failure_codes(self):
        self.prepare()
        self.finish()
        report = self.text("deterministic-review.md")
        for value in ("codex", "kiro-fable", "kiro-sol", "claude-self", "implementation",
                      "clear_frontend_only", "inactive"):
            self.assertIn(value, report)
        self.prepare(case="quota-report")
        self.record("codex", stderr="Error: quota exceeded for this account", expected=2)
        self.assert_blocked()
        report = self.text("deterministic-review.md")
        self.assertIn("quota", report)
        self.assertIn("missing_result:claude-self", report)

    def test_source_omission_flag_is_never_ignored(self):
        self.prepare()
        self.finish()
        (self.work / "source-omission.flag").touch()
        self.assert_blocked()

    def test_plan_and_request_digests_bind_head_context_and_full_diff(self):
        first = self.prepare()
        identical = self.prepare()
        self.assertEqual(first["plan_digest"], identical["plan_digest"])
        self.context.write_text("Changed trusted context.\n")
        second = self.prepare()
        self.assertNotEqual(first["plan_digest"], second["plan_digest"])
        self.assertNotEqual(
            first["roles"]["codex"]["request_digest"],
            second["roles"]["codex"]["request_digest"],
        )
        third = self.prepare(patch(after="different label"), head="c" * 40)
        self.assertNotEqual(second["plan_digest"], third["plan_digest"])

    def test_oversized_diff_blocks_without_truncating_role_input(self):
        prefix = patch()
        raw = prefix + "+" + "x" * (95001 - len(prefix) - 1)
        self.prepare(raw, expected=2)
        self.assertEqual(self.text("roles/codex.diff"), raw)
        self.assert_blocked()

    def test_line_limit_and_empty_or_unparseable_inputs_block(self):
        for raw in (patch() + "+x\n" * 3001, "", "not a git diff\n"):
            with self.subTest(raw=raw[:30]):
                self.prepare(raw, expected=2)
                self.assert_blocked()

    def test_utf8_byte_limit_is_not_a_character_limit(self):
        self.prepare(patch(after="é" * 48000), expected=2)
        self.assert_blocked()

    def test_empty_context_blocks_preparation(self):
        self.context.write_text("")
        self.prepare(expected=2)
        self.assert_blocked()

    def test_minor_and_info_findings_allow_deterministic_summary(self):
        self.prepare()
        findings = [
            {"severity": severity, "path": FRONTEND, "condition": "When the label is empty",
             "evidence": "The changed fallback branch has no accessible name."}
            for severity in ("MINOR", "INFO")
        ]
        summary = self.finish({"codex": self.response("codex", findings=findings)})
        self.assertEqual(summary["mode"], "deterministic")
        rendered = self.text("deterministic-review.md")
        self.assertIn("MINOR", rendered)
        self.assertTrue(rendered.endswith("VERDICT: PASS\n"))

    def test_critical_major_or_uncertainties_require_chair_review(self):
        for severity in ("CRITICAL", "MAJOR", None):
            with self.subTest(severity=severity):
                self.prepare(case=f"work-{severity}")
                update = {"uncertainties": ["The caller contract is unavailable."]} if severity is None else {
                    "findings": [{"severity": severity, "path": FRONTEND,
                                  "condition": "On concurrent submissions",
                                  "evidence": "The changed code drops an in-flight update."}]
                }
                summary = self.finish({"codex": self.response("codex", **update)})
                self.assertEqual(summary["mode"], "review")
                self.assertFalse((self.work / "deterministic-review.md").exists())
                self.assertFalse((self.work / "coverage-severe.flag").exists())

    def test_single_json_fence_and_kiro_prefixes_are_supported(self):
        for wrapper in (
            lambda s: "```json\n" + s + "\n```",
            lambda s: "\n".join("> " + line for line in s.splitlines()),
            lambda s: "> ```json\n> " + s + "\n> ```",
        ):
            with self.subTest(wrapper=wrapper):
                self.prepare(case=str(id(wrapper)))
                result = self.record("codex", raw=wrapper(json.dumps(self.response("codex"))))
                self.assertTrue(result["valid"])

    def test_blank_malformed_extra_text_and_duplicate_json_keys_reject(self):
        for raw in ("", "glob found no files", "{}", "[]", "```json\n{}\n```\nPASS",
                    '{"head_sha":"x","head_sha":"y"}'):
            with self.subTest(raw=raw):
                self.prepare(case=str(abs(hash(raw))))
                self.assertFalse(self.record("codex", raw=raw, expected=2)["valid"])
                self.assert_blocked()

    def test_missing_paths_false_scope_empty_checks_and_wrong_role_reject(self):
        changes = (
            {"reviewed_paths": []}, {"scope_complete": False}, {"scope_complete": "true"},
            {"checks": []}, {"checks": [{"path": FRONTEND, "evidence": " "}]},
            {"checks": [{"path": "not/changed.ts", "evidence": "claimed"}]},
            {"role": "claude-self"}, {"head_sha": "c" * 40},
        )
        for index, update in enumerate(changes):
            with self.subTest(update=update):
                self.prepare(case=f"scope-{index}")
                self.record("codex", self.response("codex", **update), expected=2)
                self.assert_blocked()

    def test_findings_need_known_severity_changed_path_condition_and_evidence(self):
        good = {"severity": "MAJOR", "path": FRONTEND, "condition": "When clicked",
                "evidence": "The changed handler raises."}
        for key, bad in (("severity", "PASS"), ("path", "other.py"), ("condition", ""), ("evidence", "")):
            with self.subTest(key=key):
                self.prepare(case=key)
                finding = dict(good, **{key: bad})
                self.record("codex", self.response("codex", findings=[finding]), expected=2)
                self.assert_blocked()

    def test_nonzero_and_specific_stderr_failures_block_even_valid_json(self):
        for index, (rc, stderr) in enumerate((
            (1, ""), (0, "ERROR: INVALID_MODEL_ID secret=do-not-publish-this"),
            (0, "Warning: falling back to another model"),
            (0, "Error: quota exceeded for this account"),
            (0, "An error occurred (ThrottlingException) when invoking the model"),
            (0, "Error: MONTHLY_REQUEST_COUNT"),
            (0, "Error: UsageLimitReachedError"),
            (0, "Warning: Json supplied at /agent/profile.json is invalid"),
        )):
            with self.subTest(rc=rc, stderr=stderr):
                self.prepare(case=f"diagnostic-{index}")
                self.record("codex", rc=rc, stderr=stderr, expected=2)
                self.assert_blocked()
                for file in self.work.rglob("*"):
                    if file.is_file():
                        self.assertNotIn("do-not-publish-this", file.read_text())

    def test_echoed_prompt_words_are_not_diagnostic_failures(self):
        self.prepare()
        result = self.record("codex", stderr=(
            "Review quota handling, fallback logic and model-selection tests.\n"
            "Review MONTHLY_REQUEST_COUNT handling in the supplied source.\n"
            "+ const note = 'quota exceeded';\n"
        ))
        self.assertTrue(result["valid"])

    def test_observed_kiro_diagnostics_reject_valid_json(self):
        diagnostics = (
            "[warn] failed to set model opus ... Method not found",
            "Monthly request limit reached",
            "Error: no agent with name inline-review found",
            "Falling back to user specified default",
        )
        for index, diagnostic in enumerate(diagnostics):
            with self.subTest(diagnostic=diagnostic):
                self.prepare(case=f"observed-kiro-{index}")
                self.record("codex", stderr=diagnostic, expected=2)
                self.assert_blocked()

    def test_echoed_diagnostic_examples_in_diff_are_not_runtime_failures(self):
        self.prepare()
        result = self.record("codex", stderr=(
            '+ "[warn] failed to set model opus ... Method not found"\n'
            "+ Monthly request limit reached\n"
            "+ Error: no agent with name X found\n"
            "+ Falling back to user specified default\n"
            '+ [ERROR] HTTP 400 body={"reason":"MONTHLY_REQUEST_COUNT"}\n'
        ))
        self.assertTrue(result["valid"])

    def test_missing_result_is_blocked_even_when_other_role_found_major(self):
        self.prepare()
        finding = {"severity": "MAJOR", "path": FRONTEND, "condition": "When clicked", "evidence": "Fails."}
        self.record("codex", self.response("codex", findings=[finding]))
        self.assert_blocked()

    def test_stale_plan_request_and_result_tag_fingerprints_block(self):
        for key in ("plan_digest", "request_digest", "head_sha", "tag"):
            with self.subTest(key=key):
                self.prepare(case=f"stale-{key}")
                for tag in ("codex", "claude-self"):
                    self.record(tag)
                p = self.work / "slot/codex-result.json"
                data = json.loads(p.read_text())
                data[key] = "wrong"
                p.write_text(json.dumps(data))
                self.assert_blocked()

    def test_offroster_and_inactive_results_cannot_supply_coverage(self):
        for name in ("intruder", "kiro-fable"):
            with self.subTest(name=name):
                self.prepare(case=name)
                for tag in ("codex", "claude-self"):
                    self.record(tag)
                shutil_source = self.work / "slot/codex-result.json"
                (self.work / f"slot/{name}-result.json").write_bytes(shutil_source.read_bytes())
                self.assert_blocked()

    def test_corrupt_slot_and_plan_metadata_fail_closed(self):
        self.prepare()
        for tag in ("codex", "claude-self"):
            self.record(tag)
        (self.work / "slot/codex-result.json").write_text("{bad")
        self.assert_blocked()
        plan = self.plan()
        plan["roles"]["claude-self"]["required"] = False
        (self.work / "role-plan.json").write_text(json.dumps(plan))
        self.assert_blocked()

    def test_failure_flags_override_valid_responses_and_remove_stale_pass(self):
        for name in ("kiro-preflight-failed.flag", "kiro-fallback.flag", "kiro-quota.flag",
                     "slot/kiro-diff-truncated.flag", "diff-truncated.flag", "slot/coverage-severe.flag"):
            with self.subTest(name=name):
                self.prepare(case=name.replace("/", "-"))
                self.finish()
                (self.work / name).touch()
                self.assert_blocked()

    def test_aggregate_revalidates_payload_and_does_not_trust_valid_boolean(self):
        self.prepare()
        for tag in ("codex", "claude-self"):
            self.record(tag)
        file = self.work / "slot/codex-result.json"
        result = self.read("slot/codex-result.json")
        result["response"]["scope_complete"] = False
        file.write_text(json.dumps(result))
        self.assert_blocked()


if __name__ == "__main__":
    unittest.main()
