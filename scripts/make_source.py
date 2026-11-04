#!/usr/bin/env python3
"""Writes the SideStore/AltStore source (source.json) for a release.

Usage: make_source.py <ipa> <version> <build> <owner/repo> <tag> <out>
The source lists only the newest version; it is attached to every release, so the stable URL
https://github.com/<owner/repo>/releases/latest/download/source.json always points at the newest build.
"""
import datetime
import json
import os
import sys

ipa, version, build, repo, tag, out = sys.argv[1:7]
base = f"https://github.com/{repo}"
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
            "date": datetime.date.today().isoformat(),
            "localizedDescription": f"Siehe {base}/releases/tag/{tag}",
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
    "news": [],
}
with open(out, "w") as f:
    json.dump(source, f, ensure_ascii=False, indent=2)
print(f"{out}: Relay {version} ({build}), {os.path.getsize(ipa)} bytes")
