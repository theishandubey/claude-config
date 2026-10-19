#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys

SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "mksh", "fish"}
DB_CLIENTS = {
    "psql", "mysql", "mariadb", "sqlite3", "duckdb", "sqlcmd", "cockroach",
    "clickhouse-client", "clickhouse", "mongosh", "mongo", "redis-cli", "valkey-cli",
}
DB_TEXT = [
    (re.compile(r"\bdrop\s+(database|schema)\b", re.I), "drops a database or schema"),
    (re.compile(r"\bflush(all|db)\b", re.I), "flushes a Redis database"),
    (re.compile(r"\.dropDatabase\s*\("), "drops a MongoDB database"),
]
PROTECTED_BRANCHES = {"main", "master"}
HOME_CHILDREN_DOT = {".ssh", ".gnupg", ".claude", ".config", ".aws", ".kube", ".local"}
MOUNT_PARENTS = {"/Volumes", "/mnt", "/media"}
RAW_DISK = re.compile(r"^/dev/(r?disk\d|sd[a-z]|hd[a-z]|vd[a-z]|xvd[a-z]|nvme\d|mmcblk\d)")
GLOB_ALL = {"*", ".*", "{*,.*}", "{.*,*}"}
UNKNOWN = "\x00"


class Blocked(Exception):
    pass


def tokenize(text):
    commands, nested = [], []
    words, heredocs, pending_heredocs = [], [], []
    word, in_word = [], False
    i, n = 0, len(text)

    def end_word():
        nonlocal word, in_word
        if in_word:
            words.append("".join(word))
        word, in_word = [], False

    def end_command():
        nonlocal words, heredocs
        end_word()
        if words or heredocs:
            commands.append((words, heredocs))
        words, heredocs = [], []

    while i < n:
        c = text[i]
        if c == "\\" and i + 1 < n:
            if text[i + 1] != "\n":
                word.append(text[i + 1])
                in_word = True
            i += 2
            continue
        if c == "'":
            j = text.find("'", i + 1)
            j = n if j < 0 else j
            word.append(text[i + 1:j])
            in_word = True
            i = j + 1
            continue
        if c == "$" and i + 1 < n and text[i + 1] == "'":
            j, buf = i + 2, []
            while j < n and text[j] != "'":
                if text[j] == "\\" and j + 1 < n:
                    buf.append(text[j:j + 2])
                    j += 2
                else:
                    buf.append(text[j])
                    j += 1
            word.append(decode_ansi_c("".join(buf)))
            in_word = True
            i = j + 1
            continue
        if c == '"' or (c == "$" and i + 1 < n and text[i + 1] == '"'):
            j = i + (2 if c == "$" else 1)
            while j < n and text[j] != '"':
                if text[j] == "\\" and j + 1 < n:
                    if text[j + 1] in '"\\$`':
                        word.append(text[j + 1])
                    else:
                        word.append(text[j:j + 2])
                    j += 2
                    continue
                if text.startswith("$(", j):
                    body, j = take_parens(text, j + 2)
                    nested.append(body)
                    word.append(UNKNOWN)
                    continue
                if text[j] == "`":
                    k = text.find("`", j + 1)
                    k = n if k < 0 else k
                    nested.append(text[j + 1:k])
                    word.append(UNKNOWN)
                    j = k + 1
                    continue
                word.append(text[j])
                j += 1
            in_word = True
            i = j + 1
            continue
        if text.startswith("$(", i):
            body, i = take_parens(text, i + 2)
            nested.append(body)
            word.append(UNKNOWN)
            in_word = True
            continue
        if c == "`":
            k = text.find("`", i + 1)
            k = n if k < 0 else k
            nested.append(text[i + 1:k])
            word.append(UNKNOWN)
            in_word = True
            i = k + 1
            continue
        if c == "#" and not in_word:
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "\n":
            end_command()
            i += 1
            for delim, strip_tabs in pending_heredocs:
                body, i = take_heredoc(text, i, delim, strip_tabs)
                (commands[-1][1] if commands else heredocs).append(body)
            pending_heredocs = []
            continue
        if c in " \t":
            end_word()
            i += 1
            continue
        if c in ";&|()":
            end_command()
            i += 1
            continue
        if c in "<>":
            end_word()
            if text.startswith("<<<", i):
                i += 3
                continue
            if text.startswith("<<", i):
                i += 2
                strip_tabs = i < n and text[i] == "-"
                if strip_tabs:
                    i += 1
                while i < n and text[i] in " \t":
                    i += 1
                m = re.match(r"""(['"]?)([^\s;&|<>()'"]+)\1""", text[i:])
                if m:
                    pending_heredocs.append((m.group(2), strip_tabs))
                    i += m.end()
                continue
            op = c
            i += 1
            while i < n and text[i] in ">&|":
                op += text[i]
                i += 1
            words.append(op)
            continue
        word.append(c)
        in_word = True
        i += 1
    end_command()
    return commands, nested


