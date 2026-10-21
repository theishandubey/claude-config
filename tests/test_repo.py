import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TIERS = {"advisors": "advisor", "workers": "worker", "explorers": "explorer"}
PLANNERS = {"architect", "backend-engineer", "frontend-engineer", "sre"}


def rd(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def frontmatter(path):
    text = rd(path)
    match = re.match(r"---\n(.*?)\n---\n(.*)", text, re.S)
    assert match, f"{path} has no frontmatter"
    meta, key = {}, None
    for line in match.group(1).splitlines():
        top = re.match(r"^([A-Za-z]+):\s*(.*)$", line)
        if top:
            key, value = top.groups()
            meta[key] = value if value else []
            meta[key + ".raw"] = ""
            continue
        meta[key + ".raw"] += line + "\n"
        item = re.match(r"^  - (\S.*)$", line)
        if item and isinstance(meta[key], list):
            meta[key].append(item.group(1))
    return meta, match.group(2)


def agents():
    out = {}
    for tier in TIERS:
        for name in sorted(os.listdir(os.path.join(ROOT, "agents", tier))):
            path = os.path.join(ROOT, "agents", tier, name)
            meta, body = frontmatter(path)
            out[meta["name"]] = (tier, meta, body, path)
    return out


def vendored_skills():
    return set(json.loads(rd(os.path.join(ROOT, "skills-lock.json")))["skills"])


def tracked_files():
    out = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard"],
                         cwd=ROOT, capture_output=True, text=True, check=True)
    return [f for f in out.stdout.splitlines() if os.path.isfile(os.path.join(ROOT, f))]


class AgentsTest(unittest.TestCase):
    def test_roster_shape(self):
        roster = agents()
        self.assertEqual(len(roster), 10)
        for name, (tier, meta, body, path) in roster.items():
            with self.subTest(agent=name):
                self.assertEqual(os.path.basename(path), name + ".md")
                self.assertTrue(meta.get("description"))
                self.assertIn(meta.get("model"), ("opus", "sonnet"))
                self.assertIn(meta.get("effort"), ("medium", "high"))
                self.assertTrue(body.strip())
                if tier == "advisors":
                    self.assertEqual(meta["model"], "opus")
                    self.assertEqual(meta.get("memory"), "project")
                    hook = meta.get("hooks.raw", "")
                    self.assertIn('matcher: "Write|Edit|NotebookEdit"', hook)
                    self.assertIn("onFailure: block", hook)
                    expected = "write-guard.py\" --allow-plans'" if name in PLANNERS else "write-guard.py\"'"
                    self.assertIn(expected, hook)
                else:
                    self.assertEqual(meta["model"], "sonnet")
                    self.assertNotIn("memory", meta)
                if tier == "explorers":
                    self.assertEqual(meta.get("omitClaudeMd"), "true")
                    self.assertEqual(meta["effort"], "medium")
                if name in PLANNERS:
                    self.assertIn("plan-handoff", meta.get("skills", []))

    def test_referenced_skills_exist(self):
        for name, (_, meta, body, _) in agents().items():
            for skill in meta.get("skills", []):
                with self.subTest(agent=name, skill=skill):
                    self.assertTrue(os.path.isfile(os.path.join(ROOT, "skills", skill, "SKILL.md")))

    def test_readme_table_matches_frontmatter(self):
        readme = rd(os.path.join(ROOT, "README.md"))
        rows = re.findall(r"^\| `([A-Za-z-]+)` \| (\w+) \| (\w+) \| (\w+) \|", readme, re.M)
        table = {name: (tier, model, effort) for name, tier, model, effort in rows}
        roster = agents()
        self.assertEqual(set(table), set(roster))
        for name, (tier, meta, _, _) in roster.items():
            self.assertEqual(table[name], (TIERS[tier], meta["model"], meta["effort"]), name)

    def test_playbook_names_only_real_agents_and_skills(self):
        roster = set(agents())
        skills = set(os.listdir(os.path.join(ROOT, "skills")))
        text = rd(os.path.join(ROOT, "claude", "orchestrator.md"))
        builtins = {"Explore", "Plan", "general-purpose", "security-review", "code-review", "Bash", "plans/", "fable"}
        for token in set(re.findall(r"`([A-Za-z][\w-]*)`", text)):
            if token in builtins or token.startswith(("git", "cd")):
                continue
            with self.subTest(token=token):
                self.assertTrue(token in roster or token in skills, f"unknown name `{token}` in orchestrator.md")
        for name in roster:
            self.assertIn(f"`{name}`", text)


