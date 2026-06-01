#!/usr/bin/env python3
"""Wrap AlertDialog content: SizedBox(...) with ScrollableDialogBody.wrap."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "flutter_client" / "lib" / "screens"

_CHILD_WHITELIST = (
    "formContent",
    "contentBody",
    "formFields",
    "buildContent",
    "buildList",
    "formBody",
    "content",
    "buildFormContent",
    "buildForm",
)


def rel_import(path: Path) -> str:
    rel = path.relative_to(ROOT.parent)
    depth = len(rel.parts) - 1
    return "../" * depth + "widgets/scrollable_dialog_body.dart"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def ensure_import(text: str, imp: str) -> str:
    if "scrollable_dialog_body" in text:
        return text
    anchor = "import 'package:flutter/material.dart';"
    if anchor in text:
        return text.replace(anchor, anchor + f"\nimport '{imp}';", 1)
    return text


def fix_extra_paren_before_actions(text: str) -> str:
    """Remove stray '),` left after unwrap (wrap closes with one '),' before actions)."""
    patterns = [
        (
            r"(\]\),)\s*\n(\s*)\),\s*\n\2\),\s*\n\2actions:",
            r"\1\n\2),\n\2actions:",
        ),
        (
            r"(\],)\s*\n(\s*)\),\s*\n\2\),\s*\n\2actions:",
            r"\1\n\2),\n\2actions:",
        ),
    ]
    for pat, repl in patterns:
        prev = None
        while prev != text:
            prev = text
            text = re.sub(pat, repl, text)
    return text


