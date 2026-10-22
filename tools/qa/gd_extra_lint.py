#!/usr/bin/env python3
"""Extra GDScript checks gdlint does not have (uses gdtoolkit's own parser).

  * duplicate-member   two funcs/vars/consts/signals with one name in the same class scope
  * duplicate-local    a local declared twice in the same block (Godot rejects this)
  * unused-local       a local `var` whose name appears nowhere else in its function

Usage: gd_extra_lint.py <dir-or-file>...   Exit 1 only for duplicate-* findings (unused-local is advisory).
Files the gdtoolkit grammar cannot parse are reported as `parse-skip` (they are not errors;
the grammar lags Godot: soft keywords such as `set`, multi-line "strings"); they never fail the run.
"""
import os
import sys

from gdtoolkit.parser import parser
from lark import Token, Tree

MEMBER_RULES = {"func_def": 0, "class_var_stmt": 0, "const_stmt": 0, "signal_stmt": 0,
                "static_func_def": 0}


def first_name(node):
    """Declared name of a func_def / var / const / signal node, or None."""
    def dig(n):
        for c in n.children:
            if isinstance(c, Token) and c.type == "NAME":
                return c
            if isinstance(c, Tree):
                if c.data in ("func_args", "expr", "type_hint", "getset", "setget"):
                    continue
                r = dig(c)
                if r is not None:
                    return r
        return None
    return dig(node)


def names_in(n, out):
    for c in n.children:
        if isinstance(c, Token):
            if c.type == "NAME":
                out.append(str(c))
        elif isinstance(c, Tree):
            names_in(c, out)


def check_members(scope, path, problems):
    seen = {}
    for c in scope.children:
        if isinstance(c, Tree) and c.data in MEMBER_RULES:
            t = first_name(c)
            if t is None:
                continue
            nm = str(t)
            if nm in seen:
                problems.append((path, t.line, "duplicate-member",
                                 "'%s' already declared at line %d" % (nm, seen[nm])))
            else:
                seen[nm] = t.line
        if isinstance(c, Tree) and c.data == "class_def":
            check_members(c, path, problems)


def check_blocks(node, path, problems):
    seen = {}
    for c in node.children:
        if isinstance(c, Tree) and c.data == "func_var_stmt":
            t = first_name(c)
            if t is not None:
                nm = str(t)
                if nm in seen:
                    problems.append((path, t.line, "duplicate-local",
                                     "local '%s' already declared at line %d" % (nm, seen[nm])))
                else:
                    seen[nm] = t.line
    for c in node.children:
        if isinstance(c, Tree):
            check_blocks(c, path, problems)


def check_unused(func, path, problems):
    allnames = []
    names_in(func, allnames)
    for d in func.find_data("func_var_stmt"):
        t = first_name(d)
        if t is None:
            continue
        nm = str(t)
        if nm.startswith("_"):
            continue
        if allnames.count(nm) <= 1:
            problems.append((path, t.line, "unused-local", "local '%s' is never used" % nm))


def lint_file(path, problems, skipped):
    src = open(path, encoding="utf8", errors="replace").read().replace("\r\n", "\n")
    try:
        tree = parser.parse(src, gather_metadata=True)
    except Exception as e:  # grammar lag, not a game error
        skipped.append((path, str(e).strip().splitlines()[0] if str(e).strip() else "parse error"))
        return
    check_members(tree, path, problems)
    check_blocks(tree, path, problems)
    for f in tree.find_data("func_def"):
        check_unused(f, path, problems)


def main(argv):
    files = []
    for a in argv or ["."]:
        if os.path.isfile(a):
            files.append(a)
            continue
        for root, _, names in os.walk(a):
            files += [os.path.join(root, n) for n in names if n.endswith(".gd")]
    problems, skipped = [], []
    for f in sorted(files):
        lint_file(f, problems, skipped)
    for p, line, rule, msg in sorted(problems):
        print("%s:%d: %s: %s" % (p, line, rule, msg))
    for p, msg in skipped:
        print("%s: parse-skip (gdtoolkit grammar): %s" % (p, msg[:80]))
    print("gd_extra_lint: %d problem(s), %d file(s) skipped, %d scanned" %
          (len(problems), len(skipped), len(files)))
    return 1 if any(p[2].startswith("duplicate") for p in problems) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