class FilesTest(unittest.TestCase):
    def test_playbook_fits_session_start_limit(self):
        self.assertLess(len(rd(os.path.join(ROOT, "claude", "orchestrator.md"))), 10000)

    def test_no_em_dashes_outside_vendored_skills(self):
        vendored = vendored_skills()
        for path in tracked_files():
            parts = path.split("/")
            if parts[0] == "skills" and len(parts) > 1 and parts[1] in vendored:
                continue
            if path.endswith((".png", ".jpg", ".gif")):
                continue
            with self.subTest(path=path):
                self.assertNotIn("\u2014", rd(os.path.join(ROOT, path)))

    def test_vendored_skills_match_lock(self):
        on_disk = {d for d in os.listdir(os.path.join(ROOT, "skills"))
                   if os.path.isfile(os.path.join(ROOT, "skills", d, "SKILL.md"))}
        own = {"parallel-build", "plan-handoff", "plan-execution", "e2e-tests"}
        self.assertEqual(on_disk, vendored_skills() | own)
        self.assertEqual(os.readlink(os.path.join(ROOT, ".claude", "skills")), "../skills")

    def test_settings_defaults_are_valid(self):
        settings = json.loads(rd(os.path.join(ROOT, "claude", "settings.json")))
        self.assertEqual(settings["permissions"]["defaultMode"], "bypassPermissions")
        commands = [h["command"] for e in settings["hooks"]["PreToolUse"] for h in e["hooks"]]
        self.assertTrue(any("bash-guard.py" in c for c in commands))
        for event in settings["hooks"].values():
            for entry in event:
                for hook in entry["hooks"]:
                    script = re.search(r"hooks/([\w-]+\.py)", hook["command"]).group(1)
                    self.assertTrue(os.access(os.path.join(ROOT, "hooks", script), os.X_OK), script)


class SessionStartTest(unittest.TestCase):
    def run_hook(self, cwd):
        return subprocess.run([sys.executable, os.path.join(ROOT, "hooks", "session-start.py")],
                              input=json.dumps({"cwd": cwd, "source": "startup"}),
                              capture_output=True, text=True, timeout=30)

    def test_prints_the_playbook(self):
        with tempfile.TemporaryDirectory() as tmp:
            r = self.run_hook(tmp)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, rd(os.path.join(ROOT, "claude", "orchestrator.md")))

    def test_links_worktree_memory_to_the_main_checkout(self):
        with tempfile.TemporaryDirectory() as tmp:
            main = os.path.join(os.path.realpath(tmp), "repo")
            git = ["git", "-c", "user.email=t@t", "-c", "user.name=t"]
            subprocess.run(["git", "init", "-q", main], check=True)
            subprocess.run(git + ["-C", main, "commit", "-q", "--allow-empty", "-m", "init"], check=True)
            wt = os.path.join(main, ".claude", "worktrees", "w")
            subprocess.run(["git", "-C", main, "worktree", "add", "-q", wt], check=True)
            os.makedirs(os.path.join(main, ".claude", "agent-memory", "architect"))
            with open(os.path.join(main, ".claude", "agent-memory", "architect", "a.md"), "w") as f:
                f.write("main")
            os.makedirs(os.path.join(wt, ".claude", "agent-memory", "architect"))
            with open(os.path.join(wt, ".claude", "agent-memory", "architect", "b.md"), "w") as f:
                f.write("worktree")
            self.assertEqual(self.run_hook(wt).returncode, 0)
            link = os.path.join(wt, ".claude", "agent-memory")
            self.assertTrue(os.path.islink(link))
            self.assertEqual(os.path.realpath(link), os.path.join(main, ".claude", "agent-memory"))
            self.assertEqual(sorted(os.listdir(os.path.join(link, "architect"))), ["a.md", "b.md"])
            self.assertTrue(os.path.islink(os.path.join(wt, ".claude", "agent-memory-local")))
            self.assertEqual(self.run_hook(wt).returncode, 0)
            self.assertEqual(self.run_hook(main).returncode, 0)
            self.assertFalse(os.path.islink(os.path.join(main, ".claude", "agent-memory")))


if __name__ == "__main__":
    unittest.main()