def unwrap_nested_scroll(text: str) -> str:
    patterns = [
        (
            r"content: SizedBox\(\s*\n\s*width: 400,\s*\n\s*child: SingleChildScrollView\(\s*\n\s*child: Column\(mainAxisSize: MainAxisSize\.min, children: \[",
            "content: ScrollableDialogBody.wrap(\n            context,\n            maxWidth: 400,\n            child: Column(mainAxisSize: MainAxisSize.min, children: [",
        ),
        (
            r"content: SizedBox\(\s*\n\s*width: 400,\s*\n\s*child: SingleChildScrollView\(\s*\n\s*child: Column\(\s*\n\s*mainAxisSize: MainAxisSize\.min,",
            "content: ScrollableDialogBody.wrap(\n            context,\n            maxWidth: 400,\n            child: Column(\n                mainAxisSize: MainAxisSize.min,",
        ),
        (
            r"content: SizedBox\(\s*\n\s*width: Responsive\.dialogWidth\(context\),\s*\n\s*child: SingleChildScrollView\(\s*\n\s*child: Column\(\s*\n\s*mainAxisSize: MainAxisSize\.min,",
            "content: ScrollableDialogBody.wrap(\n              context,\n              maxWidth: 560,\n              child: Column(\n                  mainAxisSize: MainAxisSize.min,",
        ),
        (
            r"content: SizedBox\(\s*\n\s*width: Responsive\.dialogWidth\(context\),\s*\n\s*child: SingleChildScrollView\(\s*\n\s*child: Column\(\s*\n\s*crossAxisAlignment: CrossAxisAlignment\.start,",
            "content: ScrollableDialogBody.wrap(\n          context,\n          maxWidth: 560,\n          child: Column(\n              crossAxisAlignment: CrossAxisAlignment.start,",
        ),
        (
            r"content: SizedBox\(\s*\n\s*width: 300,\s*\n\s*child: SingleChildScrollView\(\s*\n\s*child: Column\(\s*\n\s*crossAxisAlignment: CrossAxisAlignment\.start,\s*\n\s*mainAxisSize: MainAxisSize\.min,",
            "content: ScrollableDialogBody.wrap(\n        context,\n        maxWidth: 320,\n        child: Column(\n            crossAxisAlignment: CrossAxisAlignment.start,\n            mainAxisSize: MainAxisSize.min,",
        ),
        (
            r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*child: SingleChildScrollView\(\s*\n\s*child: Column\(\s*\n\s*mainAxisSize: MainAxisSize\.min,",
            r"content: ScrollableDialogBody.wrap(\n            context,\n            maxWidth: \1,\n            child: Column(\n                mainAxisSize: MainAxisSize.min,",
        ),
        (
            r"content: SizedBox\(\s*\n\s*width: MediaQuery\.of\(context\)\.size\.width < 600\s*\n\s*\? MediaQuery\.of\(context\)\.size\.width - 32\s*\n\s*: (\d+),\s*\n\s*child: SingleChildScrollView\(\s*\n\s*child: Column\(",
            r"content: ScrollableDialogBody.wrap(\n            context,\n            maxWidth: \1,\n            child: Column(",
        ),
    ]
    for pat, repl in patterns:
        text = re.sub(pat, repl, text)
    return text


def wrap_sizedbox_math_form(text: str) -> str:
    def repl(m):
        w = m.group(1)
        return (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {w},\n"
            f"            child: formBody,"
        )

    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: math\s*\n\s*\.min\((\d+), MediaQuery\.of\(context\)\.size\.width - 32\)\s*\n\s*\.toDouble\(\),\s*\n\s*child: formBody,",
        repl,
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: math\s*\n\s*\.min\((\d+), MediaQuery\.of\(context\)\.size\.width - 32\)\s*\n\s*\.toDouble\(\),\s*\n\s*child: SingleChildScrollView\(child: formBody\),",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            child: formBody,"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: math\s*\n\s*\.min\((\d+), MediaQuery\.of\(context\)\.size\.width - 32\)\s*\n\s*\.toDouble\(\),\s*\n\s*child: SingleChildScrollView\(child: (\w+)\),",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            child: {m.group(2)},"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width:\s*\n\s*math\.min\((\d+), MediaQuery\.of\(context\)\.size\.width - 32\)\.toDouble\(\),\s*\n\s*child: Column\(\s*\n\s*mainAxisSize: MainAxisSize\.min,",
        r"content: ScrollableDialogBody.wrap(\n            context,\n            maxWidth: \1,\n            child: Column(\n                mainAxisSize: MainAxisSize.min,",
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: math\s*\n\s*\.min\((\d+), MediaQuery\.of\(context\)\.size\.width - 32\)\s*\n\s*\.toDouble\(\),\s*\n\s*height: (\d+),\s*\n\s*child: (\w+),",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            maxHeightFactor: 0.75,\n"
            f"            child: {m.group(3)},"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: math\s*\n\s*\.min\((\d+), MediaQuery\.of\(context\)\.size\.width - 32\)\s*\n\s*\.toDouble\(\),\s*\n\s*height: (\d+),\s*\n\s*child: SingleChildScrollView\(child: (\w+)\(\)\),",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            maxHeightFactor: 0.75,\n"
            f"            child: {m.group(3)}(),"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: math\s*\n\s*\.min\((\d+), MediaQuery\.of\(context\)\.size\.width - 32\)\s*\n\s*\.toDouble\(\),\s*\n\s*height: (\d+),\s*\n\s*child: Column\(",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            maxHeightFactor: 0.75,\n"
            f"            child: Column("
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: math\s*\n\s*\.min\((\d+), MediaQuery\.of\(context\)\.size\.width - 32\)\s*\n\s*\.toDouble\(\),\s*\n\s*height: (\d+),\s*\n\s*child: ListView\(",
        lambda m: (
            f"content: SizedBox(\n"
            f"            width: math\n"
            f"                .min({m.group(1)}, MediaQuery.of(context).size.width - 32)\n"
            f"                .toDouble(),\n"
            f"            height: ScrollableDialogBody.maxHeight(context, factor: 0.75),\n"
            f"            child: ListView("
        ),
        text,
    )
    return text


def wrap_sizedbox_fixed_width(text: str) -> str:
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*child: SingleChildScrollView\(\s*\n\s*child: Column\(mainAxisSize: MainAxisSize\.min, children: \[",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            child: Column(mainAxisSize: MainAxisSize.min, children: ["
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: MediaQuery\.of\(context\)\.size\.width < 600\s*\n\s*\? MediaQuery\.of\(context\)\.size\.width - 32\s*\n\s*: (\d+),\s*\n\s*child: SingleChildScrollView\(\s*\n\s*child: Column\(mainAxisSize: MainAxisSize\.min, children: \[",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            child: Column(mainAxisSize: MainAxisSize.min, children: ["
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*child: SingleChildScrollView\(child: (\w+)\),",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            child: {m.group(2)},"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*child: (\w+),",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            child: {m.group(2)},"
        )
        if m.group(2) in _CHILD_WHITELIST
        else m.group(0),
        text,
    )
    # One-liner: SizedBox(width: W, height: H, child: X())
    text = re.sub(
        r"content: SizedBox\(width: (\d+), height: (\d+), child: (\w+)\(\)\),",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            maxHeightFactor: 0.75,\n"
            f"            child: {m.group(3)}(),\n"
            f"          ),"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*height: (\d+),\s*\n\s*child: (\w+)\(\),",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            maxHeightFactor: 0.75,\n"
            f"            child: {m.group(3)}(),"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*height: (\d+),\s*\n\s*child: Column\(",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            maxHeightFactor: 0.75,\n"
            f"            child: Column("
        ),
        text,
    )
    return text


def wrap_mediaquery_column(text: str) -> str:
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: MediaQuery\.of\(context\)\.size\.width < 600\s*\n\s*\? MediaQuery\.of\(context\)\.size\.width - 32\s*\n\s*: (\d+),\s*\n\s*child: (const )?Column\(\s*\n\s*mainAxisSize: MainAxisSize\.min,",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"          context,\n"
            f"          maxWidth: {m.group(1)},\n"
            f"          child: {m.group(2) or ''}Column(\n"
            f"              mainAxisSize: MainAxisSize.min,"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: MediaQuery\.of\(context\)\.size\.width < 600\s*\n\s*\? MediaQuery\.of\(context\)\.size\.width - 32\s*\n\s*: (\d+),\s*\n\s*child: Column\(\s*\n\s*mainAxisSize: MainAxisSize\.min,",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"          context,\n"
            f"          maxWidth: {m.group(1)},\n"
            f"          child: Column(\n"
            f"              mainAxisSize: MainAxisSize.min,"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: Responsive\.dialogWidth\(context\),\s*\n\s*child: Column\(\s*\n\s*mainAxisSize: MainAxisSize\.min,",
        "content: ScrollableDialogBody.wrap(\n          context,\n          maxWidth: 560,\n          child: Column(\n              mainAxisSize: MainAxisSize.min,",
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*child: Column\(\s*\n\s*mainAxisSize: MainAxisSize\.min,\s*\n\s*crossAxisAlignment:",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            child: Column(\n"
            f"              mainAxisSize: MainAxisSize.min,\n"
            f"              crossAxisAlignment:"
        ),
        text,
    )
    return text


def wrap_column_in_sizedbox(text: str) -> str:
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width:\s*\n\s*math\.min\(400, MediaQuery\.of\(context\)\.size\.width - 32\)\.toDouble\(\),\s*\n\s*child: Column\(mainAxisSize: MainAxisSize\.min, children: \[",
        "content: ScrollableDialogBody.forAlert(context, Column(mainAxisSize: MainAxisSize.min, children: [",
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: 300,\s*\n\s*child: Column\(mainAxisSize: MainAxisSize\.min, children: \[",
        "content: ScrollableDialogBody.forAlert(context, Column(mainAxisSize: MainAxisSize.min, children: [",
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: 360,\s*\n\s*child: Column\(\s*\n\s*mainAxisSize: MainAxisSize\.min,",
        "content: ScrollableDialogBody.wrap(\n          context,\n          maxWidth: 360,\n          child: Column(\n              mainAxisSize: MainAxisSize.min,",
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*child: Column\(\s*\n\s*mainAxisSize: MainAxisSize\.min,\s*\n\s*children:",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            child: Column(\n"
            f"              mainAxisSize: MainAxisSize.min,\n"
            f"              children:"
        ),
        text,
    )
    text = re.sub(
        r"(ScrollableDialogBody\.forAlert\(context, Column\([\s\S]*?)\n(\s*)\]\),\n(\s*)\),\n(\s*)actions:",
        lambda m: m.group(1) + "\n" + m.group(2) + "])),\n" + m.group(3) + "actions:",
        text,
    )
    return text


def wrap_inline_and_oneline(text: str) -> str:
    wl = "|".join(_CHILD_WHITELIST)
    text = re.sub(
        rf"content: SizedBox\(width: (\d+), child: ({wl})\),",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"              context,\n"
            f"              maxWidth: {m.group(1)},\n"
            f"              child: {m.group(2)},\n"
            f"            ),"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: math\.min\((\d+), MediaQuery\.of\((context|ctx)\)\.size\.width - 32\)\.toDouble\(\),\s*\n\s*child: formBody,",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"          {m.group(2)},\n"
            f"          maxWidth: {m.group(1)},\n"
            f"          child: formBody,"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: math\.min\((\d+), MediaQuery\.of\((context|ctx)\)\.size\.width - 32\)\.toDouble\(\),\s*\n\s*child: SingleChildScrollView\(child: formBody\),",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"              {m.group(2)},\n"
            f"              maxWidth: {m.group(1)},\n"
            f"              child: formBody,"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: math\.min\((\d+), MediaQuery\.of\(context\)\.size\.width - 32\)\.toDouble\(\),\s*\n\s*child: SingleChildScrollView\(\s*\n\s*child: Column\(mainAxisSize: MainAxisSize\.min, children: \[",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"          context,\n"
            f"          maxWidth: {m.group(1)},\n"
            f"          child: Column(mainAxisSize: MainAxisSize.min, children: ["
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: MediaQuery\.of\(context\)\.size\.width < 600 \? MediaQuery\.of\(context\)\.size\.width - 32 : (\d+),\s*\n\s*child: Column\(",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"          context,\n"
            f"          maxWidth: {m.group(1)},\n"
            f"          child: Column("
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: Responsive\.dialogWidth\(context\),\s*\n\s*child: SingleChildScrollView\(child: contentBody\),",
        "content: ScrollableDialogBody.wrap(\n            context,\n            maxWidth: 560,\n            child: contentBody,",
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*child: SingleChildScrollView\(\s*\n\s*child: buildFormContent\(setDlgState\),",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"              context,\n"
            f"              maxWidth: {m.group(1)},\n"
            f"              child: buildFormContent(setDlgState),"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*child: buildForm\(setDlgState\),",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"              context,\n"
            f"              maxWidth: {m.group(1)},\n"
            f"              child: buildForm(setDlgState),"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*child: buildFormContent\(setDlgState\),",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"              context,\n"
            f"              maxWidth: {m.group(1)},\n"
            f"              child: buildFormContent(setDlgState),"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: 620,\s*\n\s*child: SingleChildScrollView\(\s*\n\s*child: Column\(\s*\n\s*crossAxisAlignment: CrossAxisAlignment\.start,",
        "content: ScrollableDialogBody.wrap(\n            context,\n            maxWidth: 620,\n            child: Column(\n                crossAxisAlignment: CrossAxisAlignment.start,",
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*child: StatefulBuilder\(\s*\n\s*builder: \(ctx, setSt\) => SingleChildScrollView\(",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"          context,\n"
            f"          maxWidth: {m.group(1)},\n"
            f"          child: StatefulBuilder(\n"
            f"            builder: (ctx, setSt) => SingleChildScrollView("
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: MediaQuery\.of\(context\)\.size\.width < 600\s*\n\s*\? MediaQuery\.of\(context\)\.size\.width - 32\s*\n\s*: (\d+),\s*\n\s*child: Column\(mainAxisSize: MainAxisSize\.min, children: \[",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"          context,\n"
            f"          maxWidth: {m.group(1)},\n"
            f"          child: Column(mainAxisSize: MainAxisSize.min, children: ["
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*child: SingleChildScrollView\(\s*\n\s*child: Column\(\s*\n\s*crossAxisAlignment: CrossAxisAlignment\.start,\s*\n\s*mainAxisSize: MainAxisSize\.min,",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            child: Column(\n"
            f"                crossAxisAlignment: CrossAxisAlignment.start,\n"
            f"                mainAxisSize: MainAxisSize.min,"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: math\s*\n\s*\.min\((\d+), MediaQuery\.of\(context\)\.size\.width - 32\)\s*\n\s*\.toDouble\(\),\s*\n\s*child: Column\(\s*\n\s*mainAxisSize: MainAxisSize\.min,\s*\n\s*crossAxisAlignment:",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            child: Column(\n"
            f"              mainAxisSize: MainAxisSize.min,\n"
            f"              crossAxisAlignment:"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: math\s*\n\s*\.min\((\d+), MediaQuery\.of\(context\)\.size\.width - 32\)\s*\n\s*\.toDouble\(\),\s*\n\s*child: Column\(\s*\n\s*mainAxisSize: MainAxisSize\.min,\s*\n\s*children:",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"            context,\n"
            f"            maxWidth: {m.group(1)},\n"
            f"            child: Column(\n"
            f"              mainAxisSize: MainAxisSize.min,\n"
            f"              children:"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: Responsive\.dialogWidth\(context\),\s*\n\s*height: (\d+),\s*\n\s*child: Column\(",
        "content: SizedBox(\n              width: Responsive.dialogWidth(context),\n              height: ScrollableDialogBody.maxHeight(context, factor: 0.75),\n              child: Column(",
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: MediaQuery\.of\(context\)\.size\.width < 600 \? MediaQuery\.of\(context\)\.size\.width - 32 : (\d+),\s*\n\s*child: formContent,",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"              context,\n"
            f"              maxWidth: {m.group(1)},\n"
            f"              child: formContent,"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: math\.min\((\d+), MediaQuery\.of\(context\)\.size\.width - 32\),\s*\n\s*child: Column\(",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"                context,\n"
            f"                maxWidth: {m.group(1)},\n"
            f"                child: Column("
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: MediaQuery\.of\(context\)\.size\.width < 600 \? MediaQuery\.of\(context\)\.size\.width - 32 : (\d+),\s*\n\s*height: (\d+),\s*\n\s*child: SingleChildScrollView\(",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"              context,\n"
            f"              maxWidth: {m.group(1)},\n"
            f"              maxHeightFactor: 0.75,\n"
            f"              child: SingleChildScrollView("
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: math\.min\(400, MediaQuery\.of\(context\)\.size\.width - 32\)\.toDouble\(\),\s*\n\s*child:\s*\n\s*Column\(mainAxisSize: MainAxisSize\.min, children: \[",
        "content: ScrollableDialogBody.wrap(\n          context,\n          maxWidth: 400,\n          child: Column(mainAxisSize: MainAxisSize.min, children: [",
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: math\.min\(400, MediaQuery\.of\(context\)\.size\.width - 32\)\.toDouble\(\),\s*\n\s*child: SingleChildScrollView\(\s*\n\s*child: Column\(\s*\n\s*mainAxisSize: MainAxisSize\.min,",
        "content: ScrollableDialogBody.wrap(\n              context,\n              maxWidth: 400,\n              child: Column(\n                  mainAxisSize: MainAxisSize.min,",
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: isMobile \? double\.infinity : (\d+),\s*\n\s*child: Column\(",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"              context,\n"
            f"              maxWidth: {m.group(1)},\n"
            f"              child: Column("
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: isMobile \? double\.infinity : null,\s*\n\s*child: Column\(",
        "content: ScrollableDialogBody.wrap(\n          context,\n          maxWidth: 520,\n          child: Column(",
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*height: (\d+),\s*\n\s*child: _shifts\.isEmpty",
        lambda m: (
            f"content: SizedBox(\n"
            f"          width: {m.group(1)},\n"
            f"          height: ScrollableDialogBody.maxHeight(context, factor: 0.55),\n"
            f"          child: _shifts.isEmpty"
        ),
        text,
    )
    return text


def wrap_more_column_patterns(text: str) -> str:
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*child: Column\(mainAxisSize: MainAxisSize\.min, children: \[",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"          context,\n"
            f"          maxWidth: {m.group(1)},\n"
            f"          child: Column(mainAxisSize: MainAxisSize.min, children: ["
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: (\d+),\s*\n\s*child: widget\.",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"          context,\n"
            f"          maxWidth: {m.group(1)},\n"
            f"          child: widget."
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: Responsive\.dialogWidth\(context\),\s*\n\s*child: formContent,",
        "content: ScrollableDialogBody.wrap(\n              context,\n              maxWidth: 560,\n              child: formContent,",
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: Responsive\.dialogWidth\(context\),\s*\n\s*child: content,",
        "content: ScrollableDialogBody.wrap(\n              context,\n              maxWidth: 560,\n              child: content,",
        text,
    )
    return text


def wrap_ctx_and_inline_child(text: str) -> str:
    """MediaQuery.of(ctx) and child: widget) on few lines."""
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: MediaQuery\.of\((ctx|context)\)\.size\.width < 600\s*\n\s*\? MediaQuery\.of\(\1\)\.size\.width - (\d+)\s*\n\s*: (\d+),\s*\n\s*child: (\w+)\),",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"                    {m.group(1)},\n"
            f"                    maxWidth: {m.group(3)},\n"
            f"                    child: {m.group(4)}),"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: MediaQuery\.of\((ctx|context)\)\.size\.width < 600\s*\n\s*\? MediaQuery\.of\(\1\)\.size\.width - 32\s*\n\s*: (\d+),\s*\n\s*child: StatefulBuilder\(",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"          {m.group(1)},\n"
            f"          maxWidth: {m.group(2)},\n"
            f"          child: StatefulBuilder("
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: MediaQuery\.of\(context\)\.size\.width < 600\s*\n\s*\? MediaQuery\.of\(context\)\.size\.width - 32\s*\n\s*: (\d+),\s*\n\s*child: StatefulBuilder\(",
        lambda m: (
            f"content: ScrollableDialogBody.wrap(\n"
            f"          context,\n"
            f"          maxWidth: {m.group(1)},\n"
            f"          child: StatefulBuilder("
        ),
        text,
    )
    return text


def wrap_fixed_height_list(text: str) -> str:
    """SizedBox with fixed height + ListView -> maxHeight constraint."""
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: MediaQuery\.of\(context\)\.size\.width < 600\s*\n\s*\? MediaQuery\.of\(context\)\.size\.width - 32\s*\n\s*: (\d+),\s*\n\s*height: (\d+),\s*\n\s*child: ListView\(",
        lambda m: (
            f"content: SizedBox(\n"
            f"                width: MediaQuery.of(context).size.width < 600\n"
            f"                    ? MediaQuery.of(context).size.width - 32\n"
            f"                    : {m.group(1)},\n"
            f"                height: ScrollableDialogBody.maxHeight(context, factor: 0.75),\n"
            f"                child: ListView("
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: MediaQuery\.of\(context\)\.size\.width < 600\s*\n\s*\? MediaQuery\.of\(context\)\.size\.width - 32\s*\n\s*: (\d+),\s*\n\s*height: (\d+),\s*\n\s*child: (\w+),",
        lambda m: (
            f"content: SizedBox(\n"
            f"            width: MediaQuery.of(context).size.width < 600\n"
            f"                ? MediaQuery.of(context).size.width - 32\n"
            f"                : {m.group(1)},\n"
            f"            height: ScrollableDialogBody.maxHeight(context, factor: 0.75),\n"
            f"            child: {m.group(3)},"
        ),
        text,
    )
    text = re.sub(
        r"content: SizedBox\(\s*\n\s*width: MediaQuery\.of\(context\)\.size\.width < 600\s*\n\s*\? MediaQuery\.of\(context\)\.size\.width - 32\s*\n\s*: (\d+),\s*\n\s*height: MediaQuery",
        lambda m: (
            f"content: SizedBox(\n"
            f"            width: MediaQuery.of(context).size.width < 600\n"
            f"                ? MediaQuery.of(context).size.width - 32\n"
            f"                : {m.group(1)},\n"
            f"            height: MediaQuery"
        ),
        text,
    )
    # Dialog-level content: (not indented content:)
    text = re.sub(
        r"(\n\s*)content: SizedBox\(\s*\n\s*width: MediaQuery\.of\(context\)\.size\.width < 600\s*\n\s*\? MediaQuery\.of\(context\)\.size\.width - 32\s*\n\s*: 600,\s*\n\s*height: 450,\s*\n\s*child:",
        r"\1content: SizedBox(\n\1  width: MediaQuery.of(context).size.width < 600\n\1      ? MediaQuery.of(context).size.width - 32\n\1      : 600,\n\1  height: ScrollableDialogBody.maxHeight(context, factor: 0.75),\n\1  child:",
        text,
    )
    return text


def fix_file(path: Path) -> bool:
    text = read_text(path)
    if "AlertDialog" not in text or "content: SizedBox(" not in text:
        return False
    orig = text
    imp = rel_import(path)
    text = ensure_import(text, imp)
    text = unwrap_nested_scroll(text)
    text = wrap_sizedbox_fixed_width(text)
    text = wrap_sizedbox_math_form(text)
    text = wrap_mediaquery_column(text)
    text = wrap_column_in_sizedbox(text)
    text = wrap_fixed_height_list(text)
    text = wrap_ctx_and_inline_child(text)
    text = wrap_more_column_patterns(text)
    text = wrap_inline_and_oneline(text)
    text = fix_extra_paren_before_actions(text)
    if text != orig:
        path.write_text(encoding="utf-8", data=text)
        return True
    return False


def main():
    changed = []
    for path in sorted(ROOT.rglob("*.dart")):
        if ".bak" in path.name:
            continue
        if fix_file(path):
            changed.append(path)
    print(f"Updated {len(changed)} files")
    for p in changed:
        print(p.relative_to(ROOT.parent.parent.parent))


if __name__ == "__main__":
    main()