def decode_ansi_c(s):
    simple = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", "'": "'", '"': '"', "a": "\a", "e": "\x1b"}

    def repl(m):
        e = m.group(1)
        if e in simple:
            return simple[e]
        if e[0] == "x":
            return chr(int(e[1:], 16))
        if e[0].isdigit():
            return chr(int(e, 8))
        return "\\" + e

    return re.sub(r"\\(x[0-9a-fA-F]{1,2}|[0-7]{1,3}|.)", repl, s)


def take_parens(text, i):
    depth, j = 1, i
    while j < len(text):
        ch = text[j]
        if ch == "\\":
            j += 2
            continue
        if ch == "'":
            k = text.find("'", j + 1)
            j = len(text) if k < 0 else k + 1
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return text[i:j], j + 1
        j += 1
    return text[i:], len(text)


def take_heredoc(text, i, delim, strip_tabs):
    lines, n = [], len(text)
    while i < n:
        j = text.find("\n", i)
        j = n if j < 0 else j
        line = text[i:j]
        i = j + 1
        if (line.lstrip("\t") if strip_tabs else line) == delim:
            break
        lines.append(line)
    return "\n".join(lines), i


def unwrap(words):
    with_values = {
        "sudo": {"-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U", "-T"},
        "doas": {"-u", "-C"},
        "env": {"-u", "-C", "-S", "--unset", "--chdir", "--split-string"},
        "nice": {"-n", "--adjustment"},
        "timeout": {"-s", "-k", "--signal", "--kill-after"},
        "stdbuf": {"-i", "-o", "-e"},
        "ionice": {"-c", "-n", "-t", "-p"},
        "caffeinate": {"-t", "-w"},
        "xargs": {"-I", "-n", "-P", "-L", "-s", "-d", "-E", "-a", "-i", "-l"},
        "exec": {"-a"},
        "time": set(),
        "nohup": set(),
        "command": set(),
        "builtin": set(),
        "busybox": set(),
        "unbuffer": set(),
        "chronic": set(),
    }
    words = list(words)
    while words:
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]):
            words.pop(0)
            continue
        name = os.path.basename(words[0])
        if name not in with_values:
            break
        if name == "env":
            for k, w in enumerate(words):
                if w in ("-S", "--split-string") and k + 1 < len(words):
                    return unwrap(words[1:k] + words[k + 1].split() + words[k + 2:])
        if name == "command" and len(words) > 1 and words[1] in ("-v", "-V"):
            return []
        words.pop(0)
        takes = with_values[name]
        while words and words[0].startswith("-") and words[0] != "-":
            opt = words.pop(0)
            if opt == "--":
                break
            if opt in takes and words:
                words.pop(0)
        if name == "timeout" and words:
            words.pop(0)
    return words


def options_and_args(argv):
    opts, args, k = [], [], 0
    while k < len(argv):
        a = argv[k]
        if a == "--":
            args.extend(argv[k + 1:])
            break
        (opts if a.startswith("-") and a != "-" else args).append(a)
        k += 1
    return opts, args


def has_short(opts, letters):
    return any(o.startswith("-") and not o.startswith("--") and set(o[1:]) & set(letters) for o in opts)


