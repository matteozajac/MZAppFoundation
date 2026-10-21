import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

import build_inbox


def write_project(root, identifier):
    project = root / "Example.xcodeproj" / "project.pbxproj"
    project.parent.mkdir(parents=True)
    graph = {"rootObject": "project", "objects": {
        "project": {"isa": "PBXProject", "buildConfigurationList": "projectConfigs"},
        "projectConfigs": {"buildConfigurations": ["base"]},
        "base": {"name": "Release", "buildSettings": {}},
        "app": {"isa": "PBXNativeTarget", "productType": "com.apple.product-type.application",
                "buildConfigurationList": "appConfigs"},
        "appConfigs": {"buildConfigurations": ["appRelease"]},
        "appRelease": {"name": "Release", "buildSettings": {"PRODUCT_BUNDLE_IDENTIFIER": identifier}},
        "widget": {"isa": "PBXNativeTarget", "productType": "com.apple.product-type.app-extension",
                   "buildConfigurationList": "widgetConfigs"},
        "widgetConfigs": {"buildConfigurations": ["widgetRelease"]},
        "widgetRelease": {"name": "Release", "buildSettings": {"PRODUCT_BUNDLE_IDENTIFIER": "com.example.widget"}},
    }}
    project.write_bytes(plistlib.dumps(graph))
    return project, graph


class InboxBuildTests(unittest.TestCase):
    def test_resolves_base_xcconfig_and_excludes_extensions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project, graph = write_project(root, "$(APP_ID)")
            (root / "Config").mkdir()
            (root / "Config" / "Release.xcconfig").write_text('#include "Shared.xcconfig"\n')
            (root / "Config" / "Shared.xcconfig").write_text('APP_ID = com.example.actual\n')
            graph["objects"].update({
                "mainGroup": {"isa": "PBXGroup", "children": ["configGroup"]},
                "configGroup": {"isa": "PBXGroup", "path": "Config", "children": ["file"]},
                "file": {"isa": "PBXFileReference", "path": "Release.xcconfig", "sourceTree": "<group>"},
            })
            graph["objects"]["appRelease"]["baseConfigurationReference"] = "file"
            project.write_bytes(plistlib.dumps(graph))
            self.assertEqual(build_inbox.bundle_identifiers(project), {"com.example.actual"})

    def test_does_not_guess_unresolved_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            project, _ = write_project(Path(directory), "$(UNKNOWN_ID)")
            self.assertEqual(build_inbox.bundle_identifiers(project), set())

    def test_discovery_rejects_ambiguous_ids_and_package_samples(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("first", "second"):
                repository = root / name
                repository.mkdir()
                subprocess.run(["git", "init", "--quiet", str(repository)], check=True)
                write_project(repository, "com.example.same")
                write_project(repository / "Packages" / "Dependency" / "Samples", "com.example.sample")
            self.assertEqual(build_inbox.discover_routes(root), [])

    def test_reinstall_preserves_user_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            support, cloud = root / "support", root / "cloud"
            cloud.mkdir()
            path = build_inbox.initialize_config(support, cloud, Path("/bin/codex"), [], None)
            customized = json.loads(path.read_text())
            customized["paused"] = True
            customized["routes"] = [{"bundleIdentifier": "com.example.app", "mode": "fix"}]
            path.write_text(json.dumps(customized))
            build_inbox.initialize_config(support, cloud, Path("/different/codex"), [], None)
            self.assertEqual(json.loads(path.read_text()), customized)


if __name__ == "__main__":
    unittest.main()
