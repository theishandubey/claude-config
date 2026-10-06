#!/usr/bin/env python3
import os
import re
import sys

REQUIRED = ("name", "description", "tools", "model", "effort")
ALLOWED_KEYS = {
    "name", "description", "prompt", "tools", "disallowedTools", "model", "effort",
    "permissionMode", "mcpServers", "hooks", "maxTurns", "skills", "initialPrompt",
    "memory", "background", "omitClaudeMd", "isolation", "color",
}
TOOLS = {"Read", "Bash", "Write", "Edit", "Skill", "WebSearch", "WebFetch", "Grep", "Glob"}
MODELS = {"fable", "opus", "sonnet"}
EFFORTS = {"low", "medium", "high", "xhigh", "max"}
KEY_RE = re.compile(r"^([A-Za-z]+):\s*(.*)$")
COMMAND_RE = re.compile(r"^\s*(?:-\s+)?command:\s*(.*?)\s*$")
HOOKS_PREFIX = "$HOME/.claude/hooks/"


def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def read_frontmatter(path):
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    if not lines or lines[0].rstrip() != "---":
        return None, "frontmatter missing (first line must be ---)"
    for index in range(1, len(lines)):
        if lines[index].rstrip() == "---":
            return lines[1:index], None
    return None, "frontmatter unterminated (no closing ---)"


def parse_keys(lines):
    keys = {}
    problems = []
    current = None
    for line in lines:
        if not line.strip():
            continue
        if line[0] in " \t":
            if current is None:
                problems.append("indented line before any key: " + line.strip())
            else:
                keys[current]["nested"].append(line)
            continue
        match = KEY_RE.match(line)
        if not match:
            problems.append("unparseable frontmatter line: " + line)
            continue
        current = match.group(1)
        keys[current] = {"value": match.group(2).strip(), "nested": []}
    return keys, problems


def check_tool_list(key, entry, errors):
    for tool in (item.strip() for item in entry["value"].split(",")):
        if tool not in TOOLS:
            errors.append("%s: unknown tool %r" % (key, tool))


def check_hook_commands(entry, root, errors):
    for line in entry["nested"]:
        match = COMMAND_RE.match(line)
        if not match:
            continue
        command = unquote(match.group(1))
        script = command.split()[0] if command.split() else ""
        if script.startswith(HOOKS_PREFIX):
            script = "hooks/" + script[len(HOOKS_PREFIX):]
        resolved = os.path.join(root, script)
        if not script or not os.path.isfile(resolved):
            errors.append("hooks: command script %r does not exist in the repo" % script)
        elif not os.access(resolved, os.X_OK):
            errors.append("hooks: command script %r is not executable" % script)


def check_agent(path, root):
    errors = []
    lines, problem = read_frontmatter(path)
    if problem:
        return [problem]
    keys, problems = parse_keys(lines)
    errors.extend(problems)
    for key in REQUIRED:
        if key not in keys:
            errors.append("required key missing: " + key)
    for key in keys:
        if key not in ALLOWED_KEYS:
            errors.append("unknown key: " + key)
    stem = os.path.splitext(os.path.basename(path))[0]
    if "name" in keys and unquote(keys["name"]["value"]) != stem:
        errors.append("name %r does not match file name %r" % (keys["name"]["value"], stem))
    if "description" in keys:
        entry = keys["description"]
        if not unquote(entry["value"]) and not entry["nested"]:
            errors.append("description is empty")
    if "model" in keys and unquote(keys["model"]["value"]) not in MODELS:
        errors.append("model %r is not one of %s" % (keys["model"]["value"], "/".join(sorted(MODELS))))
    if "effort" in keys and unquote(keys["effort"]["value"]) not in EFFORTS:
        errors.append("effort %r is not one of %s" % (keys["effort"]["value"], "/".join(sorted(EFFORTS))))
    for key in ("tools", "disallowedTools"):
        if key in keys:
            check_tool_list(key, keys[key], errors)
    if "hooks" in keys:
        check_hook_commands(keys["hooks"], root, errors)
    return errors


def main():
    root = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))
    agents_dir = os.path.join(root, "agents")
    paths = []
    for directory, _, names in os.walk(agents_dir):
        paths.extend(os.path.join(directory, name) for name in names if name.endswith(".md"))
    paths.sort()
    failed = False
    for path in paths:
        for error in check_agent(path, root):
            print("%s: %s" % (os.path.relpath(path, root), error))
            failed = True
    if not paths:
        print("agents: no agent files found under %s" % agents_dir)
        failed = True
    if failed:
        return 1
    print("agents: %d ok" % len(paths))
    return 0


if __name__ == "__main__":
    sys.exit(main())
