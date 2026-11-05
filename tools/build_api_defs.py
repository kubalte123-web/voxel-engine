#!/usr/bin/env python3
"""Buduje docs/engine_api.lua – definicje API `engine` dla edytorów (Lua Language Server, np. VS Code),
na podstawie game/scripts/mods/prelude.lua. Uruchom: python3 tools/build_api_defs.py"""
import re

src = open("game/scripts/mods/prelude.lua", encoding="utf-8").read().split("\n")
out = ["---@meta", "-- Definicje API silnika dla podpowiedzi w edytorze (wygenerowane: tools/build_api_defs.py).",
       "-- Opis: docs/MODDING.md. Pozycje: wektor albo tabela {x =, y =, z =}.", "",
       "---@class engine", "engine = {}", ""]
groups = []          # ścieżki tabel, np. ["blocks"], ["player", "storage"]
stack = []           # (wcięcie, nazwa)
comments = []
seen = set()

def emit_group(path):
    name = "engine." + ".".join(path)
    if name in seen: return
    seen.add(name)
    out.append(f"---@class {name}")
    out.append(f"{name} = {{}}")
    out.append("")

def emit_fn(path, fname, args):
    name = "engine." + ".".join(path + [fname]) if path else "engine." + fname
    if name in seen: return
    seen.add(name)
    for c in comments:
        out.append("--- " + c)
    for a in [x.strip() for x in args.split(",") if x.strip() and x.strip() != "..."]:
        out.append(f"---@param {a} any")
    out.append(f"function {name}({args}) end")
    out.append("")

for line in src:
    s = line.rstrip()
    m = re.match(r"^(\t+)-- ?(.*)$", s)
    if m:
        comments.append(m.group(2)); continue
    m = re.match(r"^\tE\.(\w+) = \{", s)
    if m:
        stack = [(1, m.group(1))]; emit_group([m.group(1)]); comments = []; continue
    m = re.match(r"^\tfunction E\.(\w+)\(([^)]*)\)", s)
    if m:
        stack = []; emit_fn([], m.group(1), m.group(2)); comments = []; continue
    m = re.match(r"^\tE\.(\w+) = function\(([^)]*)\)", s)
    if m:
        stack = []; emit_fn([], m.group(1), m.group(2)); comments = []; continue
    m = re.match(r"^(\t+)(\w+) = function\(([^)]*)\)", s)
    if m and stack:
        depth = len(m.group(1))
        while stack and stack[-1][0] >= depth: stack.pop()
        emit_fn([n for _, n in stack], m.group(2), m.group(3)); comments = []; continue
    m = re.match(r"^(\t+)(\w+) = \{\s*$", s)
    if m and stack:
        depth = len(m.group(1))
        while stack and stack[-1][0] >= depth: stack.pop()
        stack.append((depth, m.group(2))); emit_group([n for _, n in stack]); comments = []; continue
    if s.strip() and not s.strip().startswith("--"):
        comments = []

open("docs/engine_api.lua", "w", encoding="utf-8").write("\n".join(out) + "\n")
print(len([l for l in out if l.startswith("function")]), "funkcji")