def has_long(opts, full, minimum=3):
    for o in opts:
        if o.startswith("--"):
            name = o[2:].split("=", 1)[0]
            if len(name) >= minimum and full.startswith(name):
                return True
    return False


class Context:
    def __init__(self, cwd, home):
        self.cwd = cwd
        self.home = home
        self.repo_root = git_root(cwd)


def git_root(path, *extra):
    try:
        out = subprocess.run(
            ["git", *extra, "rev-parse", "--show-toplevel"], cwd=path,
            capture_output=True, text=True, timeout=5,
        )
        return out.stdout.strip() or None if out.returncode == 0 else None
    except Exception:
        return None


def current_branch(path):
    try:
        out = subprocess.run(
            ["git", "symbolic-ref", "--short", "-q", "HEAD"], cwd=path,
            capture_output=True, text=True, timeout=5,
        )
        return out.stdout.strip()
    except Exception:
        return ""


def expand(word, ctx, cwd):
    if word == "~" or word.startswith("~/"):
        word = ctx.home + word[1:]
    word = re.sub(r"\$\{HOME\}|\$HOME\b", lambda m: ctx.home, word)
    word = re.sub(r"\$\{PWD\}|\$PWD\b", lambda m: cwd or UNKNOWN, word)
    word = re.sub(r"\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*|\$[0-9@*#?$!-]", UNKNOWN, word)
    return word


def catastrophic_path(raw, ctx, cwd):
    word = expand(raw, ctx, cwd)
    if UNKNOWN in word:
        rest = word.replace(UNKNOWN, "")
        if rest.rstrip("/") in ("", "/*", "/.*", "*") or set(rest) <= {"/", "*", "."}:
            return f"'{raw}' could expand to the filesystem root"
        if not word.startswith(UNKNOWN):
            word = word.split(UNKNOWN, 1)[0]
            if "/" not in word:
                return None
            word = word.rsplit("/", 1)[0] or "/"
        else:
            return None
    parts = word.split("/")
    for k, part in enumerate(parts):
        if part in GLOB_ALL:
            word = "/".join(parts[:k]) or ("/" if word.startswith("/") else ".")
            break
        if re.search(r"[*?\[]", part):
            return None
    if not os.path.isabs(word):
        if cwd is None:
            if word in (".", "..", "./", "../") or word.startswith(".."):
                return f"'{raw}' is relative to an unknown directory"
            return None
        word = os.path.join(cwd, word)
    candidates = {os.path.normpath(word)}
    try:
        candidates.add(os.path.realpath(word))
    except Exception:
        pass
    for t in candidates:
        reason = protected(t, ctx, cwd)
        if reason:
            return f"'{raw}' {reason}"
    return None


def is_ancestor_or_self(a, b):
    a, b = a.rstrip("/") or "/", b.rstrip("/") or "/"
    return b == a or b.startswith(a if a == "/" else a + "/")


def temp_dirs():
    dirs = {"/tmp", "/private/tmp", "/var/folders", "/private/var/folders"}
    if os.environ.get("TMPDIR"):
        dirs.add(os.path.normpath(os.environ["TMPDIR"]))
    return dirs


def protected(t, ctx, cwd):
    if t == "/":
        return "is the filesystem root"
    parent = os.path.dirname(t)
    if parent == "/":
        return "is a top-level system directory"
    if parent in MOUNT_PARENTS:
        return "is a mounted volume"
    home = os.path.normpath(ctx.home)
    for anchor, label in ((home, "your home directory"), (ctx.repo_root, "the project"), (cwd, "the working directory")):
        if anchor and is_ancestor_or_self(t, os.path.normpath(anchor)):
            return f"contains {label}"
    if parent == home:
        base = os.path.basename(t)
        if not base.startswith(".") or base in HOME_CHILDREN_DOT:
            return "is a top-level folder in your home directory"
    if os.path.basename(t) == ".git" and ctx.repo_root and is_ancestor_or_self(ctx.repo_root, t):
        return "is the project's git history"
    if not any(is_ancestor_or_self(d, t) for d in temp_dirs()):
        if os.path.basename(t) == ".git" or os.path.exists(os.path.join(t, ".git")):
            return "is a git repository"
    return None


