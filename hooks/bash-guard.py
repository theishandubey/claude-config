#
# Command checker behind hooks/bash-guard.sh; see that file for the full contract.
#
# Reads the PreToolUse JSON payload on stdin and exits 2 with a one-line reason on
# stderr when .tool_input.command contains a destructive command, otherwise 0.
# Anything it cannot parse (bad JSON, no command, unbalanced quotes) exits 0.
#
# An accident guard, not a security boundary: it does not follow `eval`, variables,
# encoded strings or scripts written to disk.

import json
import os
import re
import shlex
import sys

MAX_DEPTH = 5
SEPARATORS = ";&|\n"
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
RESERVED = {"!", "{", "if", "then", "elif", "else", "while", "until", "do"}
SHELLS = {"bash", "sh", "zsh", "dash"}
REDIRECT = re.compile(r"^(\d*|&)(<<<|<>|>>|>\||<|>)(.*)$", re.DOTALL)
SHELL_VALUE_LONG = {"--rcfile", "--init-file"}
SUDO_VALUES = "ughpCrtUDRT"
ENV_VALUES = "uCS"
SUDO_LONG = {"--user", "--group", "--host", "--prompt", "--chdir", "--close-from", "--role", "--type", "--other-user", "--command-timeout"}
ENV_LONG = {"--unset", "--chdir", "--split-string"}
XARGS_VALUES = "nILPdEsa"
XARGS_LONG = {"--arg-file", "--delimiter", "--max-args", "--max-procs", "--max-lines", "--max-chars", "--process-slot-var"}
TIMEOUT_LONG = {"--signal", "--kill-after"}
TIME_LONG = {"--format", "--output"}
GIT_VALUES = {
    "clean": ("e", {"--exclude"}),
    "restore": ("s", {"--source"}),
    "push": ("o", {"--push-option", "--repo", "--receive-pack", "--exec"}),
}
GIT_VALUE_FLAGS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env", "--super-prefix"}
FIND_EXEC = {"-exec", "-execdir", "-ok", "-okdir"}


class ParseError(Exception):
    pass


class Words(list):
    def __init__(self):
        super().__init__()
        self.heredocs = []


class Heredoc:
    def __init__(self, delimiter, strip_tabs):
        self.delimiter = delimiter
        self.strip_tabs = strip_tabs
        self.body = None


class Scanner:
    def __init__(self, text):
        self.text = text
        self.n = len(text)
        self.segments = []
        self.heredocs = []

    def scan(self, i, closer):
        text, n = self.text, self.n
        words = Words()
        word = None

        def end_word():
            nonlocal word
            if word is not None:
                words.append(word)
                word = None

        def end_segment():
            nonlocal words
            end_word()
            if words:
                self.segments.append(words)
            words = Words()

        while i < n:
            c = text[i]
            if closer and c == closer:
                end_segment()
                return i + 1
            if c == "\n":
                end_segment()
                i = self.skip_heredocs(i + 1)
                continue
            if c in " \t":
                end_word()
                i += 1
                continue
            if c == "#" and word is None:
                while i < n and text[i] != "\n":
                    i += 1
                continue
            if c == "\\":
                if i + 1 < n:
                    if text[i + 1] != "\n":
                        word = (word or "") + text[i + 1]
                    i += 2
                else:
                    i += 1
                continue
            if c == "'":
                end = text.find("'", i + 1)
                if end < 0:
                    raise ParseError("unterminated single quote")
                word = (word or "") + text[i + 1:end]
                i = end + 1
                continue
            if c == '"':
                word, i = self.scan_double(i + 1, word or "")
                continue
            if c == "`":
                word = word or ""
                i = self.scan(i + 1, "`")
                continue
            if c == "$" and text.startswith("$((", i):
                end = self.skip_arith(i + 1)
                if end >= 0:
                    word = word or ""
                    i = end
                    continue
            if c == "$" and text.startswith("$(", i):
                word = word or ""
                i = self.scan(i + 2, ")")
                continue
            if c == "(" and text.startswith("((", i) and word is None and all(w in RESERVED for w in words):
                end = self.skip_arith(i)
                if end >= 0:
                    i = end
                    continue
            if c == "<" and text.startswith("<<<", i):
                word = (word or "") + "<<<"
                i += 3
                continue
            if c == "<" and text.startswith("<<", i):
                i, heredoc = self.read_heredoc_delimiter(i + 2)
                words.heredocs.append(heredoc)
                continue
            if c == "&" and ((i > 0 and text[i - 1] in "<>") or text.startswith("&>", i)):
                word = (word or "") + c
                i += 1
                continue
            if c in SEPARATORS or c == "(" or c == ")":
                end_segment()
                i += 1
                continue
            word = (word or "") + c
            i += 1
        if closer:
            raise ParseError("unterminated substitution")
        end_segment()
        return i

    def scan_double(self, i, word):
        text, n = self.text, self.n
        while i < n:
            c = text[i]
            if c == '"':
                return word, i + 1
            if c == "\\" and i + 1 < n:
                nxt = text[i + 1]
                word += nxt if nxt in '"\\$`' else c + nxt
                i += 2
                continue
            if c == "`":
                i = self.scan(i + 1, "`")
                continue
            if c == "$" and text.startswith("$((", i):
                end = self.skip_arith(i + 1)
                if end >= 0:
                    i = end
                    continue
            if c == "$" and text.startswith("$(", i):
                i = self.scan(i + 2, ")")
                continue
            word += c
            i += 1
        raise ParseError("unterminated double quote")

    def skip_arith(self, i):
        text = self.text
        depth = 0
        for j in range(i, self.n):
            if text[j] == "(":
                depth += 1
            elif text[j] == ")":
                depth -= 1
                if depth == 0:
                    if text[j - 1] == ")" and j - 1 > i + 1 and "<<" in text[i:j]:
                        return j + 1
                    return -1
        return -1

    def read_heredoc_delimiter(self, i):
        text, n = self.text, self.n
        strip_tabs = i < n and text[i] == "-"
        if strip_tabs:
            i += 1
        while i < n and text[i] in " \t":
            i += 1
        delimiter = ""
        while i < n and text[i] not in " \t\n;&|()<>":
            c = text[i]
            if c in "'\"":
                end = text.find(c, i + 1)
                if end < 0:
                    raise ParseError("unterminated heredoc delimiter")
                delimiter += text[i + 1:end]
                i = end + 1
            elif c == "\\" and i + 1 < n:
                delimiter += text[i + 1]
                i += 2
            else:
                delimiter += c
                i += 1
        heredoc = Heredoc(delimiter, strip_tabs)
        self.heredocs.append(heredoc)
        return i, heredoc

    def skip_heredocs(self, i):
        text, n = self.text, self.n
        pending, self.heredocs = self.heredocs, []
        for heredoc in pending:
            lines = []
            while i < n:
                end = text.find("\n", i)
                line = text[i:] if end < 0 else text[i:end]
                i = n if end < 0 else end + 1
                if (line.lstrip("\t") if heredoc.strip_tabs else line) == heredoc.delimiter:
                    break
                lines.append(line)
            heredoc.body = "\n".join(lines)
        return i


