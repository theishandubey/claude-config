#!/usr/bin/env python3
import filecmp
import json
import os
import shutil
import subprocess
import sys

PLAYBOOK = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "claude", "orchestrator.md")
MEMORY_DIRS = (".claude/agent-memory", ".claude/agent-memory-local")


def git(cwd, *args):
    try:
        out = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, timeout=5)
        return out.stdout.strip() if out.returncode == 0 else ""
    except Exception:
        return ""


def merge_tree(src, dst):
    for dirpath, _, files in os.walk(src):
        rel = os.path.relpath(dirpath, src)
        os.makedirs(os.path.join(dst, rel), exist_ok=True)
        for name in files:
            s, d = os.path.join(dirpath, name), os.path.join(dst, rel, name)
            if not os.path.exists(d):
                shutil.copy2(s, d)
            elif not filecmp.cmp(s, d, shallow=False) and os.path.getmtime(s) > os.path.getmtime(d):
                shutil.copy2(d, d + ".before-worktree-merge")
                shutil.copy2(s, d)


def share_worktree_memory(cwd):
    top = git(cwd, "rev-parse", "--show-toplevel")
    common = git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not top or not common or os.path.basename(common) != ".git":
        return
    main = os.path.dirname(common)
    if os.path.realpath(main) == os.path.realpath(top):
        return
    for rel in MEMORY_DIRS:
        if git(top, "ls-files", rel):
            continue
        here, there = os.path.join(top, rel), os.path.join(main, rel)
        if os.path.islink(here):
            continue
        os.makedirs(there, exist_ok=True)
        if os.path.isdir(here):
            merge_tree(here, there)
            shutil.rmtree(here)
        os.makedirs(os.path.dirname(here), exist_ok=True)
        os.symlink(there, here)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}
    try:
        share_worktree_memory(data.get("cwd") or os.getcwd())
    except Exception as e:
        print(f"session-start: could not link worktree agent memory: {e}", file=sys.stderr)
    try:
        with open(PLAYBOOK, encoding="utf-8") as f:
            sys.stdout.write(f.read())
    except OSError as e:
        print(f"session-start: orchestrator playbook missing: {e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
