#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys

MEMORY_DIRS = (".claude/agent-memory", ".claude/agent-memory-local")
PLAN_DIRS = ("plans", "advisor-plans")
PLAN_FILE = re.compile(r"^(\d{3}-[a-z0-9][a-z0-9-]*\.md|README\.md)$")


def git(cwd, *args):
    try:
        out = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, timeout=5)
        return out.stdout.strip() if out.returncode == 0 else ""
    except Exception:
        return ""


def project_roots(cwd):
    roots = {cwd}
    if os.environ.get("CLAUDE_PROJECT_DIR"):
        roots.add(os.environ["CLAUDE_PROJECT_DIR"])
    top = git(cwd, "rev-parse", "--show-toplevel")
    if top:
        roots.add(top)
    common = git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if common and os.path.basename(common) == ".git":
        roots.add(os.path.dirname(common))
    return {os.path.realpath(r) for r in roots if r}


def inside(path, directory):
    return path.startswith(directory.rstrip("/") + "/")


def allowed(target, cwd, allow_plans):
    home = os.path.realpath(os.path.expanduser("~"))
    if inside(target, os.path.join(home, ".claude", "agent-memory")):
        return True
    for root in project_roots(cwd):
        if any(inside(target, os.path.join(root, d)) for d in MEMORY_DIRS):
            return True
        if allow_plans and os.path.dirname(target) in {os.path.join(root, d) for d in PLAN_DIRS}:
            if PLAN_FILE.match(os.path.basename(target)):
                return True
    return False


def main():
    allow_plans = "--allow-plans" in sys.argv[1:]
    try:
        data = json.load(sys.stdin)
        tool_input = data.get("tool_input") or {}
        raw = tool_input.get("file_path") or tool_input.get("notebook_path")
        cwd = data.get("cwd") or os.getcwd()
        if not raw:
            return 0
        target = os.path.realpath(os.path.join(cwd, os.path.expanduser(raw)))
        if allowed(target, cwd, allow_plans):
            return 0
    except Exception as e:
        print(f"write-guard could not check this write ({e}); blocked.", file=sys.stderr)
        return 2
    scope = "agent memory and plans/NNN-<slug>.md or plans/README.md" if allow_plans else "agent memory"
    print(
        f"write-guard blocked a write to {raw}: advisors may only write {scope}. "
        "Put the content in your answer instead, with its target path, for a worker to write.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