def strip_wrappers(words):
    while words:
        word = words[0]
        name = os.path.basename(word)
        if ASSIGNMENT.match(word) or word in RESERVED or name == "nohup":
            words = words[1:]
        elif name == "time":
            words = skip_options(words[1:], "fo", TIME_LONG)
        elif name == "exec":
            words = skip_options(words[1:], "a")
        elif name == "command":
            words = words[1:]
            while words and words[0] in ("-p", "--"):
                words = words[1:]
        elif name == "sudo":
            words = skip_options(words[1:], SUDO_VALUES, SUDO_LONG)
        elif name == "doas":
            words = skip_options(words[1:], "uC")
        elif name == "env":
            words = skip_options(words[1:], ENV_VALUES, ENV_LONG, assignments=True)
        elif name == "xargs":
            words = skip_options(words[1:], XARGS_VALUES, XARGS_LONG)
        elif name == "timeout":
            words = skip_options(words[1:], "sk", TIMEOUT_LONG)[1:]
        elif name == "nice":
            words = skip_options(words[1:], "n", {"--adjustment"})
        elif name == "ionice":
            words = skip_options(words[1:], "cnp", {"--class", "--classdata", "--pid"})
        else:
            break
    return words


def skip_options(words, short_values="", long_values=(), assignments=False):
    i = 0
    while i < len(words):
        word = words[i]
        if word == "--":
            return words[i + 1:]
        if assignments and ASSIGNMENT.match(word):
            i += 1
        elif word.startswith("--"):
            i += 2 if word in long_values else 1
        elif word.startswith("-"):
            i += 1
            for pos, ch in enumerate(word[1:], 1):
                if ch in short_values:
                    if pos == len(word) - 1:
                        i += 1
                    break
        else:
            break
    return words[i:]


def split_options(args, short_values, long_values):
    kept, flags = [], ""
    i = 0
    while i < len(args):
        arg = args[i]
        i += 1
        if arg == "--":
            kept.extend(args[i - 1:])
            break
        if arg.startswith("--"):
            if arg.split("=", 1)[0] in long_values:
                i += "=" not in arg
            else:
                kept.append(arg)
        elif arg == "-h":
            kept.append(arg)
        elif arg.startswith("-") and len(arg) > 1:
            for pos, ch in enumerate(arg[1:], 1):
                if ch in short_values:
                    if pos == len(arg) - 1:
                        i += 1
                    break
                flags += ch
        else:
            kept.append(arg)
    return kept, flags


def check_rm(args):
    recursive = force = False
    for arg in args:
        if arg == "--":
            break
        if arg in ("--recursive",):
            recursive = True
        elif arg == "--force":
            force = True
        elif arg.startswith("-") and not arg.startswith("--"):
            recursive = recursive or "r" in arg or "R" in arg
            force = force or "f" in arg
    if recursive and force:
        return "rm with recursive and force flags"
    return None


