#!/usr/bin/env python3
"""Build and optionally install the local MZ Inbox companion (no cloud provisioning)."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "com.matteozajac.MZInbox"
SKIP_PARTS = {".build", "DerivedData", "SourcePackages", "checkouts", "node_modules", "output", ".git",
              ".swiftpm", "Pods", "build", "vendor", "repositories", "PreservedBuildArtifacts"}


def run(arguments, **kwargs):
    return subprocess.run([str(item) for item in arguments], check=True, **kwargs)


def bundle_identifiers(project):
    """Resolve application target IDs from the checked-in Xcode graph, never names."""
    result = run(["/usr/bin/plutil", "-convert", "json", "-o", "-", project], capture_output=True)
    graph = json.loads(result.stdout)
    objects = graph["objects"]
    project_object = objects[graph["rootObject"]]

    def reference_path(key, seen=None):
        seen = set() if seen is None else seen
        if key in seen:
            raise ValueError("Cyclic Xcode file reference")
        seen.add(key)
        item = objects[key]
        path = Path(item.get("path", ""))
        if path.is_absolute() or item.get("sourceTree") == "SOURCE_ROOT":
            return project.parent.parent / path
        parent = next((parent_key for parent_key, parent in objects.items()
                       if key in parent.get("children", [])), None)
        return (reference_path(parent, seen) if parent else project.parent.parent) / path

    def xcconfig(path, seen=None):
        seen = set() if seen is None else seen
        path = path.resolve()
        if path in seen or not path.is_file() or path.suffix != ".xcconfig" or path.stat().st_size > 1024 * 1024:
            return {}
        seen.add(path)
        values = {}
        for line in path.read_text().splitlines():
            include = re.match(r'\s*#include\??\s+"([^"]+)"', line)
            if include:
                values.update(xcconfig(path.parent / include[1], seen))
                continue
            match = re.match(r"\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*;?\s*$", line)
            if match:
                values[match[1]] = match[2].split(" //", 1)[0].strip()
        return values

    def configurations(owner):
        group = objects.get(owner.get("buildConfigurationList", ""), {})
        configurations_by_name = {}
        for key in group.get("buildConfigurations", []):
            if key not in objects:
                continue
            config = objects[key]
            values = xcconfig(reference_path(config["baseConfigurationReference"])) if config.get("baseConfigurationReference") else {}
            values.update(config.get("buildSettings", {}))
            configurations_by_name[config.get("name", "")] = values
        return configurations_by_name

    project_settings = configurations(project_object)
    found = set()
    for target in objects.values():
        if target.get("isa") != "PBXNativeTarget" or target.get("productType") != "com.apple.product-type.application":
            continue
        for name, target_settings in configurations(target).items():
            settings = dict(project_settings.get(name, {}))
            settings.update(target_settings)
            value = settings.get("PRODUCT_BUNDLE_IDENTIFIER", "")
            if not isinstance(value, str):
                continue
            for _ in range(10):
                expanded = re.sub(r"\$\(([^)]+)\)|\$\{([^}]+)\}",
                                  lambda match: str(settings.get(match[1] or match[2], match[0])), value)
                if expanded == value:
                    break
                value = expanded
            if re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", value):
                found.add(value)
    return found


def discover_routes(directory):
    """Register actual app targets with an unambiguous local git root."""
    directory = directory.resolve()
    candidates = {}
    projects = []
    for current, directories, filenames in os.walk(directory):
        relative = Path(current).relative_to(directory)
        directories[:] = [name for name in directories if name not in SKIP_PARTS
                          and not name.endswith((".xcarchive", ".app")) and len(relative.parts) < 5]
        if "project.pbxproj" in filenames:
            projects.append(Path(current) / "project.pbxproj")
    for project in projects:
        if project.parent.suffix != ".xcodeproj" or SKIP_PARTS.intersection(project.relative_to(directory).parts):
            continue
        result = subprocess.run(["git", "-C", str(project.parent.parent), "rev-parse", "--show-toplevel"],
                                capture_output=True, text=True)
        if result.returncode:
            continue
        repository = Path(result.stdout.strip()).resolve()
        if repository == ROOT:
            continue  # Samples are a capture demo, rather than a customer app.
        if {"Samples", "Examples", "Packages", "Pods"}.intersection(project.relative_to(repository).parts):
            continue
        try:
            identifiers = bundle_identifiers(project)
        except (ValueError, KeyError, subprocess.CalledProcessError):
            continue
        for identifier in identifiers:
            if identifier.startswith("com.matteozajac.mzfoundation."):
                continue
            candidates.setdefault(identifier, set()).add(repository)
    return [{"bundleIdentifier": identifier, "name": (next(iter(paths)).parent.name if next(iter(paths)).name in {"iOS", "visionOS", "macOS"} else next(iter(paths)).name),
             "repository": str(next(iter(paths))), "mode": "diagnose", "enabled": True}
            for identifier, paths in sorted(candidates.items()) if len(paths) == 1]


def initialize_config(support, cloud, codex, routes, model):
    support.mkdir(parents=True, exist_ok=True)
    support.chmod(0o700)
    path = support / "config.json"
    if path.exists():
        return path  # Keep user routing and chosen permissions on every reinstall.
    if not cloud.is_dir():
        raise ValueError("Enable iCloud Drive on this Mac before installing the inbox.")
    incoming = cloud / "MZ Inbox" / "Incoming"
    statuses = cloud / "MZ Inbox" / "Status"
    incoming.mkdir(parents=True, exist_ok=True)
    statuses.mkdir(parents=True, exist_ok=True)
    config = {"schemaVersion": 1, "inboxPath": str(incoming), "statusPath": str(statuses),
              "statePath": str(support / "state"), "codexPath": str(codex), "pollSeconds": 5,
              "paused": False, "routes": routes}
    if model and model.is_file():
        config["whisperModel"] = str(model)
    with path.open("x", encoding="utf-8") as stream:
        json.dump(config, stream, indent=2)
        stream.write("\n")
    path.chmod(0o600)
    return path


def build(output, python):
    package = ROOT / "Tools" / "MZInboxMac"
    scratch = output / ".build"
    run(["swift", "build", "--package-path", package, "--scratch-path", scratch, "-c", "release"])
    result = run(["swift", "build", "--package-path", package, "--scratch-path", scratch,
                  "-c", "release", "--show-bin-path"], capture_output=True, text=True)
    binary = Path(result.stdout.strip()) / "MZInbox"
    app = output / "MZ Inbox.app"
    if app.exists():
        shutil.rmtree(app)
    contents = app / "Contents"
    executable = contents / "MacOS" / "MZInbox"
    executable.parent.mkdir(parents=True)
    shutil.copy2(binary, executable)
    resources = contents / "Resources"
    resources.mkdir(parents=True)
    artwork = package / "Artwork"
    for name in ("AppIcon.icns", "RabbitTemplate.png"):
        shutil.copy2(artwork / name, resources / name)
    ignored = shutil.ignore_patterns("__pycache__", "*.pyc", ".build", "tests", "test_*.py")
    shutil.copytree(ROOT / "Tools" / "MZInbox", resources / "worker", ignore=ignored)
    shutil.copytree(ROOT / "skills" / "app-bug-report", resources / "report-tools", ignore=ignored)
    if (ROOT / "docs" / "report-inbox.md").exists():
        shutil.copy2(ROOT / "docs" / "report-inbox.md", resources / "Getting Started.md")
    shortcut = output / "Send to my agent.shortcut"
    if shortcut.is_file():
        shutil.copy2(shortcut, resources / shortcut.name)
    info = {"CFBundleIdentifier": BUNDLE_ID, "CFBundleName": "MZ Inbox", "CFBundleDisplayName": "MZ Inbox",
            "CFBundleExecutable": "MZInbox", "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
            "CFBundleIconFile": "AppIcon",
            "CFBundleShortVersionString": "0.1.0", "LSMinimumSystemVersion": "15.0", "LSUIElement": True,
            "NSHighResolutionCapable": True, "MZInboxPythonPath": str(python),
            "NSPrincipalClass": "NSApplication"}
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    run(["/usr/bin/codesign", "--force", "--sign", "-", app])
    run(["/usr/bin/codesign", "--verify", "--strict", app])
    return app


def install(app, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        info = plistlib.loads((destination / "Contents" / "Info.plist").read_bytes())
        if info.get("CFBundleIdentifier") != BUNDLE_ID:
            raise ValueError("The destination is occupied by a different app.")
        shutil.rmtree(destination)
    shutil.copytree(app, destination)
    return destination


def install_login_item(app, home):
    path = home / "Library" / "LaunchAgents" / f"{BUNDLE_ID}.plist"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps({"Label": BUNDLE_ID,
                                    "ProgramArguments": ["/usr/bin/open", "-g", str(app)],
                                    "RunAtLoad": True}))
    path.chmod(0o600)
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "output" / "inbox")
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--launch", action="store_true")
    parser.add_argument("--login", action="store_true", help="Open the installed companion at Mac login")
    parser.add_argument("--discover-root", type=Path, help="Register unambiguous Foundation app targets in this directory")
    parser.add_argument("--python", type=Path, default=Path(sys.executable))
    args = parser.parse_args()
    if (args.launch or args.login or args.discover_root) and not args.install:
        parser.error("--launch, --login and --discover-root require --install")
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    python = args.python.expanduser().absolute()
    version = run([python, "-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"],
                  capture_output=True, text=True)
    if tuple(int(part) for part in version.stdout.strip().split(".")) < (3, 11):
        raise ValueError("MZ Inbox requires Python 3.11 or newer. Choose its executable with --python.")
    app = build(output, python)
    receipt = {"app": str(app), "signing": "local-ad-hoc"}
    if args.install:
        codex = shutil.which("codex")
        if not codex:
            raise ValueError("Install and sign in to Codex CLI before installing MZ Inbox.")
        home = Path.home()
        routes = discover_routes(args.discover_root.expanduser().resolve()) if args.discover_root else []
        receipt["config"] = str(initialize_config(
            home / "Library" / "Application Support" / "MZ Inbox",
            home / "Library" / "Mobile Documents" / "com~apple~CloudDocs", Path(codex), routes,
            home / ".cache" / "whisper.cpp" / "ggml-small.bin"))
        shortcut = output / "Send to my agent.shortcut"
        if shortcut.is_file():
            phone_shortcut = home / "Library" / "Mobile Documents" / "com~apple~CloudDocs" / "MZ Inbox" / shortcut.name
            phone_shortcut.parent.mkdir(parents=True, exist_ok=True)
            if phone_shortcut.is_symlink():
                raise ValueError("The phone shortcut destination is a symbolic link. Choose a regular file destination.")
            shutil.copy2(shortcut, phone_shortcut)
            receipt["phoneShortcut"] = str(phone_shortcut)
        app = install(app, home / "Applications" / "MZ Inbox.app")
        receipt["installedApp"] = str(app)
        if args.login:
            receipt["loginItem"] = str(install_login_item(app, home))
        if args.launch:
            run(["/usr/bin/open", "-g", app])
    (output / "build-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"MZ Inbox build failed: {error}", file=sys.stderr)
        raise SystemExit(1)
