#!/usr/bin/env python3
import argparse
import os
import shutil
import subprocess
import sys
import time

CACHE_NAMES = {
    ".next", ".nuxt", ".turbo", ".parcel-cache", ".svelte-kit", ".vite",
    "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
}
NO_DESCENT = {".git", "node_modules"}
REGENERABLE = {"node_modules", ".venv", ".DS_Store"}
MOUNT_PARENTS = ("/Volumes", "/mnt", "/media", "/run/media")
DAY = 86400


class RepoError(Exception):
    pass


def git(cwd, *args, stdin=None):
    return subprocess.run(["git", "--no-optional-locks", "-C", cwd, *args],
                          input=stdin, capture_output=True, text=True)


def real(path):
    return os.path.realpath(path)


def inside(path, root):
    return path == root or path.startswith(root.rstrip(os.sep) + os.sep)


def worktrees(repo):
    r = git(repo, "worktree", "list", "--porcelain", "-z")
    sep = "\0"
    if r.returncode and git(repo, "rev-parse", "--git-dir").returncode == 0:
        r = git(repo, "worktree", "list", "--porcelain")
        sep = "\n"
    if r.returncode:
        raise RepoError(f"not a git repository: {r.stderr.strip()}")
    items, cur = [], {}
    for line in r.stdout.split(sep) + [""]:
        if not line:
            if cur:
                items.append(cur)
            cur = {}
            continue
        key, _, value = line.partition(" ")
        cur[key] = value
    return items


def is_commit(repo, ref):
    return git(repo, "rev-parse", "--verify", "--quiet", ref + "^{commit}").returncode == 0