def split_git(args):
    i = 0
    while i < len(args) and args[i].startswith("-"):
        flag = args[i]
        i += 2 if flag in GIT_VALUE_FLAGS else 1
    if i >= len(args):
        return None, []
    return args[i], args[i + 1:]


def check_git(args):
    sub, rest = split_git(args)
    short_values, long_values = GIT_VALUES.get(sub, ("", ()))
    rest, flags = split_options(rest, short_values, long_values)
    head = rest[:rest.index("--")] if "--" in rest else rest
    if "-h" in head or "--help" in head:
        return None
    if sub == "push":
        if "--dry-run" in head or "n" in flags:
            return None
        for arg in rest:
            if arg in ("--force", "--force-if-includes") or arg.startswith("--force-with-lease"):
                return "git push with a force flag"
            if arg == "--mirror":
                return "git push --mirror"
            if arg.startswith("+"):
                return "git push with a + refspec"
        if "f" in flags:
            return "git push with a force flag"
    elif sub == "reset":
        if "--hard" in head:
            return "git reset --hard"
    elif sub == "clean":
        force = "--force" in rest or "f" in flags
        dry = "--dry-run" in head or "n" in flags
        if force and not dry:
            return "git clean with force"
    elif sub == "checkout":
        if "--force" in rest or "f" in flags:
            return "git checkout with force"
        if any(arg == "--pathspec-from-file" or arg.startswith("--pathspec-from-file=") for arg in head):
            return "git checkout that discards working-tree changes"
        if "." in rest or ("--" in rest and rest.index("--") < len(rest) - 1):
            return "git checkout that discards working-tree changes"
    elif sub == "switch":
        if "--force" in rest or "--discard-changes" in rest or "f" in flags:
            return "git switch that discards working-tree changes"
    elif sub == "restore":
        staged = "--staged" in rest or "S" in flags
        worktree = "--worktree" in rest or "W" in flags
        if not staged or worktree:
            return "git restore that discards working-tree changes"
    return None


def check_find(args, depth):
    if "-delete" in args:
        return "find -delete"
    for i, arg in enumerate(args):
        if arg not in FIND_EXEC:
            continue
        command = Words()
        for word in args[i + 1:]:
            if word in (";", "+"):
                break
            command.append(word)
        stripped = strip_wrappers(command)
        if stripped and os.path.basename(stripped[0]) == "rm":
            return "find -exec rm"
        reason = check_segment(command, depth + 1)
        if reason:
            return reason
    return None


def shell_scripts(args, heredocs):
    has_c = has_s = False
    options = True
    positional = []
    here = []
    i = 0
    while i < len(args):
        arg = args[i]
        if options and arg == "--":
            options = False
            i += 1
        elif options and arg in SHELL_VALUE_LONG:
            i += 2
        elif options and arg.startswith("--"):
            i += 1
        elif options and len(arg) > 1 and arg[0] in "-+":
            i += 1
            for ch in arg[1:]:
                if ch in "oO":
                    i += 1
                elif ch == "c" and arg[0] == "-":
                    has_c = True
                elif ch == "s" and arg[0] == "-":
                    has_s = True
        elif not has_c and REDIRECT.match(arg):
            _, op, rest = REDIRECT.match(arg).groups()
            i += 1
            if op == "<<<":
                if rest:
                    here.append(rest)
                elif i < len(args):
                    here.append(args[i])
                    i += 1
            elif not rest:
                i += 1
        else:
            positional.append(arg)
            options = False
            i += 1
    if has_c:
        return positional[:1]
    if positional and not has_s and positional[0] != "-":
        return []
    return here + [h.body for h in heredocs if h.body]


def check_segment(words, depth):
    heredocs = words.heredocs
    words = strip_wrappers(words)
    if not words:
        return None
    name, args = os.path.basename(words[0]), words[1:]
    if name == "rm":
        return check_rm(args)
    if name == "git":
        return check_git(args)
    if name == "find":
        return check_find(args, depth)
    if name in SHELLS:
        for inner in shell_scripts(args, heredocs):
            reason = check_command(inner, depth + 1)
            if reason:
                return reason
    return None


def check_command(command, depth=0):
    if depth > MAX_DEPTH:
        return None
    scanner = Scanner(command)
    try:
        scanner.scan(0, None)
    except ParseError:
        pass
    for words in scanner.segments:
        reason = check_segment(words, depth)
        if reason:
            return "%s: %s" % (reason, " ".join(shlex.quote(w) for w in words)) if depth == 0 else reason
    return None


def main():
    try:
        payload = json.load(sys.stdin)
        command = payload["tool_input"]["command"]
    except (ValueError, KeyError, TypeError):
        return 0
    if not isinstance(command, str):
        return 0
    try:
        reason = check_command(command)
    except Exception:
        return 0
    if reason:
        message = " ".join(("bash-guard blocked " + reason).split())
        print(message[:300], file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
