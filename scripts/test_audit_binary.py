import contextlib
import importlib.util
import io
from pathlib import Path
import plistlib
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('audit_binary', Path(__file__).with_name('audit_binary.py'))
audit_binary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit_binary)


class BinaryAuditTests(unittest.TestCase):
    def test_app_names_and_core_configuration_are_not_live_sdk_linkage(self):
        symbols = '\n'.join([
            '00000000 T _$s8Roamline25SentryEventPrivacyScrubberV',
            '00000000 T _$s8Roamline22CommerceServiceFactoryO12isRevenueCatSbvp',
            '00000000 T _$s8Roamline30localizedFirebaseAnalyticsKeySSvp',
            '00000000 S _OBJC_CLASS_$_FIRAnalyticsConfiguration',
            '00000000 S _OBJC_METACLASS_$_FIRAnalyticsConfiguration',
        ])
        self.assertEqual(audit_binary.sdk_evidence(symbols, [
            'SentryEventPrivacyScrubber.swift', 'RevenueCatProducts.storekit',
            'en.lproj/Localizable.strings',
        ]), {})

    def test_real_swift_modules_are_detected_independently(self):
        symbols = '00000000 T _$s10RevenueCat9PurchasesC\n00000000 T _$s6Sentry5EventC'
        self.assertEqual(set(audit_binary.sdk_evidence(symbols, [])), {'RevenueCat', 'Sentry'})

    def test_exact_objective_c_analytics_and_sentry_classes_are_detected(self):
        for sdk, name in [('FirebaseAnalytics', 'FIRAnalytics'),
                          ('GoogleAppMeasurement', 'APMAnalytics'), ('Sentry', 'SentrySDK')]:
            with self.subTest(sdk=sdk):
                self.assertIn(sdk, audit_binary.sdk_evidence('00000000 S _OBJC_CLASS_$_' + name, []))
                self.assertIn(sdk, audit_binary.sdk_evidence('00000000 t +[' + name + ' start]', []))

    def test_vendor_object_paths_and_embedded_resources_are_detected(self):
        symbols = '00000000 - 00 0001 OSO /Build/RevenueCat.build/Objects/Purchases.o\n' \
                  '00000000 - 00 0001 OSO /Build/Sentry.build/Objects/SentrySDK.o'
        paths = ['Frameworks/FirebaseAnalytics.framework/FirebaseAnalytics',
                 'FirebaseAnalytics_FirebaseAnalytics.bundle/Info.plist',
                 'GoogleAppMeasurement_GoogleAppMeasurement.bundle/Info.plist']
        self.assertEqual(set(audit_binary.sdk_evidence(symbols, paths)),
                         {'RevenueCat', 'Sentry', 'FirebaseAnalytics', 'GoogleAppMeasurement'})

    def test_local_cli_rejects_live_linkage_and_requires_real_pulse(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.bundle(Path(directory) / 'Fixture.app')
            for symbols, status in [
                ('00000000 T _$s5Pulse11LoggerStoreC', 0),
                ('00000000 T _$s8Roamline14PulseLogEngineV', 1),
                ('00000000 T _$s5Pulse11LoggerStoreC\n00000000 T _$s6Sentry5EventC', 1),
            ]:
                with self.subTest(symbols=symbols), \
                        patch.object(audit_binary.subprocess, 'run', return_value=SimpleNamespace(stdout=symbols)), \
                        contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(audit_binary.main([str(app), '--local']), status)

    def test_audit_includes_debug_dylibs_and_embedded_extension_executables(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.bundle(Path(directory) / 'Fixture.app')
            (app / 'Fixture.debug.dylib').touch()
            self.bundle(app / 'PlugIns' / 'Activity.appex')
            with patch.object(audit_binary.subprocess, 'run', return_value=SimpleNamespace(stdout='')) as nm:
                result = audit_binary.audit(app, local=True)
            self.assertEqual(set(result['inspected_executables']), {
                'Fixture', 'Fixture.debug.dylib', 'PlugIns/Activity.appex/Activity'
            })
            self.assertEqual(nm.call_count, 3)

    @staticmethod
    def bundle(path):
        path.mkdir(parents=True)
        (path / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': path.stem}))
        (path / path.stem).touch()
        return path

    def test_native_macos_bundle_and_debug_dylib_are_inspected(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'Fixture.app'
            binaries = app / 'Contents/MacOS'
            binaries.mkdir(parents=True)
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': 'Fixture'}))
            (binaries / 'Fixture').touch()
            (binaries / 'Fixture.debug.dylib').touch()
            with patch.object(audit_binary.subprocess, 'run', return_value=SimpleNamespace(stdout='')):
                result = audit_binary.audit(app, local=True)
            self.assertEqual(set(result['inspected_executables']), {
                'Contents/MacOS/Fixture', 'Contents/MacOS/Fixture.debug.dylib'
            })


if __name__ == '__main__':
    unittest.main()
