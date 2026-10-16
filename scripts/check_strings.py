#!/usr/bin/env python3
"""Validates Sources/MidgarPortal/Resources/Localizable.xcstrings.

Every key must carry every locale in LOCALES, with the same printf placeholders as the English
source and no leftover English for languages that are not Latin script. Exits 1 on any problem.
"""
import json
import pathlib
import re
import sys

CATALOG = pathlib.Path(__file__).resolve().parent.parent / "Sources" / "MidgarPortal" / "Resources" / "Localizable.xcstrings"
LOCALES = ["ar", "cs", "da", "de", "es", "fi", "fr", "it", "ja", "ko", "nb", "nl", "pl", "pt-BR", "pt-PT",
           "ru", "sv", "tr", "uk", "vi", "zh-Hans", "zh-Hant"]
NON_LATIN = {"ar", "ja", "ko", "ru", "uk", "zh-Hans", "zh-Hant"}
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|@|d)")
UPPERCASE_KEYS = {"ALL APPS", "OPEN", "VIEW", "GET", "SEND TO %@"}
BRANDS = {"Midgar", "Midgar Oy"}


def value(entry, locale):
    unit = entry.get("localizations", {}).get(locale, {}).get("stringUnit")
    return unit["value"] if unit else None


def main():
    catalog = json.loads(CATALOG.read_text())
    problems = []
    for key, entry in catalog["strings"].items():
        wanted = sorted(PLACEHOLDER.findall(key))
        for locale in LOCALES:
            text = value(entry, locale)
            if text is None:
                problems.append(f"{key!r}: missing {locale}")
                continue
            if sorted(PLACEHOLDER.findall(text)) != wanted:
                problems.append(f"{key!r}: {locale} placeholders differ: {text!r}")
            if locale in NON_LATIN and text.strip() == key.strip():
                problems.append(f"{key!r}: {locale} is still English")
            if "—" in text:
                problems.append(f"{key!r}: {locale} contains an em dash")
            if key in UPPERCASE_KEYS and locale not in NON_LATIN and text != text.upper():
                problems.append(f"{key!r}: {locale} should be uppercase: {text!r}")
    for problem in problems:
        print("FAIL", problem)
    print(f"{len(catalog['strings'])} keys x {len(LOCALES)} locales, {len(problems)} problems")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
