#!/usr/bin/env python3
"""Build Apple's importable Share Sheet shortcut for the MZ Inbox receiver.

The only external operation is Apple's native shortcut signing service. The
shortcut contains no report contents, credentials, account IDs, or Mac paths.
The destination is selected once during import because a Files folder bookmark
belongs to the device that creates it.
"""

from __future__ import annotations

import argparse
import plistlib
from pathlib import Path
import shutil
import subprocess
import sys
import uuid


DEFAULT_NAME = "Send to my agent"
DEFAULT_OUTPUT = Path(__file__).resolve().parent.parent / "output" / "inbox"
# Shortcuts' rabbit face glyph and the first (coral-red) palette color.
DEFAULT_ICON_GLYPH = 61558
DEFAULT_ICON_COLOR = 4282601983


def action(identifier: str, **parameters: object) -> dict[str, object]:
    return {
        "WFWorkflowActionIdentifier": identifier,
        "WFWorkflowActionParameters": parameters,
    }


def variable(kind: str, **values: str) -> dict[str, object]:
    return {
        "Value": {"Type": kind, **values},
        "WFSerializationType": "WFTextTokenAttachment",
    }


def workflow(name: str = DEFAULT_NAME) -> dict[str, object]:
    """Return a portable workflow; never serialize this Mac's folder bookmark."""
    namespace = uuid.uuid5(uuid.NAMESPACE_URL, "https://mzappfoundation.local/inbox/" + name)
    condition_id = str(uuid.uuid5(namespace, "zip-condition")).upper()
    extension_id = str(uuid.uuid5(namespace, "extension")).upper()
    shortcut_input = variable("ExtensionInput")
    extension = variable("ActionOutput", OutputUUID=extension_id, OutputName="File Extension")
    actions = [
        action(
            "is.workflow.actions.properties.files",
            WFInput=shortcut_input,
            WFContentItemPropertyName="File Extension",
            UUID=extension_id,
        ),
        action(
            "is.workflow.actions.conditional",
            WFConditions={
                "Value": {
                    "WFActionParameterFilterPrefix": 1,
                    "WFActionParameterFilterTemplates": [
                        {
                            "WFInput": {"Type": "Variable", "Variable": extension},
                            "WFCondition": 4,  # Shortcuts' serialized "is" comparison.
                            "WFConditionalActionString": "zip",
                        }
                    ],
                    "WFContentPredicateBoundedDate": False,
                },
                "WFSerializationType": "WFContentPredicateTableTemplate",
            },
            GroupingIdentifier=condition_id,
            WFControlFlowMode=0,
        ),
        action(
            "is.workflow.actions.documentpicker.save",
            WFInput=shortcut_input,
            WFAskWhereToSave=False,
            WFSaveFileOverwrite=False,
        ),
        action(
            "is.workflow.actions.conditional",
            GroupingIdentifier=condition_id,
            WFControlFlowMode=1,
        ),
        action(
            "is.workflow.actions.showresult",
            Text="This file was not queued. Share the .zip file created by the app's bug reporter.",
        ),
        action("is.workflow.actions.exit"),
        action(
            "is.workflow.actions.conditional",
            GroupingIdentifier=condition_id,
            WFControlFlowMode=2,
        ),
        action(
            "is.workflow.actions.notification",
            WFNotificationActionTitle="MZ Inbox",
            WFNotificationActionBody="Queued for Mac. Your report is saved in iCloud Drive; processing starts when your Mac is available.",
            WFNotificationActionSound=False,
        ),
    ]
    return {
        "WFWorkflowName": name,
        "WFWorkflowClientVersion": "4018.0.4",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {
            "WFWorkflowIconStartColor": DEFAULT_ICON_COLOR,
            "WFWorkflowIconGlyphNumber": DEFAULT_ICON_GLYPH,
        },
        "WFWorkflowTypes": ["ActionExtension"],
        "WFQuickActionSurfaces": [],
        "WFWorkflowInputContentItemClasses": ["WFGenericFileContentItem"],
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowHasShortcutInputVariables": True,
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowActions": actions,
        "WFWorkflowImportQuestions": [
            {
                "ActionIndex": 2,
                "Category": "Parameter",
                "ParameterKey": "WFFolder",
                "Text": "Choose iCloud Drive → MZ Inbox → Incoming once. Reports will save here automatically.",
            }
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--name", default=DEFAULT_NAME, help="Shortcut name; useful for isolated validation.")
    parser.add_argument("--unsigned-only", action="store_true", help="Write the inspectable plist without signing or importing it.")
    args = parser.parse_args()
    if not args.name.strip() or any(char in args.name for char in "/\\\0"):
        parser.error("--name must be a non-empty filename without path separators")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    unsigned = args.output_dir / (args.name + ".unsigned.shortcut")
    unsigned.write_bytes(plistlib.dumps(workflow(args.name), fmt=plistlib.FMT_XML, sort_keys=False))
    print(f"Workflow source: {unsigned}")
    if args.unsigned_only:
        return 0
    shortcuts = shutil.which("shortcuts")
    if shortcuts is None:
        print("Signing requires the Shortcuts command on macOS. The unsigned source was preserved.", file=sys.stderr)
        return 1
    signed = args.output_dir / (args.name + ".shortcut")
    result = subprocess.run(
        [shortcuts, "sign", "--mode", "anyone", "--input", str(unsigned), "--output", str(signed)],
        check=False,
    )
    if result.returncode:
        print("Apple's signing service did not complete. The unsigned source was preserved; rerun to sign.", file=sys.stderr)
        return result.returncode
    if not signed.is_file() or signed.stat().st_size == 0:
        print("Signing did not produce a shortcut file.", file=sys.stderr)
        return 1
    print(f"Importable shortcut: {signed}")
    print("On iPhone, import it and choose iCloud Drive/MZ Inbox/Incoming in the setup question.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
