import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUARD = os.path.join(ROOT, "hooks", "bash-guard.py")

BLOCKED = [
    "rm -rf /",
    "rm -rf /*",
    "rm -fr /",
    "rm -r -f /",
    "rm -R /usr",
    "rm --recursive --force /etc",
    "rm --recur --forc /",
    "rm -rf --no-preserve-root /",
    "rm --no-preserve-root -rf /",
    "sudo rm -rf /",
    "sudo -u root rm -rf /",
    "env FOO=1 rm -rf /",
    "nohup rm -rf / &",
    "time rm -rf /",
    "timeout 10 rm -rf /",
    "stdbuf -o0 rm -rf /",
    "busybox rm -rf /",
    "xargs rm -rf /",
    "/bin/rm -rf /",
    "command rm -rf /",
    "$'rm' -rf /",
    "rm $'-rf' /",
    '$"rm" -rf /',
    "'rm' '-rf' '/'",
    'r""m -rf /',
    "rm -rf ~",
    "rm -rf ~/",
    "rm -rf ~/*",
    'rm -rf "$HOME"',
    "rm -rf ${HOME}/",
    "rm -rf ~/Documents",
    "rm -rf ~/.ssh",
    "rm -rf .",
    "rm -rf ./",
    "rm -rf *",
    "rm -rf ./*",
    "rm -rf .*",
    "rm -rf $PWD",
    'rm -rf "$DIR/"',
    'rm -rf "$DIR"/*',
    "rm -rf ${UNSET}/",
    "rm -rf ./$X",
    "rm -rf .git",
    "rm -rf {repo}",
    "rm -rf {repo}/",
    "rm -rf {parent}",
    "cd src && rm -rf ..",
    "cd / && rm -rf *",
    "cd ~ && rm -rf *",
    "rm -rf /Volumes/Data",
    "rm -rf /tmp",
    "true; rm -rf /",
    "false || rm -rf /",
    "echo hi | rm -rf /",
    "(rm -rf /)",
    "echo $(rm -rf /)",
    "echo `rm -rf /`",
    'bash -c "rm -rf /"',
    "sh -c 'rm -rf ~'",
    "zsh -lc 'rm -rf /'",
    "ksh -c 'rm -rf /'",
    "fish -c 'rm -rf /'",
    "bash -c \"bash -c 'rm -rf /'\"",
    "eval rm -rf /",
    "eval 'rm -rf /'",
    "watch -n 5 rm -rf /",
    "bash <<EOF\nrm -rf /\nEOF",
    "find / -delete",
    "find ~ -name '*' -delete",
    "find . -exec rm -rf {} +",
    "find / -type f -exec rm {} \\;",
    "chmod -R 000 /",
    "chown -R nobody ~",
    "mkfs.ext4 /dev/sda1",
    "mkfs -t ext4 /dev/sdb",
    "wipefs -a /dev/sda",
    "dd if=/dev/zero of=/dev/sda bs=1M",
    "dd if=/dev/zero of=/dev/disk2",
    "dd if=/dev/zero of=/dev/rdisk2",
    "diskutil eraseDisk APFS Empty disk2",
    "diskutil apfs deleteContainer disk3",
    "cat /dev/zero > /dev/sda",
    "shred /dev/nvme0n1",
    "psql -c 'DROP DATABASE prod'",
    "psql -c 'drop   schema public cascade'",
    "mysql -e 'DROP DATABASE app'",
    "echo 'DROP DATABASE app;' | psql",
    "psql <<SQL\nDROP DATABASE app;\nSQL",
    "dropdb app",
    "mysqladmin -u root drop app",
    "redis-cli FLUSHALL",
    "redis-cli -n 2 flushdb",
    "mongosh --eval 'db.dropDatabase()'",
    "npx prisma migrate reset --force",
    "prisma db push --force-reset",
    "rails db:drop",
    "bin/rails db:reset",
    "rake db:purge",
    "python manage.py flush --no-input",
    "supabase db reset --linked",
    "heroku pg:reset DATABASE_URL",
    "terraform destroy",
    "terraform apply -destroy -auto-approve",
    "tofu destroy",
    "pulumi destroy --yes",
    "kubectl delete namespace prod",
    "kubectl delete ns prod",
    "aws s3 rb s3://bucket --force",
    "aws s3 rm s3://bucket --recursive",
    "aws rds delete-db-instance --db-instance-identifier prod",
    "aws dynamodb delete-table --table-name t",
    "gcloud projects delete my-project",
    "gcloud sql instances delete prod",
    "gsutil rm -r gs://bucket",
    "az group delete -n rg",
    "fly apps destroy app",
    "gh repo delete owner/repo --yes",
    "git push --force origin main",
    "git push -f origin master",
    "git push origin +main",
    "git push --force-with-lease origin main",
    "git push --forc origin main",
    "git push origin main --force",
    "git push origin --delete main",
    "git push origin :main",
    "git push --mirror",
    "git push --all --force",
    "git -C {repo} push -f origin main",
    "git push origin HEAD:main --force",
    "git push origin feature:refs/heads/main -f",
]