def base_ref(repo, given):
    if given:
        if not is_commit(repo, given):
            raise RepoError(f"--base {given} is not a commit")
        return given
    r = git(repo, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
    candidates = ([r.stdout.strip()] if r.returncode == 0 else []) + ["main", "master"]
    for ref in candidates:
        if is_commit(repo, ref):
            return ref
    raise RepoError("cannot find the default branch; pass --base")


def last_activity(path):
    stamps = [os.path.getmtime(path)]
    gitdir = git(path, "rev-parse", "--absolute-git-dir").stdout.strip()
    for name in ("HEAD", "index", os.path.join("logs", "HEAD")):
        p = os.path.join(gitdir, name)
        if gitdir and os.path.exists(p):
            stamps.append(os.path.getmtime(p))
    return max(stamps)


def disposable(root, rel):
    parts = rel.rstrip("/").split("/")
    if os.path.islink(os.path.join(root, *parts)):
        return True
    for i, name in enumerate(parts):
        if name in CACHE_NAMES or name in REGENERABLE:
            return True
        if name == "target" and os.path.isfile(os.path.join(root, *parts[:i], "Cargo.toml")):
            return True
    return False


def dirty_reason(path):
    r = git(path, "status", "--porcelain", "-z", "--ignored=matching", "--untracked-files=all")
    if r.returncode:
        return "git status failed"
    entries = r.stdout.split("\0")
    i = 0
    while i < len(entries):
        entry = entries[i]
        i += 1
        if not entry:
            continue
        code, rel = entry[:2], entry[3:]
        if code[0] in "RC":
            i += 1
        if code != "!!":
            return "uncommitted or untracked changes"
        if not disposable(path, rel):
            return f"ignored files that are not caches ({rel})"
    return None


def reflog_has_unmerged(path, base):
    shas = git(path, "log", "-g", "--format=%H", "HEAD").stdout.split()
    if not shas:
        return False
    r = git(path, "rev-list", "--stdin", "--max-count=1", stdin="\n".join(shas + ["^" + base]) + "\n")
    if r.returncode:
        raise RepoError(f"reflog check failed: {r.stderr.strip()}")
    return bool(r.stdout.strip())


def on_missing_volume(path):
    p = path
    while not os.path.exists(p):
        parent = os.path.dirname(p)
        if parent == p:
            return False
        p = parent
    return p in MOUNT_PARENTS or p.startswith("/run/media/")


def worktree_keep_reason(wt, others, base, min_age, here, now):
    path = real(wt["worktree"])
    if "bare" in wt:
        return "bare repository"
    if "locked" in wt:
        return "locked"
    if inside(here, path):
        return "current directory"
    nested = [o for o in others if o != path and inside(o, path)]
    if nested:
        return f"contains worktree {nested[0]}"
    idle = (now - last_activity(path)) / DAY
    if idle < min_age:
        return f"active {idle:.1f} days ago"
    reason = dirty_reason(path)
    if reason:
        return reason
    if git(path, "merge-base", "--is-ancestor", wt["HEAD"], base).returncode:
        return f"commits not in {base}"
    try:
        if reflog_has_unmerged(path, base):
            return f"its reflog has commits not in {base}"
    except RepoError as e:
        return str(e)
    return None


def plan_worktrees(repo, base, min_age, here, now):
    items = worktrees(repo)
    paths = [real(w["worktree"]) for w in items]
    unmounted = any("prunable" in wt and on_missing_volume(wt["worktree"]) for wt in items[1:])
    plan = []
    for wt in items[1:]:
        if "prunable" in wt:
            if on_missing_volume(wt["worktree"]):
                plan.append(("keep", wt, "on a volume that is not mounted"))
            elif unmounted:
                plan.append(("keep", wt, "directory missing, but pruning is blocked by a worktree on an unmounted volume"))
            else:
                plan.append(("prune", wt, "directory missing"))
            continue
        try:
            reason = worktree_keep_reason(wt, paths, base, min_age, here, now)
        except OSError as e:
            reason = f"unreadable: {e}"
        plan.append(("keep", wt, reason) if reason else ("remove", wt, "merged and clean"))
    return plan


def apply_worktrees(repo, plan, min_age):
    removed = failed = 0
    for action, wt, _ in plan:
        if action != "remove":
            continue
        r = git(repo, "worktree", "remove", wt["worktree"])
        if r.returncode:
            failed += 1
            print(f"  failed to remove {wt['worktree']}: {r.stderr.strip()}")
            continue
        removed += 1
        branch = wt.get("branch", "").replace("refs/heads/", "")
        if branch:
            b = git(repo, "branch", "-d", branch)
            if b.returncode:
                print(f"  kept branch {branch}: {b.stderr.strip()}")
    to_prune = [wt for action, wt, _ in plan if action == "prune"]
    if not to_prune:
        return removed, failed
    r = git(repo, "worktree", "prune", f"--expire={int(min_age * DAY)}.seconds.ago")
    if r.returncode:
        print(f"  failed to prune: {r.stderr.strip()}")
        return removed, failed + 1
    still = {w["worktree"] for w in worktrees(repo)}
    for wt in to_prune:
        if wt["worktree"] in still:
            print(f"  not pruned yet {wt['worktree']}: its record is newer than --min-age")
        else:
            removed += 1
    return removed, failed


def size_of(path):
    total = 0
    for dirpath, _, files in os.walk(path):
        for name in files:
            try:
                total += os.lstat(os.path.join(dirpath, name)).st_size
            except OSError:
                pass
    return total


def cache_keep_reason(path, min_age, now):
    parent = os.path.dirname(path)
    if git(parent, "rev-parse", "--show-toplevel").returncode:
        return "not in a git repository"
    if git(parent, "ls-files", "--", os.path.basename(path)).stdout.strip():
        return "contains tracked files"
    if git(parent, "check-ignore", "-q", os.path.basename(path) + "/").returncode:
        return "not ignored by git"
    idle = (now - os.path.getmtime(path)) / DAY
    if idle < min_age:
        return f"active {idle:.1f} days ago"
    return None


def is_cache(dirpath, name):
    if name in CACHE_NAMES:
        return True
    return name == "target" and os.path.isfile(os.path.join(dirpath, "Cargo.toml"))


def plan_caches(roots, min_age, now):
    plan = []
    for root in roots:
        for dirpath, dirnames, _ in os.walk(root):
            dirnames.sort()
            for name in list(dirnames):
                path = os.path.join(dirpath, name)
                if os.path.islink(path) or name in NO_DESCENT:
                    dirnames.remove(name)
                elif is_cache(dirpath, name):
                    dirnames.remove(name)
                    reason = cache_keep_reason(path, min_age, now)
                    plan.append(("keep", path, reason) if reason else ("remove", path, size_of(path)))
    return plan


def mb(n):
    return f"{n / 1e6:.1f} MB"


def run(args):
    now = time.time()
    here = real(os.getcwd())
    removed = failed = 0
    freed = 0
    for repo in args.repo:
        repo = real(repo)
        try:
            base = base_ref(repo, args.base)
            plan = plan_worktrees(repo, base, args.min_age, here, now)
        except RepoError as e:
            failed += 1
            print(f"Worktrees of {repo}: skipped, {e}")
            continue
        print(f"Worktrees of {repo} (base {base}):")
        if not plan:
            print("  none besides the main checkout")
        for action, wt, why in plan:
            branch = wt.get("branch", "").replace("refs/heads/", "")
            label = wt["worktree"] + (f" [{branch}]" if branch else "")
            print(f"  {action:<7}{label}: {why}")
        if args.yes:
            r, f = apply_worktrees(repo, plan, args.min_age)
            removed += r
            failed += f
    if args.caches:
        plan = plan_caches([real(c) for c in args.caches], args.min_age, now)
        print("Build caches:")
        if not plan:
            print("  none found")
        for action, path, detail in plan:
            if action == "keep":
                print(f"  keep   {path}: {detail}")
                continue
            print(f"  remove {path}: {mb(detail)}")
            if args.yes:
                try:
                    shutil.rmtree(path)
                    removed += 1
                    freed += detail
                except OSError as e:
                    failed += 1
                    print(f"         failed: {e}")
    if not args.yes:
        print("Dry run: nothing was changed. Pass --yes to apply.")
    else:
        print(f"Removed {removed}, freed {mb(freed)} of caches, {failed} failed.")
    return 1 if failed else 0


def main(argv=None):
    p = argparse.ArgumentParser(description="Remove merged, clean, idle git worktrees and git-ignored build caches. Dry run unless --yes.")
    p.add_argument("--repo", action="append", help="repository whose worktrees to clean (repeatable, default: current directory)")
    p.add_argument("--caches", action="append", default=[], help="directory to search for build caches (repeatable)")
    p.add_argument("--base", help="branch a worktree must be merged into (default: origin/HEAD, then main, then master)")
    p.add_argument("--min-age", type=float, default=7, help="days a worktree or cache must be idle (default: 7)")
    p.add_argument("--yes", action="store_true", help="apply the plan")
    args = p.parse_args(argv)
    if args.min_age < 0:
        p.error("--min-age cannot be negative")
    if shutil.which("git") is None:
        p.error("git is not on PATH")
    if args.repo is None:
        in_repo = git(os.getcwd(), "rev-parse", "--git-dir").returncode == 0
        args.repo = [os.getcwd()] if in_repo or not args.caches else []
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
