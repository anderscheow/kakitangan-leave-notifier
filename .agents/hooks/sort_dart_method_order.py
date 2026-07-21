#!/usr/bin/env python3
"""
Enforce Dart class method ordering: @override → public → private.

Can be invoked with specific file paths, or with no arguments to 
automatically search the current directory and all subdirectories 
for .dart files.

Non-blocking: automatically reorders methods/getters and writes back to the file.
Always exits 0.

Heuristic — not a full parser. Identifies class boundaries, separates 
fields/constructors from methods/getters, and sorts the methods.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

RANK = {"override": 0, "public": 1, "private": 2}

CLASS_RE = re.compile(
    r"^\s*(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+|mixin\s+)*"
    r"(?:class|mixin)\s+(\w+)"
)
METHOD_RE = re.compile(r"^[\w<>?,\s\[\]]+?\s+(_?\w+)\s*\(")
GETTER_RE = re.compile(r"^[\w<>?,\s\[\]]+?\s+get\s+(_?\w+)")

class BraceTracker:
    """Tracks brace depth while ignoring braces inside strings and comments."""
    def __init__(self):
        self.nested = 0
        self.in_string = False
        self.string_char = ''
        self.is_multiline = False

    def update(self, line: str) -> str:
        """Processes the line, updates state, and returns the code portion (excluding // comments)."""
        i = 0
        length = len(line)
        code_end = length

        while i < length:
            char = line[i]

            if char == '\\':
                i += 2
                continue

            if self.in_string:
                if self.is_multiline:
                    if i + 2 < length and line[i:i+3] == self.string_char * 3:
                        self.in_string = False
                        i += 2
                else:
                    if char == self.string_char:
                        self.in_string = False
            else:
                if char == '/' and i + 1 < length and line[i+1] == '/':
                    code_end = i
                    break
                elif i + 2 < length and line[i:i+3] in ("'''", '"""'):
                    self.in_string = True
                    self.is_multiline = True
                    self.string_char = line[i]
                    i += 2
                elif char in ("'", '"'):
                    self.in_string = True
                    self.is_multiline = False
                    self.string_char = char
                elif char == '{':
                    self.nested += 1
                elif char == '}':
                    self.nested -= 1
            i += 1
            
        return line[:code_end]

class Block:
    """Represents a top-level declaration block inside a class."""
    def __init__(self, lines: list[str], class_name: str, original_idx: int):
        self.lines = lines
        self.original_idx = original_idx
        self.is_movable = False
        self.rank = -1
        self.name = ""

        self._analyze(class_name)

    def _analyze(self, class_name: str):
        is_override = False
        name = None
        is_constructor = False

        for line in self.lines:
            stripped = line.strip()
            if stripped.startswith("@override"):
                is_override = True

            if not name:
                g = GETTER_RE.match(stripped)
                if g:
                    name = g.group(1)
                else:
                    m = METHOD_RE.match(stripped)
                    if m:
                        name = m.group(1)
                        # Skip constructors, standard 'Function' declarations, and factories
                        if (name == class_name or
                            name == "Function" or
                            stripped.startswith("factory ") or
                            stripped.startswith("const ")):
                            is_constructor = True
                            name = None

        if name and not is_constructor:
            self.is_movable = True
            self.name = name
            if is_override:
                self.rank = 0
            elif name.startswith("_"):
                self.rank = 2
            else:
                self.rank = 1

def process_file(path: Path) -> bool:
    try:
        lines = path.read_text(encoding="utf-8").splitlines(keepends=False)
    except OSError:
        return False

    new_lines = []
    i = 0
    changed = False

    while i < len(lines):
        m = CLASS_RE.match(lines[i])
        if not m:
            new_lines.append(lines[i])
            i += 1
            continue

        class_name = m.group(1)
        tracker = BraceTracker()
        open_idx = None
        
        # Find the '{' that opens the class
        j = i
        while j < len(lines):
            old_nested = tracker.nested
            tracker.update(lines[j])
            if old_nested == 0 and tracker.nested > 0:
                open_idx = j
                break
            j += 1

        if open_idx is None:
            new_lines.append(lines[i])
            i += 1
            continue

        # Find the closing brace of the class
        close_idx = None
        if tracker.nested == 0:
            close_idx = open_idx
        else:
            j = open_idx + 1
            while j < len(lines):
                tracker.update(lines[j])
                if tracker.nested == 0:
                    close_idx = j
                    break
                j += 1

        if close_idx is None:
            new_lines.append(lines[i])
            i += 1
            continue

        class_header = lines[i : open_idx + 1]
        class_footer = [lines[close_idx]]

        if open_idx == close_idx:
            new_lines.extend(lines[i : close_idx + 1])
            i = close_idx + 1
            continue

        body_lines = lines[open_idx + 1 : close_idx]
        blocks: list[Block] = []
        current_block_lines = []
        block_tracker = BraceTracker()

        # Partition body into discrete member blocks
        for line in body_lines:
            current_block_lines.append(line)
            code_portion = block_tracker.update(line)

            if block_tracker.nested == 0 and not block_tracker.in_string:
                stripped = code_portion.strip()
                if stripped.endswith(';') or stripped.endswith('}'):
                    blocks.append(Block(current_block_lines, class_name, len(blocks)))
                    current_block_lines = []

        if current_block_lines:
            blocks.append(Block(current_block_lines, class_name, len(blocks)))

        # Separate fields/constructors from methods/getters
        unmovables = [b for b in blocks if not b.is_movable]
        movables = [b for b in blocks if b.is_movable]

        # Sort the methods/getters by rank
        sorted_movables = sorted(movables, key=lambda b: (b.rank, b.original_idx))

        if movables != sorted_movables:
            changed = True

        reordered_blocks = unmovables + sorted_movables

        new_lines.extend(class_header)
        for b in reordered_blocks:
            new_lines.extend(b.lines)
        new_lines.extend(class_footer)

        i = close_idx + 1

    if changed:
        path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
        
    return changed

def check_and_process_path(path: Path):
    if path.suffix != ".dart" or not path.is_file():
        return
        
    # Skip generated files
    if any(path.name.endswith(suffix) for suffix in (".g.dart", ".freezed.dart", ".gr.dart")):
        return

    if process_file(path):
        # Print full relative path so it's clear what was fixed across a whole directory
        print(f"FIXED: Dart method ordering violations in {path} (reordered override → public → private)")

def main() -> int:
    if len(sys.argv) > 1:
        # Process specific files if arguments are provided
        for arg in sys.argv[1:]:
            check_and_process_path(Path(arg))
    else:
        # Auto-search the entire folder recursively if no arguments are provided
        print("No arguments provided. Searching the current directory and subdirectories for .dart files...")
        for path in Path(".").rglob("*.dart"):
            check_and_process_path(path)

    return 0

if __name__ == "__main__":
    sys.exit(main())