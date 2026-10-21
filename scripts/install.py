#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

REPO = os.path.realpath(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HOME = os.path.realpath(os.environ.get("HOME") or os.path.expanduser("~"))
CLAUDE = os.path.join(HOME, ".claude")
STATE = os.path.join(CLAUDE, "dotclaude-state.json")
BACKUPS = os.path.join(HOME, ".dotclaude-backups")
TMUX_MARK = "# dotclaude"
MANAGED_DIRS = ("agents", "hooks", "skills")
MISSING = object()
COLOR = sys.stdout.isatty() and not os.environ.get("NO_COLOR")


def say(kind, text):
    colors = {"ok": "32", "change": "36", "confirm": "33", "warn": "31"}
    label = f"\033[{colors[kind]}m{kind}:\033[0m" if COLOR else f"{kind}:"
    print(f"  {label} {text}")


def short(path):
    return "~" + path[len(HOME):] if path.startswith(HOME + "/") else path


def into_repo(path):
    if not os.path.islink(path):
        return False
    target = os.path.realpath(path)
    return target == REPO or target.startswith(REPO + "/")


def from_any_checkout(path):
    if not os.path.islink(path):
        return False
    directory = os.path.dirname(os.path.realpath(path))
    while directory != os.path.dirname(directory):
        if all(os.path.exists(os.path.join(directory, m)) for m in ("install.sh", "claude/CLAUDE.md", "agents")):
            return True
        directory = os.path.dirname(directory)
    return False


def canon(value):
    return "<missing>" if value is MISSING else json.dumps(value, sort_keys=True)


def merge3(base, ours, theirs):
    if canon(ours) == canon(base):
        return theirs
    if canon(theirs) == canon(base):
        return ours
    if theirs is MISSING and isinstance(ours, (dict, list)) and type(base) is type(ours):
        merged = merge3(base, ours, type(ours)())
        return merged if merged else MISSING
    if isinstance(ours, dict) and isinstance(theirs, dict):
        base = base if isinstance(base, dict) else {}
        out = {}
        for key in list(ours) + [k for k in theirs if k not in ours]:
            value = merge3(base.get(key, MISSING), ours.get(key, MISSING), theirs.get(key, MISSING))
            if value is not MISSING:
                out[key] = value
        return out
    if isinstance(ours, list) and isinstance(theirs, list):
        base_set = {canon(x) for x in base} if isinstance(base, list) else set()
        theirs_set = {canon(x) for x in theirs}
        ours_set = {canon(x) for x in ours}
        kept = [x for x in ours if canon(x) in theirs_set or canon(x) not in base_set]
        added = [x for x in theirs if canon(x) not in ours_set and canon(x) not in base_set]
        return kept + added
    return ours


def load_json(path, default):
    if not os.path.lexists(path):
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def write_json(path, data):
    path = os.path.realpath(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    mode = os.stat(path).st_mode & 0o7777 if os.path.exists(path) else 0o644
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".dotclaude-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.chmod(tmp, mode)
    os.replace(tmp, path)


class Plan:
    def __init__(self, stamp):
        self.steps = []
        self.stamp = stamp

    def ok(self, text):
        say("ok", text)

    def add(self, text, action, confirm=False):
        say("confirm" if confirm else "change", text)
        self.steps.append((text, action, confirm))

    @property
    def needs_confirm(self):
        return any(c for _, _, c in self.steps)

    def backup(self, path):
        dest = os.path.join(BACKUPS, self.stamp, os.path.relpath(path, HOME))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.move(path, dest)
        return dest


def desired_links():
    links = {os.path.join(CLAUDE, "CLAUDE.md"): os.path.join(REPO, "claude", "CLAUDE.md")}
    agents = os.path.join(REPO, "agents")
    for tier in sorted(os.listdir(agents)):
        for name in sorted(os.listdir(os.path.join(agents, tier))):
            if name.endswith(".md"):
                links[os.path.join(CLAUDE, "agents", name)] = os.path.join(agents, tier, name)
    for name in sorted(os.listdir(os.path.join(REPO, "hooks"))):
        if name.endswith(".py"):
            links[os.path.join(CLAUDE, "hooks", name)] = os.path.join(REPO, "hooks", name)
    skills = os.path.join(REPO, "skills")
    for name in sorted(os.listdir(skills)):
        if os.path.isfile(os.path.join(skills, name, "SKILL.md")):
            links[os.path.join(CLAUDE, "skills", name)] = os.path.join(skills, name)
    return links


def own_files(directory):
    names = [n for n in sorted(os.listdir(directory)) if not n.startswith(".") and n != "__pycache__"]
    try:
        out = subprocess.run(["git", "ls-files", "-z"], cwd=directory, capture_output=True, text=True, timeout=10)
    except OSError:
        return names
    if out.returncode != 0:
        return names
    tracked = {p.split("/", 1)[0] for p in out.stdout.split("\0") if p}
    return [n for n in names if n not in tracked]


def plan_managed_dir(plan, name):
    path = os.path.join(CLAUDE, name)
    if not os.path.islink(path):
        return False
    if into_repo(path) or from_any_checkout(path):
        old = os.path.realpath(path)
        keep = own_files(old) if os.path.isdir(old) else []

        def run():
            os.unlink(path)
            os.makedirs(path)
            for n in keep:
                src, dst = os.path.join(old, n), os.path.join(path, n)
                if os.path.isdir(src) and not os.path.islink(src):
                    shutil.copytree(src, dst, symlinks=True)
                else:
                    shutil.copy2(src, dst, follow_symlinks=False)

        extra = f", copying your own files from it: {', '.join(keep)}" if keep else ""
        plan.add(f"replace the link {short(path)} with a directory of links{extra}", run)
    else:
        def run():
            say("change", f"backed up {short(path)} to {short(plan.backup(path))}")
            os.makedirs(path)

        plan.add(f"back up the link {short(path)} and replace it with a directory of links", run, confirm=True)
    return True


def plan_link(plan, target, source, fresh=False):
    if not fresh and os.path.islink(target) and os.path.realpath(target) == os.path.realpath(source):
        plan.ok(short(target))
        return

    def make(backup=False):
        def run():
            if backup:
                say("change", f"backed up {short(target)} to {short(plan.backup(target))}")
            elif os.path.lexists(target):
                os.unlink(target)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            os.symlink(source, target)
        return run

    if fresh or not os.path.lexists(target):
        plan.add(f"link {short(target)} -> {short(source)}", make())
    elif into_repo(target) or from_any_checkout(target) or not os.path.exists(target):
        plan.add(f"relink {short(target)} -> {short(source)}", make())
    else:
        plan.add(f"back up {short(target)} and link it to {short(source)}", make(backup=True), confirm=True)


def stale_links(desired, include_dirs=False):
    found = []
    for directory in [CLAUDE] + [os.path.join(CLAUDE, d) for d in MANAGED_DIRS]:
        if os.path.islink(directory) or not os.path.isdir(directory):
            continue
        for name in sorted(os.listdir(directory)):
            path = os.path.join(directory, name)
            if directory == CLAUDE and name in MANAGED_DIRS and not include_dirs:
                continue
            if into_repo(path) and path not in desired:
                found.append(path)
    return found


def plan_settings(plan, uninstall=False):
    path = os.path.join(CLAUDE, "settings.json")
    user = load_json(path, {})
    state = load_json(STATE, None)
    base = state.get("settings", {}) if state is not None else {}
    defaults = {} if uninstall else load_json(os.path.join(REPO, "claude", "settings.json"), {})
    merged = merge3(base, user, defaults)
    if merged is MISSING:
        merged = {}
    changed = canon(merged) != canon(user)
    state_changed = uninstall and state is not None or not uninstall and (state is None or canon(base) != canon(defaults))

    def run():
        if changed:
            write_json(path, merged)
        if uninstall:
            if os.path.exists(STATE):
                os.unlink(STATE)
        else:
            write_json(STATE, {"repo": REPO, "settings": defaults})

    if changed:
        keys = sorted({k for k in set(merged) | set(user) if canon(merged.get(k)) != canon(user.get(k))})
        verb = "remove this repo's defaults from" if uninstall else "merge defaults into"
        plan.add(f"{verb} {short(path)} ({', '.join(keys)})", run)
    elif state_changed:
        plan.add("record the applied settings defaults", run)
    else:
        plan.ok(short(path))


def tmux_paths():
    xdg = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
    return os.path.join(HOME, ".tmux.conf"), os.path.join(xdg, "tmux", "tmux.conf")


def source_line():
    return f'source-file "{os.path.join(REPO, "tmux", "tmux.conf")}" {TMUX_MARK}\n'


def plan_tmux(plan, uninstall=False):
    dotfile, xdg = tmux_paths()
    source = os.path.join(REPO, "tmux", "tmux.conf")
    if uninstall:
        if into_repo(dotfile):
            plan.add(f"remove link {short(dotfile)}", lambda: os.unlink(dotfile))
        for conf in (dotfile, xdg):
            if os.path.isfile(conf) and not into_repo(conf):
                lines = open(conf, encoding="utf-8").readlines()
                if any(l.rstrip().endswith(TMUX_MARK) for l in lines):
                    def strip(conf=conf, lines=lines):
                        with open(os.path.realpath(conf), "w", encoding="utf-8") as f:
                            f.writelines(l for l in lines if not l.rstrip().endswith(TMUX_MARK))
                    plan.add(f"remove the dotclaude line from {short(conf)}", strip)
        return
    if into_repo(dotfile) or from_any_checkout(dotfile):
        plan_link(plan, dotfile, source)
        return
    active = dotfile if os.path.lexists(dotfile) else xdg if os.path.lexists(xdg) else None
    if active is None:
        plan_link(plan, dotfile, source)
        return
    text = open(active, encoding="utf-8").read()
    if source_line().strip() in text:
        plan.ok(f"{short(active)} sources tmux/tmux.conf")
        return
    lines = [l for l in text.splitlines(keepends=True) if not l.rstrip().endswith(TMUX_MARK)]

    def append():
        with open(os.path.realpath(active), "w", encoding="utf-8") as f:
            f.writelines(lines)
            if lines and not lines[-1].endswith("\n"):
                f.write("\n")
            f.write(source_line())

    plan.add(f"add a source-file line for tmux/tmux.conf to {short(active)}", append, confirm=True)


def newest_backup(path):
    rel = os.path.relpath(path, HOME)
    if not os.path.isdir(BACKUPS):
        return None
    for stamp in sorted(os.listdir(BACKUPS), reverse=True):
        candidate = os.path.join(BACKUPS, stamp, rel)
        if os.path.lexists(candidate):
            return candidate
    return None


def plan_unlink(plan, path, restore):
    backup = newest_backup(path) if restore else None

    def run():
        os.unlink(path)
        if backup:
            shutil.move(backup, path)

    if backup:
        plan.add(f"remove link {short(path)} and restore {short(backup)}", run, confirm=True)
    else:
        plan.add(f"remove link {short(path)}", run)


def confirm(plan, assume_yes):
    if not plan.needs_confirm or assume_yes:
        return True
    if not sys.stdin.isatty():
        print("Changes marked 'confirm' need --yes when not run from a terminal; nothing was changed.", file=sys.stderr)
        return False
    answer = input("Apply the changes marked 'confirm'? [y/N] ").strip().lower()
    return answer in ("y", "yes")


def main(argv):
    parser = argparse.ArgumentParser(prog="install.sh", description="Link this Claude Code config into ~/.claude.")
    parser.add_argument("--dry-run", action="store_true", help="print the plan and change nothing")
    parser.add_argument("-y", "--yes", action="store_true", help="apply changes that need confirmation without asking")
    parser.add_argument("--uninstall", action="store_true", help="remove the links and this repo's settings defaults")
    args = parser.parse_args(argv)

    plan = Plan(time.strftime("%Y%m%d-%H%M%S"))
    print(f"dotclaude {'uninstall' if args.uninstall else 'install'} from {short(REPO)}")
    try:
        if args.uninstall:
            for path in stale_links({}, include_dirs=True):
                plan_unlink(plan, path, restore=True)
        else:
            desired = desired_links()
            migrating = {os.path.join(CLAUDE, d) for d in MANAGED_DIRS if plan_managed_dir(plan, d)}
            for target, source in desired.items():
                plan_link(plan, target, source, fresh=os.path.dirname(target) in migrating)
            for path in stale_links(desired):
                plan_unlink(plan, path, restore=False)
        plan_settings(plan, uninstall=args.uninstall)
        plan_tmux(plan, uninstall=args.uninstall)
    except (OSError, ValueError) as e:
        print(f"error: {e}; nothing was changed.", file=sys.stderr)
        return 1

    if not plan.steps:
        print("Everything is in place.")
        return 0
    if args.dry_run:
        print("Dry run: nothing was changed.")
        return 0
    if not confirm(plan, args.yes):
        return 1
    for text, action, _ in plan.steps:
        action()
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