ALLOWED = [
    "ls -la",
    "rm file.txt",
    "rm -f build.log",
    "rm -rf build",
    "rm -rf node_modules dist .next",
    "rm -rf ./build",
    "rm -rf build/*",
    "rm -rf src/*.js",
    "rm -rf /tmp/scratch-dir",
    "rm -rf ~/.cache/pip",
    "rm -rf ~/.npm/_cacache",
    "rm -rf ~/.cache",
    'rm -rf "$HOME/.cache/$X"',
    'rm -rf "$OUT/build"',
    'rm -rf "$TMPDIR/foo"',
    "rm -r -- -weird-name",
    "rm -rf /tmp/clone-of-repo",
    "find . -name '*.pyc' -delete",
    "find build -type f -delete",
    "find . -name node_modules -prune",
    "chmod -R u+w build",
    "chmod 755 /",
    "git status",
    "git push",
    "git push origin feature",
    "git push --force origin feature",
    "git push -f origin feature-main",
    "git push --force-with-lease origin my-branch",
    "git push origin --delete old-feature",
    "git reset --hard HEAD~1",
    "git checkout -- .",
    "git clean -fdx",
    "git branch -D old",
    "psql -c 'select 1'",
    "psql -c 'DROP TABLE tmp_users'",
    "grep -rn 'DROP DATABASE' migrations/",
    "rg 'flushall' src",
    "echo 'rm -rf /'",
    "printf '%s\\n' 'rm -rf /'",
    "cat > notes.md <<EOF\nrm -rf /\nEOF",
    "redis-cli get key",
    "dd if=/dev/zero of=disk.img bs=1M count=10",
    "terraform plan",
    "terraform apply",
    "kubectl delete pod web-1",
    "aws s3 rm s3://bucket/key",
    "rails db:migrate",
    "npx prisma migrate dev",
    "supabase db reset",
    "diskutil list",
    "command -v rm",
    "echo done # rm -rf /",
    "python3 -c 'print(1)'",
    "make clean",
]


class BashGuardTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        base = os.path.realpath(cls.tmp.name)
        cls.home = os.path.join(base, "home")
        cls.parent = os.path.join(cls.home, "code")
        cls.repo = os.path.join(cls.parent, "project")
        os.makedirs(os.path.join(cls.repo, "src"))
        os.makedirs(os.path.join(cls.home, ".cache"))
        subprocess.run(["git", "init", "-q", "-b", "feature", cls.repo], check=True)
        cls.main_repo = os.path.join(base, "on-main")
        subprocess.run(["git", "init", "-q", "-b", "main", cls.main_repo], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def run_guard(self, command, cwd=None):
        command = command.replace("{repo}", self.repo).replace("{parent}", self.parent)
        payload = {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": cwd or self.repo}
        env = dict(os.environ, HOME=self.home)
        env.pop("TMPDIR", None)
        result = subprocess.run(
            [sys.executable, GUARD], input=json.dumps(payload), capture_output=True,
            text=True, env=env, cwd=cwd or self.repo, timeout=30,
        )
        return result

    def test_blocks_catastrophic_commands(self):
        for command in BLOCKED:
            with self.subTest(command=command):
                result = self.run_guard(command)
                self.assertEqual(result.returncode, 2, f"not blocked: {command!r}")
                self.assertIn("bash-guard blocked", result.stderr)

    def test_allows_ordinary_commands(self):
        for command in ALLOWED:
            with self.subTest(command=command):
                result = self.run_guard(command)
                self.assertEqual(result.returncode, 0, f"blocked: {command!r}: {result.stderr}")

    def test_plain_force_push_blocked_only_on_protected_branch(self):
        self.assertEqual(self.run_guard("git push --force", cwd=self.main_repo).returncode, 2)
        self.assertEqual(self.run_guard("git push --force", cwd=self.repo).returncode, 0)

    def test_ignores_other_tools_and_bad_input(self):
        env = dict(os.environ, HOME=self.home)
        for stdin in ("not json", json.dumps({"tool_name": "Write", "tool_input": {"file_path": "/"}})):
            result = subprocess.run([sys.executable, GUARD], input=stdin, capture_output=True, text=True, env=env)
            self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
