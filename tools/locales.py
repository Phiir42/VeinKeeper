"""VeinKeeper's translation files (VeinKeeper/Locales/<code>.lua).

    python tools/locales.py              check every locale file (the Checks workflow runs this)
    python tools/locales.py new deDE     start a file for a language, listed in the .toc
    python tools/locales.py update       add new English text to every locale file, keeping translations

The English text is the code's L["..."] keys. A locale file has one line per
key, commented out until translated:

    L["Minimap pins"] = "Minikartenpunkte"
    --L["World map pins"] = ""

A check fails on a translation of text the code no longer has, on one whose
placeholders (%s, %d, %.1f, %%) differ from the English, and on a locale file
the .toc doesn't load between Locale.lua and Check.lua.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "VeinKeeper")
LOCALES = os.path.join(ADDON, "Locales")
TOC = os.path.join(ADDON, "VeinKeeper.toc")

# GetLocale() codes and the language's name, for new files
LANGUAGES = {
    "deDE": "German", "esES": "Spanish (Spain)", "esMX": "Spanish (Latin America)", "frFR": "French",
    "itIT": "Italian", "koKR": "Korean", "ptBR": "Portuguese (Brazil)", "ruRU": "Russian",
    "zhCN": "Chinese (simplified)", "zhTW": "Chinese (traditional)",
}

KEY = re.compile(r'\bL\["((?:[^"\\]|\\.)*)"\]')
LINE = re.compile(r'^\s*(--)?\s*L\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"')
PLACEHOLDER = re.compile(r"%[-+ #0]*\d*\.?\d*[a-zA-Z%]")


def code_keys():
    """[(file, [keys in order of first use])] over the addon's code."""
    seen, out = set(), []
    files = sorted(f for f in os.listdir(ADDON) if f.endswith(".lua"))
    # in load order, so related text stays together in the locale files
    with open(TOC, encoding="utf-8") as fh:
        order = [l.strip() for l in fh if l.strip().endswith(".lua") and not l.startswith("#")]
    files.sort(key=lambda f: order.index(f) if f in order else len(order))
    for f in files:
        with open(os.path.join(ADDON, f), encoding="utf-8") as fh:
            keys = []
            for k in KEY.findall(fh.read()):
                if k not in seen:
                    seen.add(k)
                    keys.append(k)
        if keys:
            out.append((f, keys))
    return out


def placeholders(s):
    return PLACEHOLDER.findall(s)


def locale_files():
    return sorted(f[:-4] for f in os.listdir(LOCALES)
                  if re.fullmatch(r"[a-z]{2}[A-Z]{2}\.lua", f))


def read_locale(code):
    """{key: translation} for the translated lines, and a list of problems."""
    path = os.path.join(LOCALES, code + ".lua")
    out, problems = {}, []
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            m = LINE.match(line)
            if not m or m.group(1) or m.group(3) == "":
                continue
            key, text = m.group(2), m.group(3)
            if key in out:
                problems.append("%s.lua:%d: translated twice: %s" % (code, n, key))
            out[key] = text
            if placeholders(key) != placeholders(text):
                problems.append("%s.lua:%d: placeholders %s should be %s: %s" % (
                    code, n, " ".join(placeholders(text)) or "none", " ".join(placeholders(key)) or "none", key))
    return out, problems


def toc_lines():
    with open(TOC, encoding="utf-8") as fh:
        return fh.read().splitlines()


def write_locale(code, translated):
    """Rewrite a locale file: every key in code order, translations kept."""
    name = LANGUAGES.get(code, code)
    lines = [
        "-- %s. Translate a line by removing its \"--\" and writing the text between" % name,
        "-- the quotes; lines left as they are stay English. Keep %s, %d, %.1f and %%",
        "-- in the same order (a translation where they differ isn't used). Slash",
        "-- commands (/vk route...) stay English. python tools/locales.py update adds",
        "-- new English text and keeps your translations.",
        "local L = select(2, ...).Locale(\"%s\")" % code,
        "if not L then return end",
    ]
    for f, keys in code_keys():
        lines += ["", "-- " + f]
        for k in keys:
            if k in translated:
                lines.append('L["%s"] = "%s"' % (k, translated[k]))
            else:
                lines.append('--L["%s"] = ""' % k)
    with open(os.path.join(LOCALES, code + ".lua"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


def check():
    keys = {k for _, ks in code_keys() for k in ks}
    toc = [l.strip() for l in toc_lines()]
    errors, report = [], []
    for code in locale_files():
        translated, problems = read_locale(code)
        errors += problems
        for k in translated:
            if k not in keys:
                errors.append("%s.lua: translates text the code no longer has: %s" % (code, k))
        entry = "Locales\\%s.lua" % code
        if entry not in toc:
            errors.append("VeinKeeper.toc doesn't load %s" % entry)
        elif not (toc.index("Locales\\Locale.lua") < toc.index(entry) < toc.index("Locales\\Check.lua")):
            errors.append("VeinKeeper.toc: %s must load between Locales\\Locale.lua and Locales\\Check.lua" % entry)
        done = len([k for k in translated if k in keys])
        report.append("%s: %d of %d translated" % (code, done, len(keys)))
    print("%d English texts in the code" % len(keys))
    for r in report:
        print("  " + r)
    for e in errors:
        print("ERROR " + e)
    return 1 if errors else 0


def new(code):
    if not re.fullmatch(r"[a-z]{2}[A-Z]{2}", code):
        sys.exit("a GetLocale() code such as deDE")
    if code == "enUS" or code == "enGB":
        sys.exit("English is the code's own text")
    if os.path.exists(os.path.join(LOCALES, code + ".lua")):
        sys.exit("%s.lua already exists; use update" % code)
    write_locale(code, {})
    lines = toc_lines()
    at = lines.index("Locales\\Check.lua")
    lines.insert(at, "Locales\\%s.lua" % code)
    with open(TOC, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print("wrote VeinKeeper/Locales/%s.lua and added it to the .toc" % code)


def update():
    keys = {k for _, ks in code_keys() for k in ks}
    for code in locale_files():
        translated, _ = read_locale(code)
        stale = [k for k in translated if k not in keys]
        write_locale(code, {k: v for k, v in translated.items() if k in keys})
        print("%s: updated%s" % (code, ", dropped %d no longer used" % len(stale) if stale else ""))


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        sys.exit(check())
    if args[0] == "new" and len(args) == 2:
        new(args[1])
    elif args[0] == "update" and len(args) == 1:
        update()
    else:
        sys.exit(__doc__)
