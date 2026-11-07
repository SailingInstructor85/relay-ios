#!/usr/bin/env python3
"""The section of one version from CHANGELOG.md, for the GitHub release text and the SideStore description.

Usage: changelog_section.py <version> [--changelog CHANGELOG.md] [--repo owner/repo] [--tag vX.Y.Z]
                            [--release | --plain] [--out FILE]

  (default)   the section's markdown body without its heading
  --release   markdown for the GitHub release: heading line, body, links to README, Nachtlog and Changelog at the tag
  --plain     plain text for SideStore (bold marks removed, bullets kept)

A missing section never fails the build: a short default text is written instead (exit code 0).
The changelog format is "## x.y.z (JJJJ-MM-TT)" per version, newest first; the body runs to the next "## ".
"""
import argparse
import re
import sys

DEFAULT = "Relay {version}: Wartungsversion ohne gesonderte Versionshinweise. Einzelheiten stehen im Changelog."


def section(version: str, text: str) -> "str | None":
    """Body of the "## <version> (...)" section, without heading, or None."""
    m = re.search(r"^## " + re.escape(version) + r"\b[^\n]*\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        return None
    body = m.group(1).strip("\n").rstrip()
    return body or None


def heading(version: str, text: str) -> str:
    """"0.3.5 (2026-11-07)" from the heading line, or just the version."""
    m = re.search(r"^## (" + re.escape(version) + r"\b[^\n]*)$", text, re.M)
    return m.group(1).strip() if m else version


def plain(md: str) -> str:
    """Markdown bold and links out, so SideStore shows readable text; bullets and blank lines stay."""
    t = re.sub(r"\*\*(.+?)\*\*", r"\1", md)
    t = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", t)
    t = re.sub(r"`([^`]*)`", r"\1", t)
    t = re.sub(r"\n{3,}", "\n\n", t)
    return t.strip()


def body_or_default(version: str, text: str) -> str:
    return section(version, text) or DEFAULT.format(version=version)


def release(version: str, text: str, repo: str, tag: str) -> str:
    base = f"https://github.com/{repo}/blob/{tag}" if repo and tag else ""
    out = [f"## Relay {heading(version, text)}", "", body_or_default(version, text), ""]
    if base:
        out += ["---", "", f"Dokumentation: [README]({base}/README.md) · [Nachtlog]({base}/docs/nachtlog.md) · [Changelog]({base}/CHANGELOG.md)"]
    return "\n".join(out).rstrip() + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("version")
    ap.add_argument("--changelog", default="CHANGELOG.md")
    ap.add_argument("--repo", default="")
    ap.add_argument("--tag", default="")
    ap.add_argument("--release", action="store_true")
    ap.add_argument("--plain", action="store_true")
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    version = a.version.lstrip("v")
    try:
        with open(a.changelog, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        print(f"changelog_section: {a.changelog} nicht lesbar ({e}), Standardtext", file=sys.stderr)
        text = ""
    if section(version, text) is None:
        print(f"changelog_section: kein Abschnitt für {version} in {a.changelog}, Standardtext", file=sys.stderr)
    if a.release:
        result = release(version, text, a.repo, a.tag or f"v{version}")
    elif a.plain:
        result = plain(body_or_default(version, text)) + "\n"
    else:
        result = body_or_default(version, text) + "\n"
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            f.write(result)
    else:
        sys.stdout.write(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
