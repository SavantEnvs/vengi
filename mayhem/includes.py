#!/usr/bin/env python3
"""Print the -I/-isystem/-D flags CMake used for a voxelformat TU, one per line, so the
harness compiles with exactly the include paths and defines the library has."""
import json, shlex, sys

for e in json.load(open(sys.argv[1])):
    if not e["file"].endswith("src/modules/voxelformat/Format.cpp"):
        continue
    toks = shlex.split(e["command"])
    i = 0
    while i < len(toks):
        t = toks[i]
        if t in ("-isystem", "-I", "-D") and i + 1 < len(toks):
            print(t)
            print(toks[i + 1])
            i += 1
        elif t.startswith(("-I", "-D", "-isystem")):
            print(t)
        i += 1
    break
