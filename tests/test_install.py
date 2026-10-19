import json
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def rd(path):
    with open(path) as f:
        return f.read()


def wr(path, text):
    with open(path, "w") as f:
        f.write(text)


def load(path):
    return json.loads(rd(path))


def dump(data, path):
    wr(path, json.dumps(data))


DEFAULTS = load(os.path.join(ROOT, "claude", "settings.json"))
SKILLS = sorted(d for d in os.listdir(os.path.join(ROOT, "skills"))
                if os.path.isfile(os.path.join(ROOT, "skills", d, "SKILL.md")))


class InstallTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = os.path.realpath(self.tmp.name)
        self.home = os.path.join(base, "home")
        os.makedirs(self.home)
        self.repo = os.path.join(base, "repo")
        shutil.copytree(ROOT, self.repo, symlinks=True,
                        ignore=shutil.ignore_patterns(".git", "agent-memory*", "worktrees", "__pycache__"))
        self.claude = os.path.join(self.home, ".claude")
        self.settings = os.path.join(self.claude, "settings.json")

    def tearDown(self):
        self.tmp.cleanup()

    def run_install(self, *args, repo=None, expect=0):
        env = {k: v for k, v in os.environ.items() if k not in ("XDG_CONFIG_HOME", "NO_COLOR")}
        env["HOME"] = self.home
        result = subprocess.run(["bash", os.path.join(repo or self.repo, "install.sh"), *args],
                                env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, expect, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def read_settings(self):
        return load(self.settings)

    def write_settings(self, data):
        os.makedirs(self.claude, exist_ok=True)
        dump(data, self.settings)

    def link_target(self, path):
        return os.path.realpath(os.path.join(self.home, path))

    def snapshot(self):
        out = {}
        for dirpath, dirs, files in os.walk(self.home):
            for name in dirs + files:
                p = os.path.join(dirpath, name)
                if os.path.islink(p):
                    out[p] = "-> " + os.readlink(p)
                elif os.path.isfile(p):
                    with open(p, "rb") as f:
                        out[p] = f.read()
        return out

    def test_fresh_install_links_everything_and_is_idempotent(self):
        self.run_install()
        self.assertEqual(self.link_target(".claude/CLAUDE.md"), os.path.join(self.repo, "claude", "CLAUDE.md"))
        for tier in ("advisors", "workers", "explorers"):
            for name in os.listdir(os.path.join(self.repo, "agents", tier)):
                self.assertEqual(self.link_target(f".claude/agents/{name}"), os.path.join(self.repo, "agents", tier, name))
        self.assertEqual(sorted(os.listdir(os.path.join(self.claude, "hooks"))),
                         ["bash-guard.py", "session-start.py", "write-guard.py"])
        for name in os.listdir(os.path.join(self.claude, "hooks")):
            self.assertEqual(self.link_target(f".claude/hooks/{name}"), os.path.join(self.repo, "hooks", name))
        for name in SKILLS:
            self.assertEqual(self.link_target(f".claude/skills/{name}"), os.path.join(self.repo, "skills", name))
        self.assertEqual(self.link_target(".tmux.conf"), os.path.join(self.repo, "tmux", "tmux.conf"))
        self.assertEqual(self.read_settings(), DEFAULTS)
        before = self.snapshot()
        out = self.run_install()
        self.assertIn("Everything is in place.", out)
        self.assertEqual(self.snapshot(), before)

    def test_dry_run_changes_nothing(self):
        self.write_settings({"theme": "light"})
        before = self.snapshot()
        out = self.run_install("--dry-run")
        self.assertIn("Dry run", out)
        self.assertEqual(self.snapshot(), before)

    def test_user_values_survive_and_removals_stick(self):
        self.write_settings({"theme": "light", "permissions": {"allow": ["Bash(ls:*)"]}})
        self.run_install()
        s = self.read_settings()
        self.assertEqual(s["theme"], "light")
        self.assertIn("Bash(ls:*)", s["permissions"]["allow"])
        self.assertIn("Bash(make:*)", s["permissions"]["allow"])
        s["permissions"]["allow"].remove("Bash(make:*)")
        del s["tui"]
        s["model"] = "sonnet"
        self.write_settings(s)
        self.run_install()
        s = self.read_settings()
        self.assertNotIn("Bash(make:*)", s["permissions"]["allow"])
        self.assertNotIn("tui", s)
        self.assertEqual(s["model"], "sonnet")

    def test_changed_repo_defaults_replace_old_ones(self):
        self.run_install()
        defaults_path = os.path.join(self.repo, "claude", "settings.json")
        new = load(defaults_path)
        new["hooks"]["PreToolUse"][0]["hooks"][0]["command"] = "python3 \"$HOME/.claude/hooks/new-guard.py\""
        new["permissions"]["allow"].remove("Bash(cargo:*)")
        new["permissions"]["allow"].append("Bash(uv:*)")
        new["theme"] = "light"
        dump(new, defaults_path)
        self.run_install()
        s = self.read_settings()
        commands = [h["command"] for e in s["hooks"]["PreToolUse"] for h in e["hooks"]]
        self.assertEqual(commands, ["python3 \"$HOME/.claude/hooks/new-guard.py\""])
        self.assertNotIn("Bash(cargo:*)", s["permissions"]["allow"])
        self.assertIn("Bash(uv:*)", s["permissions"]["allow"])
        self.assertEqual(s["theme"], "light")

    def test_user_hook_entries_are_kept_when_defaults_change(self):
        self.run_install()
        s = self.read_settings()
        mine = {"matcher": "Write", "hooks": [{"type": "command", "command": "echo mine"}]}
        s["hooks"]["PreToolUse"].append(mine)
        self.write_settings(s)
        defaults_path = os.path.join(self.repo, "claude", "settings.json")
        new = load(defaults_path)
        new["hooks"]["PreToolUse"][0]["hooks"][0]["command"] = "python3 new.py"
        dump(new, defaults_path)
        self.run_install()
        entries = self.read_settings()["hooks"]["PreToolUse"]
        self.assertIn(mine, entries)
        commands = [h["command"] for e in entries for h in e["hooks"]]
        self.assertEqual(sorted(commands), ["echo mine", "python3 new.py"])

    def test_existing_files_need_confirmation_and_go_to_the_backup_dir(self):
        os.makedirs(os.path.join(self.claude, "skills", "tdd"))
        wr(os.path.join(self.claude, "skills", "tdd", "SKILL.md"), "old")
        wr(os.path.join(self.claude, "CLAUDE.md"), "mine")
        before = self.snapshot()
        out = self.run_install(expect=1)
        self.assertIn("need --yes", out)
        self.assertEqual(self.snapshot(), before)
        self.run_install("--yes")
        self.assertTrue(os.path.islink(os.path.join(self.claude, "skills", "tdd")))
        self.assertEqual(os.listdir(os.path.join(self.claude, "skills")).count("tdd"), 1)
        self.assertFalse([n for n in os.listdir(os.path.join(self.claude, "skills")) if ".bak" in n])
        backups = os.path.join(self.home, ".claude-config-backups")
        [stamp] = os.listdir(backups)
        self.assertEqual(rd(os.path.join(backups, stamp, ".claude", "CLAUDE.md")), "mine")
        self.assertTrue(os.path.isfile(os.path.join(backups, stamp, ".claude", "skills", "tdd", "SKILL.md")))

    def test_leaves_unrelated_skills_alone_and_removes_stale_repo_links(self):
        os.makedirs(os.path.join(self.claude, "skills", "my-own", ))
        os.makedirs(os.path.join(self.claude, "skills", "synced"))
        self.run_install()
        os.symlink(os.path.join(self.repo, "skills", "gone"), os.path.join(self.claude, "skills", "gone"))
        self.run_install()
        names = os.listdir(os.path.join(self.claude, "skills"))
        self.assertIn("my-own", names)
        self.assertIn("synced", names)
        self.assertNotIn("gone", names)

    def test_repo_reached_through_a_symlink_counts_as_the_same_repo(self):
        alias = os.path.join(os.path.dirname(self.repo), "alias")
        os.symlink(self.repo, alias)
        self.run_install(repo=alias)
        out = self.run_install()
        self.assertIn("Everything is in place.", out)

    def test_settings_mode_and_symlink_are_preserved(self):
        dotfiles = os.path.join(self.home, "dotfiles")
        os.makedirs(dotfiles)
        real = os.path.join(dotfiles, "settings.json")
        dump({"theme": "light"}, real)
        os.chmod(real, 0o640)
        os.makedirs(self.claude)
        os.symlink(real, self.settings)
        self.run_install()
        self.assertTrue(os.path.islink(self.settings))
        self.assertEqual(stat.S_IMODE(os.stat(real).st_mode), 0o640)
        self.assertEqual(load(real)["theme"], "light")

    def test_invalid_settings_abort_without_changes(self):
        os.makedirs(self.claude)
        wr(self.settings, "{not json")
        before = self.snapshot()
        self.run_install(expect=1)
        self.assertEqual(self.snapshot(), before)

    def test_tmux_existing_config_gets_a_source_line(self):
        conf = os.path.join(self.home, ".tmux.conf")
        wr(conf, "set -g prefix C-a")
        self.run_install("--yes")
        text = rd(conf)
        self.assertTrue(text.startswith("set -g prefix C-a\n"))
        self.assertIn(f'source-file "{self.repo}/tmux/tmux.conf"', text)
        self.assertIn("Everything is in place.", self.run_install())
        self.run_install("--uninstall", "--yes")
        self.assertEqual(rd(conf), "set -g prefix C-a\n")

    def test_links_into_another_checkout_are_relinked_not_edited(self):
        other = os.path.join(os.path.dirname(self.repo), "other-clone")
        shutil.copytree(self.repo, other, symlinks=True)
        self.run_install(repo=other)
        out = self.run_install()
        self.assertNotIn("confirm:", out)
        self.assertEqual(self.link_target(".tmux.conf"), os.path.join(self.repo, "tmux", "tmux.conf"))
        self.assertEqual(self.link_target(".claude/agents/fixer.md"), os.path.join(self.repo, "agents", "workers", "fixer.md"))
        self.assertNotIn("source-file", rd(os.path.join(other, "tmux", "tmux.conf")))

    def test_migrates_whole_directory_links_keeping_the_users_own_files(self):
        old = os.path.join(os.path.dirname(self.repo), "old-clone")
        shutil.copytree(self.repo, old, symlinks=True)
        git = ["git", "-C", old, "-c", "user.email=t@t", "-c", "user.name=t"]
        subprocess.run(["git", "init", "-q", old], check=True)
        subprocess.run(git + ["add", "-A"], check=True)
        subprocess.run(git + ["commit", "-q", "-m", "old"], check=True)
        wr(os.path.join(old, "hooks", "my-hook.sh"), "echo mine")
        os.makedirs(self.claude)
        for name in ("agents", "hooks"):
            os.symlink(os.path.join(old, name), os.path.join(self.claude, name))
        out = self.run_install()
        self.assertNotIn("confirm:", out)
        hooks = os.path.join(self.claude, "hooks")
        self.assertFalse(os.path.islink(hooks))
        self.assertEqual(rd(os.path.join(hooks, "my-hook.sh")), "echo mine")
        self.assertEqual(self.link_target(".claude/hooks/bash-guard.py"), os.path.join(self.repo, "hooks", "bash-guard.py"))
        self.assertNotIn("bash-guard.sh", os.listdir(hooks))
        self.assertFalse(os.path.islink(os.path.join(self.claude, "agents")))
        self.assertIn("Everything is in place.", self.run_install())

    def test_tmux_xdg_config_is_not_shadowed(self):
        xdg = os.path.join(self.home, ".config", "tmux", "tmux.conf")
        os.makedirs(os.path.dirname(xdg))
        wr(xdg, "set -g mouse off\n")
        self.run_install("--yes")
        self.assertFalse(os.path.lexists(os.path.join(self.home, ".tmux.conf")))
        self.assertIn("source-file", rd(xdg))

    def test_tmux_config_loads(self):
        if not shutil.which("tmux"):
            self.skipTest("tmux not installed")
        sock = os.path.join(os.path.realpath(self.tmp.name), "tmux.sock")
        conf = os.path.join(ROOT, "tmux", "tmux.conf")
        try:
            r = subprocess.run(["tmux", "-S", sock, "-f", conf, "new-session", "-d", ";",
                                "show-options", "-s", "terminal-features"],
                               capture_output=True, text=True, timeout=30)
            self.assertEqual(r.returncode, 0, r.stderr)
            subprocess.run(["tmux", "-S", sock, "source-file", conf], check=True, timeout=30)
            r = subprocess.run(["tmux", "-S", sock, "show-options", "-s", "terminal-features"],
                               capture_output=True, text=True, timeout=30)
            self.assertEqual(r.stdout.count("xterm*:extkeys"), 1, r.stdout)
        finally:
            subprocess.run(["tmux", "-S", sock, "kill-server"], capture_output=True)

    def test_uninstall_restores_backups_and_removes_defaults(self):
        open_claude = os.path.join(self.claude, "CLAUDE.md")
        os.makedirs(self.claude)
        wr(open_claude, "mine")
        self.write_settings({"theme": "light"})
        self.run_install("--yes")
        s = self.read_settings()
        s["permissions"]["allow"].append("Bash(ls:*)")
        self.write_settings(s)
        self.run_install("--uninstall", "--yes")
        self.assertEqual(rd(open_claude), "mine")
        self.assertEqual(os.listdir(os.path.join(self.claude, "agents")), [])
        self.assertEqual(os.listdir(os.path.join(self.claude, "hooks")), [])
        self.assertFalse([n for n in os.listdir(os.path.join(self.claude, "skills"))])
        self.assertEqual(self.read_settings(), {"theme": "light", "permissions": {"allow": ["Bash(ls:*)"]}})
        self.assertFalse(os.path.exists(os.path.join(self.claude, "claude-config-state.json")))


if __name__ == "__main__":
    unittest.main()