def check_rm(argv, ctx, cwd):
    opts, args = options_and_args(argv[1:])
    if has_long(opts, "no-preserve-root"):
        raise Blocked("rm --no-preserve-root")
    if not (has_short(opts, "rR") or has_long(opts, "recursive")):
        return
    for a in args:
        reason = catastrophic_path(a, ctx, cwd)
        if reason:
            raise Blocked(f"recursive rm of {reason}")


def check_find(argv, ctx, cwd):
    rest = argv[1:]
    while rest and rest[0] in ("-H", "-L", "-P", "-E", "-X", "-s", "-x", "-d"):
        rest = rest[1:]
    starts = []
    while rest and not rest[0].startswith("-") and rest[0] not in ("(", "!", ","):
        starts.append(rest.pop(0))
    filters = {
        "-name", "-iname", "-path", "-ipath", "-wholename", "-regex", "-iregex", "-newer",
        "-mtime", "-mmin", "-atime", "-amin", "-ctime", "-cmin", "-size", "-empty", "-user", "-group",
        "-perm", "-links", "-inum",
    }
    for k, w in enumerate(rest):
        if w in filters and not (w in ("-name", "-iname", "-path") and k + 1 < len(rest) and rest[k + 1] in GLOB_ALL):
            return
    deletes = "-delete" in rest
    for k, w in enumerate(rest):
        if w in ("-exec", "-execdir", "-ok", "-okdir") and k + 1 < len(rest):
            if os.path.basename(rest[k + 1]) in ("rm", "shred", "unlink"):
                deletes = True
    if not deletes:
        return
    for s in starts or ["."]:
        reason = catastrophic_path(s, ctx, cwd)
        if reason:
            raise Blocked(f"find deleting under {reason}")


def check_chmod_chown(argv, ctx, cwd):
    opts, args = options_and_args(argv[1:])
    if not (has_short(opts, "R") or has_long(opts, "recursive")):
        return
    for a in args[1:]:
        reason = catastrophic_path(a, ctx, cwd)
        if reason and any(s in reason for s in ("filesystem root", "top-level system", "home directory", "mounted volume")):
            raise Blocked(f"recursive {os.path.basename(argv[0])} of {reason}")


def check_disk(argv):
    name = os.path.basename(argv[0])
    if name.startswith("mkfs") or name in ("wipefs", "newfs") or name.startswith("newfs_"):
        raise Blocked(f"{name} formats a disk")
    if name == "dd":
        for a in argv[1:]:
            if a.startswith("of=") and RAW_DISK.match(a[3:]):
                raise Blocked("dd writes to a raw disk")
    if name == "shred" and any(RAW_DISK.match(a) for a in argv[1:]):
        raise Blocked("shred wipes a raw disk")
    if name == "diskutil":
        verbs = {"erasedisk", "erasevolume", "reformat", "partitiondisk", "zerodisk", "randomdisk", "secureerase", "deletecontainer", "deletevolume"}
        if any(a.lower() in verbs for a in argv[1:]):
            raise Blocked("diskutil erases a disk or volume")
        if len(argv) > 2 and argv[1].lower() == "apfs" and argv[2].lower() in verbs:
            raise Blocked("diskutil erases an APFS container or volume")


def check_redirects(words):
    for k, w in enumerate(words):
        if w and w[0] == ">" and k + 1 < len(words) and RAW_DISK.match(words[k + 1]):
            raise Blocked("redirect writes to a raw disk")


def positional(argv, value_opts=()):
    out, k = [], 0
    while k < len(argv):
        a = argv[k]
        if a.startswith("-"):
            if a in value_opts:
                k += 1
        else:
            out.append(a)
        k += 1
    return out


