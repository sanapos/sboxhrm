#!/usr/bin/env python3
"""Minimal Dart-aware scanner: strings (with interpolation), brackets, args."""
from __future__ import annotations

QUOTES = ("'", '"')


def skip_string(text: str, i: int) -> int:
    """text[i] is a quote (possibly preceded by r). Return index after string."""
    raw = False
    if text[i] == "r" and i + 1 < len(text) and text[i + 1] in QUOTES:
        raw = True
        i += 1
    q = text[i]
    triple = text.startswith(q * 3, i)
    term = q * 3 if triple else q
    i += len(term)
    while i < len(text):
        c = text[i]
        if not raw and c == "\\":
            i += 2
            continue
        if not raw and c == "$" and i + 1 < len(text):
            if text[i + 1] == "{":
                i = skip_braces(text, i + 1)
                continue
            j = i + 1
            while j < len(text) and (text[j].isalnum() or text[j] == "_"):
                j += 1
            i = j
            continue
        if text.startswith(term, i):
            return i + len(term)
        i += 1
    return i


def skip_braces(text: str, i: int) -> int:
    """text[i] == '{'. Return index after matching '}'."""
    depth = 0
    while i < len(text):
        c = text[i]
        if c in QUOTES or (c == "r" and i + 1 < len(text) and text[i + 1] in QUOTES):
            i = skip_string(text, i)
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return i


def first_arg_span(text: str, open_paren: int) -> tuple[int, int] | None:
    """text[open_paren] == '('. Return (start, end) of first argument."""
    i = open_paren + 1
    while i < len(text) and text[i].isspace():
        i += 1
    start = i
    depth = 0
    while i < len(text):
        c = text[i]
        if c in QUOTES or (c == "r" and i + 1 < len(text) and text[i + 1] in QUOTES):
            i = skip_string(text, i)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0 and c == ")":
                return (start, i)
            depth -= 1
        elif c in ",;" and depth == 0:
            return (start, i)
        i += 1
    return None


def value_span(text: str, colon: int) -> tuple[int, int] | None:
    """text[colon] == ':' of a named arg. Return (start, end) of its value."""
    i = colon + 1
    while i < len(text) and text[i].isspace():
        i += 1
    start = i
    depth = 0
    while i < len(text):
        c = text[i]
        if c in QUOTES or (c == "r" and i + 1 < len(text) and text[i + 1] in QUOTES):
            i = skip_string(text, i)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                return (start, i)
            depth -= 1
        elif c in ",;" and depth == 0:
            return (start, i)
        i += 1
    return None
