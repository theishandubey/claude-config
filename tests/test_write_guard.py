import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUARD = os.path.join(ROOT, "hooks", "write-guard.py")


class WriteGuardTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = os.path.realpath(self.tmp.name)
        self.home = os.path.join(base, "home")
        self.repo = os.path.join(base, "repo")
        os.makedirs(self.home)
        os.makedirs(os.path.join(self.repo, "src"))
        subprocess.run(["git", "init", "-q", self.repo], check=True)
        subprocess.run(["git", "-C", self.repo, "-c", "user.email=t@t", "-c", "user.name=t",
                        "commit", "-q", "--allow-empty", "-m", "init"], check=True)

    def tearDown(self):
        self.tmp.cleanup()

    def guard(self, path, *args, cwd=None, tool="Write", key="file_path", env_extra=None):
        payload = {"tool_name": tool, "tool_input": {key: path}, "cwd": cwd or self.repo}
        env = dict(os.environ, HOME=self.home)
        env.pop("CLAUDE_PROJECT_DIR", None)
        env.update(env_extra or {})
        return subprocess.run([sys.executable, GUARD, *args], input=json.dumps(payload),
                              capture_output=True, text=True, env=env, timeout=30)

    def assertAllowed(self, *a, **k):
        r = self.guard(*a, **k)
        self.assertEqual(r.returncode, 0, r.stderr)

    def assertBlocked(self, *a, **k):
        r = self.guard(*a, **k)
        self.assertEqual(r.returncode, 2)
        self.assertIn("write-guard", r.stderr)

    def test_memory_writes_pass(self):
        self.assertAllowed(f"{self.repo}/.claude/agent-memory/architect/notes.md")
        self.assertAllowed(".claude/agent-memory/architect/MEMORY.md")
        self.assertAllowed(f"{self.repo}/.claude/agent-memory-local/qa-lead/x.md")
        self.assertAllowed(f"{self.home}/.claude/agent-memory/architect/x.md")

    def test_project_files_blocked(self):
        self.assertBlocked(f"{self.repo}/src/app.ts")
        self.assertBlocked("src/app.ts")
        self.assertBlocked(f"{self.repo}/.claude/settings.json")
        self.assertBlocked(f"{self.repo}/.claude/agent-memory")
        self.assertBlocked(f"{self.repo}/.claude/agent-memory/../../src/x.ts")
        self.assertBlocked("/etc/.claude/agent-memory/x")
        self.assertBlocked(f"{self.repo}/src/vendor/.claude/agent-memory/x.ts")
        self.assertBlocked(f"{self.home}/.claude/settings.json")
        self.assertBlocked("/tmp/scratch.md")

    def test_symlinked_memory_dir_blocked(self):
        os.makedirs(os.path.join(self.repo, ".claude"))
        os.symlink("../src", os.path.join(self.repo, ".claude", "agent-memory"))
        self.assertBlocked(f"{self.repo}/.claude/agent-memory/app.ts")

    def test_plans_need_flag_and_naming(self):
        self.assertBlocked(f"{self.repo}/plans/001-add-auth.md")
        self.assertAllowed(f"{self.repo}/plans/001-add-auth.md", "--allow-plans")
        self.assertAllowed(f"{self.repo}/plans/README.md", "--allow-plans")
        self.assertAllowed(f"{self.repo}/advisor-plans/012-x.md", "--allow-plans")
        self.assertBlocked(f"{self.repo}/plans/notes.md", "--allow-plans")
        self.assertBlocked(f"{self.repo}/plans/mode/001-x.md", "--allow-plans")
        self.assertBlocked(f"{self.repo}/src/plans/001-x.md", "--allow-plans")
        self.assertBlocked(f"{self.repo}/plans/001-x.py", "--allow-plans")

    def test_symlinked_plans_dir_blocked(self):
        os.symlink("src", os.path.join(self.repo, "plans"))
        self.assertBlocked(f"{self.repo}/plans/001-x.md", "--allow-plans")

    def test_worktree_may_write_main_checkout_memory(self):
        wt = os.path.join(self.repo, ".claude", "worktrees", "w1")
        subprocess.run(["git", "-C", self.repo, "worktree", "add", "-q", wt], check=True)
        self.assertAllowed(f"{wt}/.claude/agent-memory/a/x.md", cwd=wt)
        self.assertAllowed(f"{self.repo}/.claude/agent-memory/a/x.md", cwd=wt)
        self.assertBlocked(f"{self.repo}/src/x.ts", cwd=wt)

    def test_project_dir_env_is_a_root(self):
        workspace = os.path.dirname(self.repo)
        self.assertAllowed(f"{workspace}/plans/001-x.md", "--allow-plans",
                           env_extra={"CLAUDE_PROJECT_DIR": workspace})

    def test_notebook_and_edit(self):
        self.assertBlocked(f"{self.repo}/nb.ipynb", tool="NotebookEdit", key="notebook_path")
        self.assertBlocked(f"{self.repo}/src/a.ts", tool="Edit")

    def test_malformed_input_fails_closed(self):
        env = dict(os.environ, HOME=self.home)
        r = subprocess.run([sys.executable, GUARD], input="nope", capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 2)


if __name__ == "__main__":
    unittest.main()