def check_db_and_infra(argv):
    name = os.path.basename(argv[0])
    pos = [p.lower() for p in positional(argv[1:])]
    joined = " ".join(pos)
    if name == "dropdb":
        raise Blocked("dropdb drops a database")
    if name in ("mysqladmin", "mariadb-admin") and "drop" in pos:
        raise Blocked("mysqladmin drop drops a database")
    if name == "prisma" or (name in ("npx", "pnpx", "bunx") and pos[:1] == ["prisma"]) or (name in ("pnpm", "yarn") and pos[:2] == ["exec", "prisma"]):
        if "migrate reset" in joined or "--force-reset" in argv:
            raise Blocked("prisma resets the database")
    if name in ("rails", "rake") or argv[0].endswith("bin/rails"):
        if any(p in ("db:drop", "db:reset", "db:purge", "db:drop:all") for p in pos):
            raise Blocked("rails drops or resets the database")
    if name in ("python", "python3") and len(pos) >= 2 and pos[0].endswith("manage.py") and pos[1] in ("flush", "reset_db"):
        raise Blocked("django flushes the database")
    if name == "supabase" and pos[:2] == ["db", "reset"] and "--linked" in argv:
        raise Blocked("supabase resets the linked remote database")
    if name == "heroku" and pos[:1] in (["pg:reset"], ["apps:destroy"]):
        raise Blocked(f"heroku {pos[0]}")
    if name in ("terraform", "tofu", "terragrunt"):
        if pos[:1] == ["destroy"] or (pos[:1] == ["apply"] and "-destroy" in argv):
            raise Blocked(f"{name} destroys infrastructure")
    if name == "pulumi" and pos[:1] == ["destroy"]:
        raise Blocked("pulumi destroys a stack")
    if name == "kubectl" and pos[:1] == ["delete"] and len(pos) > 1 and pos[1] in ("namespace", "namespaces", "ns"):
        raise Blocked("kubectl deletes a namespace")
    if name == "aws":
        if pos[:2] == ["s3", "rb"] or (pos[:2] == ["s3", "rm"] and "--recursive" in argv):
            raise Blocked("aws s3 deletes a bucket or its contents")
        if len(pos) > 1 and pos[0] in ("rds", "dynamodb") and pos[1].startswith("delete-"):
            raise Blocked(f"aws {pos[0]} {pos[1]}")
    if name == "gcloud":
        if pos[:2] == ["projects", "delete"] or pos[:3] == ["sql", "instances", "delete"]:
            raise Blocked("gcloud deletes a project or database")
    if name == "gsutil" and (pos[:1] == ["rb"] or (pos[:1] == ["rm"] and has_short(argv[1:], "r"))):
        raise Blocked("gsutil deletes a bucket or its contents")
    if name == "az" and pos[:2] == ["group", "delete"]:
        raise Blocked("az deletes a resource group")
    if name in ("fly", "flyctl") and (pos[:2] == ["apps", "destroy"] or pos[:1] == ["destroy"]):
        raise Blocked("fly destroys an app")
    if name == "gh" and pos[:2] == ["repo", "delete"]:
        raise Blocked("gh deletes a repository")


def check_git(argv, ctx, cwd):
    k, gitdir = 1, cwd
    while k < len(argv) and argv[k].startswith("-"):
        if argv[k] == "-C" and k + 1 < len(argv):
            target = expand(argv[k + 1], ctx, cwd)
            gitdir = None if UNKNOWN in target else os.path.join(cwd or "/", target)
            k += 2
        elif argv[k] in ("-c", "--git-dir", "--work-tree", "--namespace") and k + 1 < len(argv):
            k += 2
        else:
            k += 1
    if k >= len(argv) or argv[k] != "push":
        return
    opts, args = options_and_args(argv[k + 1:])
    args = [a for a in args if not a.startswith("--")]
    force = has_short(opts, "f") or has_long(opts, "force", 4) or has_long(opts, "force-with-lease", 7) or has_long(opts, "mirror")
    delete = has_short(opts, "d") or has_long(opts, "delete")
    refspecs = args[1:]
    if any(r.startswith("+") for r in refspecs):
        force = True
    if not (force or delete or any(r.startswith(":") for r in refspecs)):
        return
    if has_long(opts, "mirror") or has_long(opts, "all"):
        raise Blocked("force push of all branches")
    targets = []
    for r in refspecs:
        r = r.lstrip("+")
        dst = r.split(":", 1)[1] if ":" in r else r
        if r.startswith(":"):
            delete = True
        targets.append(dst.replace("refs/heads/", ""))
    if not targets:
        branch = current_branch(gitdir) if gitdir else ""
        targets = [branch] if branch else ["main"]
    for t in targets:
        if t in PROTECTED_BRANCHES or t == "HEAD" and current_branch(gitdir or cwd) in PROTECTED_BRANCHES:
            raise Blocked(f"{'deleting' if delete and not force else 'force push to'} protected branch {t}")


