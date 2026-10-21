#!/usr/bin/env python3
"""Reads the Android screen through `adb uiautomator dump` so the journey never uses coordinates
or sleeps. Standard library only.

  ui.py exists  [matchers]     exit 0 if a node matches
  ui.py center  [matchers]     print "x y" of the first match (exit 1 if none)
  ui.py rows                   JSON list of the todo rows on screen: title, completed, notes
  ui.py open-count             the "N open" number in the top bar, or -1
  ui.py size                   print "width height" of the screen
  ui.py texts                  every non-empty text on screen, one per line

Matchers (all must hold): --text X  --text-re R  --desc X  --desc-re R  --checked true|false
                          --focused true|false  --cls android.widget.EditText
"""
import json
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ADB = os.environ.get("ADB", "adb")
BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")


def dump():
    for _ in range(10):
        out = subprocess.run([ADB, "exec-out", "uiautomator", "dump", "/dev/tty"],
                             capture_output=True, text=True).stdout
        start, end = out.find("<?xml"), out.rfind("</hierarchy>")
        if start >= 0 and end >= 0:
            return ET.fromstring(out[start:end + len("</hierarchy>")])
        time.sleep(0.5)  # the screen can be mid-animation: "null root node"
    sys.exit("ui.py: could not read the UI hierarchy")


def box(node):
    x1, y1, x2, y2 = map(int, BOUNDS.search(node.get("bounds", "[0,0][0,0]")).groups())
    return x1, y1, x2, y2


def center(node):
    x1, y1, x2, y2 = box(node)
    return (x1 + x2) // 2, (y1 + y2) // 2


def parse_matchers(args):
    matchers, it = {}, iter(args)
    for arg in it:
        if not arg.startswith("--"):
            sys.exit(f"ui.py: unexpected argument {arg}")
        matchers[arg[2:]] = next(it)
    return matchers


def matches(node, m):
    checks = {
        "text": lambda v: node.get("text") == v,
        "text-re": lambda v: re.search(v, node.get("text") or "") is not None,
        "desc": lambda v: node.get("content-desc") == v,
        "desc-re": lambda v: re.search(v, node.get("content-desc") or "") is not None,
        "checked": lambda v: node.get("checked") == v,
        "focused": lambda v: node.get("focused") == v,
        "cls": lambda v: node.get("class") == v,
    }
    return all(checks[key](value) for key, value in m.items())


def find(root, m):
    return [n for n in root.iter("node") if matches(n, m)]


def rows(root):
    """One entry per todo. The checkbox carries the title ("Complete <title>") and the checked
    state; the other texts beside it are the notes."""
    nodes = list(root.iter("node"))
    checkboxes = [n for n in nodes if (n.get("content-desc") or "").startswith("Complete ")]
    checkboxes.sort(key=lambda n: center(n)[1])
    result = [{"title": n.get("content-desc")[len("Complete "):],
               "completed": n.get("checked") == "true", "notes": None} for n in checkboxes]
    for text_node in nodes:
        text = text_node.get("text")
        if not text or not checkboxes:
            continue
        cx, cy = center(text_node)
        index = min(range(len(checkboxes)), key=lambda i: abs(center(checkboxes[i])[1] - cy))
        cb_x, cb_y = center(checkboxes[index])
        if abs(cb_y - cy) < 110 and cx > cb_x and text != result[index]["title"]:
            result[index]["notes"] = text
    return result


def main():
    command, rest = sys.argv[1], sys.argv[2:]
    root = dump()
    if command == "exists":
        sys.exit(0 if find(root, parse_matchers(rest)) else 1)
    if command == "center":
        found = find(root, parse_matchers(rest))
        if not found:
            sys.exit(1)
        print(*center(found[0]))
    elif command == "rows":
        print(json.dumps(rows(root)))
    elif command == "open-count":
        counts = [re.fullmatch(r"(\d+) open", n.get("text") or "") for n in root.iter("node")]
        counts = [m for m in counts if m]
        print(int(counts[0].group(1)) if counts else -1)
    elif command == "size":
        x1, y1, x2, y2 = box(root[0])
        print(x2 - x1, y2 - y1)
    elif command == "texts":
        for n in root.iter("node"):
            if n.get("text"):
                print(n.get("text"))
    else:
        sys.exit(f"ui.py: unknown command {command}")


if __name__ == "__main__":
    main()
