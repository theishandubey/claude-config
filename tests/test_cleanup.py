import os
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "scripts", "cleanup.py")
OLD = time.time() - 30 * 86400


def wr(path, text="x"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def age(path):
    for dirpath, dirnames, files in os.walk(path):
        for name in dirnames + files:
            os.utime(os.path.join(dirpath, name), (OLD, OLD), follow_symlinks=False)
    os.utime(path, (OLD, OLD))


class CleanupTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = os.path.realpath(self.tmp.name)
        self.repo = os.path.join(self.base, "repo")
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1",
                        GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
        self.git(self.base, "init", "-q", "-b", "main", self.repo)
        wr(os.path.join(self.repo, ".gitignore"), "__pycache__/\n.next/\n.turbo/\ntarget/\nwt/\n.env\nlink\n.DS_Store\n.venv/\n")
        wr(os.path.join(self.repo, "README"))
        self.git(self.repo, "add", ".")
        self.git(self.repo, "commit", "-qm", "init")

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, cwd, *args):
        return subprocess.run(["git", "-C", cwd, *args], env=self.env, check=True,
                              capture_output=True, text=True).stdout

    def cleanup(self, *args, cwd=None, expect=0):
        r = subprocess.run([sys.executable, SCRIPT, *args], cwd=cwd or self.base, env=self.env,
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, expect, r.stdout + r.stderr)
        return r.stdout

    def worktree(self, name, commit=False):
        path = os.path.join(self.repo, "wt", name)
        self.git(self.repo, "worktree", "add", "-q", "-b", name, path)
        if commit:
            wr(os.path.join(path, name))
            self.git(path, "add", ".")
            self.git(path, "commit", "-qm", name)
        age(path)
        age(os.path.join(self.repo, ".git", "worktrees", name))
        return path

    def branches(self):
        return self.git(self.repo, "branch", "--format=%(refname:short)").split()

    def test_dry_run_changes_nothing(self):
        merged = self.worktree("merged")
        out = self.cleanup("--repo", self.repo)
        self.assertIn("remove", out)
        self.assertIn("Dry run", out)
        self.assertTrue(os.path.isdir(merged))
        self.assertIn("merged", self.branches())

    def test_removes_only_merged_clean_idle_worktrees(self):
        merged = self.worktree("merged")
        unmerged = self.worktree("unmerged", commit=True)
        dirty = self.worktree("dirty")
        wr(os.path.join(dirty, "README"), "changed")
        untracked = self.worktree("untracked")
        wr(os.path.join(untracked, "new-file"))
        locked = self.worktree("locked")
        self.git(self.repo, "worktree", "lock", locked)
        fresh = os.path.join(self.repo, "wt", "fresh")
        self.git(self.repo, "worktree", "add", "-q", "-b", "fresh", fresh)
        out = self.cleanup("--repo", self.repo, "--yes")
        self.assertFalse(os.path.exists(merged), out)
        self.assertNotIn("merged", self.branches())
        for path in (unmerged, dirty, untracked, locked, fresh):
            self.assertTrue(os.path.isdir(path), f"{path} was removed:\n{out}")
        self.assertIn("commits not in main", out)
        self.assertIn("uncommitted or untracked changes", out)
        self.assertIn("locked", out)
        self.assertIn("active 0.0 days ago", out)

    def test_merged_branch_counts_after_merge(self):
        path = self.worktree("feature", commit=True)
        self.git(self.repo, "merge", "-q", "--ff-only", "feature")
        self.cleanup("--repo", self.repo, "--yes")
        self.assertFalse(os.path.exists(path))
        self.assertNotIn("feature", self.branches())

    def test_min_age_zero_removes_fresh_worktree(self):
        path = os.path.join(self.repo, "wt", "fresh")
        self.git(self.repo, "worktree", "add", "-q", "-b", "fresh", path)
        self.cleanup("--repo", self.repo, "--min-age", "0", "--yes")
        self.assertFalse(os.path.exists(path))

    def test_keeps_the_worktree_it_runs_in(self):
        path = self.worktree("here")
        out = self.cleanup("--yes", cwd=path)
        self.assertTrue(os.path.isdir(path))
        self.assertIn("current directory", out)

    def test_prunes_worktrees_whose_directory_is_gone(self):
        path = self.worktree("gone")
        os.rename(path, os.path.join(self.base, "moved-away"))
        out = self.cleanup("--repo", self.repo, "--yes")
        self.assertIn("directory missing", out)
        self.assertNotIn("gone", self.git(self.repo, "worktree", "list"))

    def test_base_option(self):
        path = self.worktree("feature", commit=True)
        self.git(self.repo, "branch", "release", "feature")
        self.cleanup("--repo", self.repo, "--base", "release", "--yes")
        self.assertFalse(os.path.exists(path))
        self.cleanup("--repo", self.repo, "--base", "nope", expect=1)
        self.cleanup("--repo", self.repo, "--min-age", "-1", expect=2)

    def test_keeps_worktree_with_ignored_files_that_are_not_caches(self):
        path = self.worktree("secrets")
        wr(os.path.join(path, ".env"), "SECRET")
        age(path)
        out = self.cleanup("--repo", self.repo, "--yes")
        self.assertTrue(os.path.isfile(os.path.join(path, ".env")), out)
        self.assertIn("ignored files that are not caches (.env)", out)

    def test_ignored_caches_and_symlinks_do_not_block_removal(self):
        path = self.worktree("cached")
        wr(os.path.join(path, "pkg", "__pycache__", "m.pyc"))
        wr(os.path.join(path, ".DS_Store"))
        wr(os.path.join(path, ".venv", "bin", "python"))
        target = os.path.join(self.base, "outside-target")
        wr(os.path.join(target, "keep-me"))
        os.symlink(target, os.path.join(path, "link"))
        age(path)
        out = self.cleanup("--repo", self.repo, "--yes")
        self.assertFalse(os.path.exists(path), out)
        self.assertTrue(os.path.isfile(os.path.join(target, "keep-me")))

    def test_keeps_worktree_that_contains_another_worktree(self):
        outer = self.worktree("outer")
        inner = os.path.join(outer, "wt", "inner")
        self.git(self.repo, "worktree", "add", "-q", "-b", "inner", inner)
        wr(os.path.join(inner, "work-in-progress"))
        age(outer)
        age(os.path.join(self.repo, ".git", "worktrees", "outer"))
        out = self.cleanup("--repo", self.repo, "--yes")
        self.assertTrue(os.path.isfile(os.path.join(inner, "work-in-progress")), out)
        self.assertIn("contains worktree", out)

    def test_keeps_worktree_whose_reflog_holds_unmerged_commits(self):
        path = self.worktree("reset", commit=True)
        self.git(path, "reset", "-q", "--hard", "main")
        age(path)
        age(os.path.join(self.repo, ".git", "worktrees", "reset"))
        out = self.cleanup("--repo", self.repo, "--yes")
        self.assertTrue(os.path.isdir(path), out)
        self.assertIn("reflog has commits not in main", out)

    def test_stale_origin_head_falls_back_to_main(self):
        self.git(self.repo, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/gone")
        path = self.worktree("merged")
        out = self.cleanup("--repo", self.repo, "--yes")
        self.assertIn("(base main)", out)
        self.assertFalse(os.path.exists(path))

    def test_a_bad_repo_does_not_stop_the_rest(self):
        pyc = os.path.join(self.repo, "__pycache__")
        wr(os.path.join(pyc, "m.pyc"))
        age(pyc)
        missing = os.path.join(self.base, "not-a-repo")
        os.makedirs(missing)
        out = self.cleanup("--repo", missing, "--caches", self.repo, "--yes", expect=1)
        self.assertIn("skipped", out)
        self.assertFalse(os.path.exists(pyc), out)

    def test_removes_only_ignored_idle_caches(self):
        pyc = os.path.join(self.repo, "src", "__pycache__")
        wr(os.path.join(pyc, "m.pyc"), "x" * 2000)
        nxt = os.path.join(self.repo, "app", ".next")
        wr(os.path.join(nxt, "build"))
        tracked = os.path.join(self.repo, "lib", ".turbo")
        wr(os.path.join(tracked, "keep"))
        self.git(self.repo, "add", "-f", "lib/.turbo/keep")
        self.git(self.repo, "commit", "-qm", "tracked cache")
        unignored = os.path.join(self.repo, "web", ".vite")
        wr(os.path.join(unignored, "c"))
        rust = os.path.join(self.repo, "crate")
        wr(os.path.join(rust, "Cargo.toml"))
        wr(os.path.join(rust, "target", "debug", "bin"))
        other_target = os.path.join(self.repo, "docs", "target")
        wr(os.path.join(other_target, "page"))
        deps = os.path.join(self.repo, "node_modules", "pkg", "__pycache__")
        wr(os.path.join(deps, "x.pyc"))
        outside = os.path.join(self.base, "plain", "__pycache__")
        wr(os.path.join(outside, "y.pyc"))
        for p in (pyc, nxt, tracked, unignored, os.path.join(rust, "target"), other_target, deps, outside):
            age(p)
        recent = os.path.join(self.repo, "new", "__pycache__")
        wr(os.path.join(recent, "z.pyc"))
        out = self.cleanup("--caches", self.repo, "--caches", os.path.join(self.base, "plain"), "--yes")
        for p in (pyc, nxt, os.path.join(rust, "target")):
            self.assertFalse(os.path.exists(p), f"{p} kept:\n{out}")
        for p in (tracked, unignored, other_target, deps, outside, recent):
            self.assertTrue(os.path.exists(p), f"{p} removed:\n{out}")
        self.assertIn("contains tracked files", out)
        self.assertIn("not ignored by git", out)
        self.assertIn("not in a git repository", out)
        self.assertNotIn("Worktrees of", out)

    def test_cache_dry_run_reports_sizes(self):
        pyc = os.path.join(self.repo, "__pycache__")
        wr(os.path.join(pyc, "m.pyc"), "x" * 3_000_000)
        age(pyc)
        out = self.cleanup("--caches", self.repo)
        self.assertIn("3.0 MB", out)
        self.assertTrue(os.path.isdir(pyc))


if __name__ == "__main__":
    unittest.main()