def check_command(words, heredocs, ctx, cwd, depth):
    check_redirects(words)
    words = [w for k, w in enumerate(words) if not (w[:1] in "<>" or (k and words[k - 1][:1] in "<>"))]
    argv = unwrap(words)
    if not argv:
        return cwd
    name = os.path.basename(argv[0])
    if name == "cd":
        target = argv[1] if len(argv) > 1 else "~"
        expanded = expand(target, ctx, cwd)
        if UNKNOWN in expanded or target == "-":
            return None
        return os.path.normpath(os.path.join(cwd or "/", expanded)) if (cwd or os.path.isabs(expanded)) else None
    if name in SHELLS:
        script = None
        for k, a in enumerate(argv[1:], 1):
            if a.startswith("-") and not a.startswith("--") and "c" in a[1:]:
                script = argv[k + 1] if k + 1 < len(argv) else ""
                break
            if not a.startswith("-"):
                break
        if script is not None:
            check_script(script, ctx, cwd, depth + 1)
        elif len(argv) == 1 or all(a.startswith("-") for a in argv[1:]):
            for body in heredocs:
                check_script(body, ctx, cwd, depth + 1)
        return cwd
    if name == "eval":
        check_script(" ".join(argv[1:]), ctx, cwd, depth + 1)
        return cwd
    if name == "watch":
        rest = argv[1:]
        while rest and rest[0].startswith("-"):
            opt = rest.pop(0)
            if opt in ("-n", "-d", "--interval") and rest:
                rest.pop(0)
        check_script(" ".join(rest), ctx, cwd, depth + 1)
        return cwd
    if name in DB_CLIENTS:
        text = " ".join(argv[1:]) + "\n" + "\n".join(heredocs)
        for pattern, label in DB_TEXT:
            if pattern.search(text):
                raise Blocked(f"{name} {label}")
    if name in ("rm", "unlink"):
        check_rm(argv, ctx, cwd)
    elif name == "find":
        check_find(argv, ctx, cwd)
    elif name in ("chmod", "chown", "chgrp"):
        check_chmod_chown(argv, ctx, cwd)
    elif name == "git":
        check_git(argv, ctx, cwd)
    else:
        check_disk(argv)
        check_db_and_infra(argv)
    return cwd


def check_db_text(text, commands):
    names = set()
    for words, _ in commands:
        argv = unwrap([w for w in words if w[:1] not in "<>"])
        if argv:
            names.add(os.path.basename(argv[0]))
    if names & DB_CLIENTS:
        for pattern, label in DB_TEXT:
            if pattern.search(text):
                raise Blocked(f"SQL sent to a database client {label}")


def check_script(text, ctx, cwd, depth=0):
    if depth > 8:
        raise Blocked("command nests shells too deeply to inspect")
    commands, nested = tokenize(text)
    check_db_text(text, commands)
    for body in nested:
        check_script(body, ctx, cwd, depth + 1)
    for words, heredocs in commands:
        cwd = check_command(words, heredocs, ctx, cwd, depth)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    if data.get("tool_name") != "Bash":
        return 0
    command = (data.get("tool_input") or {}).get("command") or ""
    cwd = data.get("cwd") or os.getcwd()
    ctx = Context(cwd, os.environ.get("HOME") or os.path.expanduser("~"))
    try:
        check_script(command, ctx, cwd)
    except Blocked as e:
        print(
            f"bash-guard blocked this command: {e}. "
            "It is irreversible. If it is really intended, ask the user to run it themselves.",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
