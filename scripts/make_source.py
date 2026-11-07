#!/usr/bin/env python3
"""Writes the SideStore/AltStore source (source.json) for a release.

Usage: make_source.py <ipa> <version> <build> <owner/repo> <tag> <out> [changelog]
The source lists only the newest version; it is attached to every release, so the stable URL
https://github.com/<owner/repo>/releases/latest/download/source.json always points at the newest build.
The version's text ("Neu in dieser Version") and one news entry come from the version's section of CHANGELOG.md
(default: CHANGELOG.md next to this repo's scripts/); without a section a short default text is used.
"""
import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from changelog_section import body_or_default, plain  # noqa: E402

ipa, version, build, repo, tag, out = sys.argv[1:7]
changelog = sys.argv[7] if len(sys.argv) > 7 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "CHANGELOG.md")
base = f"https://github.com/{repo}"
release_url = f"{base}/releases/tag/{tag}"
try:
    with open(changelog, encoding="utf-8") as f:
        notes = plain(body_or_default(version, f.read()))
except OSError:
    notes = plain(body_or_default(version, ""))
today = datetime.date.today().isoformat()
first_line = next((l.lstrip("- ").strip() for l in notes.splitlines() if l.strip() and not l.strip().endswith(":") and l.strip() not in ("Neu", "Geändert", "Behoben")), f"Relay {version}")
source = {
    "name": "Relay iOS",
    "identifier": "dev.relay.ios.source",
    "subtitle": "Relay für das iPhone",
    "sourceURL": f"{base}/releases/latest/download/source.json",
    "website": base,
    "apps": [{
        "name": "Relay",
        "bundleIdentifier": "dev.relay.ios",
        "developerName": repo.split("/")[0],
        "subtitle": "KI-Sitzungen auf dem Desktop vom iPhone steuern",
        "localizedDescription": "iPhone-App für Relay (github.com/chart21/relay): Sitzungsliste, Chat, Antwortkarten, "
                                "Live-Bildschirm, neue Sitzungen und Jarvis per Sprache, alles über die eigene SSH-Verbindung.",
        "iconURL": f"https://raw.githubusercontent.com/{repo}/main/App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
        "tintColor": "#3B82F6",
        "category": "developer",
        "versions": [{
            "version": version,
            "buildVersion": build,
            "date": today,
            "localizedDescription": f"{notes}\n\nRelease: {release_url}",
            "downloadURL": f"{base}/releases/download/{tag}/Relay.ipa",
            "size": os.path.getsize(ipa),
            "minOSVersion": "17.0",
        }],
        "appPermissions": {
            "entitlements": [],
            "privacy": {
                "NSMicrophoneUsageDescription": "Jarvis hört zu, wenn du aufs Mikrofon tippst.",
                "NSSpeechRecognitionUsageDescription": "Sprache wird auf dem iPhone in Text umgewandelt.",
                "NSFaceIDUsageDescription": "Relay lässt sich mit Face ID sperren.",
                "NSLocalNetworkUsageDescription": "SSH-Verbindung zum Desktop im lokalen Netz.",
                "NSPhotoLibraryUsageDescription": "Fotos an eine Sitzung schicken.",
            },
        },
    }],
    "news": [{
        "title": f"Relay {version}",
        "identifier": f"relay-{version}",
        "caption": first_line[:200],
        "date": today,
        "tintColor": "#3B82F6",
        "appID": "dev.relay.ios",
        "url": release_url,
        "notify": True,
    }],
}
with open(out, "w") as f:
    json.dump(source, f, ensure_ascii=False, indent=2)
print(f"{out}: Relay {version} ({build}), {os.path.getsize(ipa)} bytes, Hinweise aus {changelog if os.path.exists(changelog) else 'Standardtext'}")
