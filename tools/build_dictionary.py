#!/usr/bin/env python3
"""Expand Hunspell es_ES + es_AR into a flat, normalized word list for the game.

Usage:
    python -I tools/build_dictionary.py <hunspell_dir> <output_file>

<hunspell_dir> must contain es_ES.dic/.aff and es_AR.dic/.aff
(LibreOffice/dictionaries, es/, used under MPL 1.1).

Normalization rules (see project decisions):
- accents are stripped (a-u), but the letter n-tilde is kept as its own letter
- only lowercase dictionary entries are used (drops proper nouns and acronyms)
- words must match [a-zñ]{3,16} (16 = longest possible path on a 4x4 grid)
"""
import re
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

MIN_LEN = 3
MAX_LEN = 16
VALID = re.compile(r"^[a-zñ]{%d,%d}$" % (MIN_LEN, MAX_LEN))


def parse_aff(path):
    """Return {'PFX': {flag: (cross, [rules])}, 'SFX': {...}}.

    A rule is (strip, add, cond_regex, cont_flags).
    """
    affixes = {"PFX": {}, "SFX": {}}
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) < 4 or parts[0] not in affixes:
            continue
        kind, flag = parts[0], parts[1]
        if len(parts) == 4 and parts[3].isdigit():
            affixes[kind][flag] = (parts[2] == "Y", [])
            continue
        strip = "" if parts[2] == "0" else parts[2]
        add, _, cont = parts[3].partition("/")
        add = "" if add == "0" else add
        cond = parts[4] if len(parts) > 4 else "."
        pattern = cond + "$" if kind == "SFX" else "^" + cond
        affixes[kind][flag][1].append((strip, add, re.compile(pattern), cont))
    return affixes


def apply_rule(kind, word, strip, add, cond):
    if not cond.search(word):
        return None
    if kind == "SFX":
        if strip and not word.endswith(strip):
            return None
        return (word[: len(word) - len(strip)] if strip else word) + add
    if strip and not word.startswith(strip):
        return None
    return add + word[len(strip):]


def expand_entry(word, flags, affixes):
    """Yield every surface form for a stem and its flags (one continuation level)."""
    forms = {word}
    sfx_forms = []  # (form, cross)
    pfx_forms = []

    def collect(kind, base, flag_str, depth, sink):
        for flag in flag_str:
            if flag not in affixes[kind]:
                continue
            cross, rules = affixes[kind][flag]
            for strip, add, cond, cont in rules:
                out = apply_rule(kind, base, strip, add, cond)
                if out is None:
                    continue
                sink.append((out, cross))
                if cont and depth < 1:
                    collect(kind, out, cont, depth + 1, sink)

    collect("SFX", word, flags, 0, sfx_forms)
    collect("PFX", word, flags, 0, pfx_forms)
    forms.update(f for f, _ in sfx_forms)
    forms.update(f for f, _ in pfx_forms)
    # cross product: prefix on top of suffixed forms when both allow it
    for sform, scross in sfx_forms:
        if not scross:
            continue
        for flag in flags:
            if flag not in affixes["PFX"]:
                continue
            pcross, rules = affixes["PFX"][flag]
            if not pcross:
                continue
            for strip, add, cond, _ in rules:
                out = apply_rule("PFX", sform, strip, add, cond)
                if out is not None:
                    forms.add(out)
    return forms


def normalize(word):
    """Lowercase, strip accents but keep n-tilde. Returns None if invalid."""
    word = word.replace("ñ", "\x00")
    word = unicodedata.normalize("NFD", word)
    word = "".join(c for c in word if unicodedata.category(c) != "Mn")
    word = word.replace("\x00", "ñ")
    return word if VALID.match(word) else None


def expand_dictionary(dic_path, aff_path):
    affixes = parse_aff(aff_path)
    lines = dic_path.read_text(encoding="utf-8").splitlines()
    out = set()
    for raw in lines[1:]:  # first line is the entry count
        raw = raw.strip()
        if not raw:
            continue
        stem, _, flags = raw.partition("/")
        if stem != stem.lower():  # skip proper nouns and acronyms
            continue
        for form in expand_entry(stem, flags, affixes):
            norm = normalize(form)
            if norm:
                out.add(norm)
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dest = Path(sys.argv[1]), Path(sys.argv[2])
    words = set()
    for variant in ("es_ES", "es_AR"):
        found = expand_dictionary(src / f"{variant}.dic", src / f"{variant}.aff")
        print(f"{variant}: {len(found):,} normalized words")
        words |= found
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text("\n".join(sorted(words)) + "\n", encoding="utf-8", newline="\n")
    by_len = defaultdict(int)
    for w in words:
        by_len[len(w)] += 1
    print(f"union: {len(words):,} words -> {dest}")
    print("by length:", dict(sorted(by_len.items())))


if __name__ == "__main__":
    main()
