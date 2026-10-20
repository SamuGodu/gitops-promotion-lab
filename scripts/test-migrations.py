#!/usr/bin/env python3
from pathlib import Path
import shutil
import sqlite3
import tempfile
import unittest
from importlib.util import spec_from_file_location, module_from_spec

root = Path(__file__).resolve().parent.parent
spec = spec_from_file_location('migration_demo', root / 'scripts/migrate-demo.py')
module = module_from_spec(spec)
spec.loader.exec_module(module)


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='migration-practice-')
        self.directory = Path(self.temp.name)
        shutil.copytree(root / 'local-sources/migrations', self.directory / 'local-sources/migrations')
        self.demo = module.MigrationDemo(self.directory)

    def tearDown(self):
        self.temp.cleanup()

    def test_upgrade_preserves_account_and_adds_column(self):
        old = self.demo.upgrade(1)
        new = self.demo.upgrade(2)
        self.assertEqual(old['accounts'][0]['name'], new['accounts'][0]['name'])
        self.assertEqual(new['accounts'][0]['email'], 'demo@example.invalid')
        self.assertEqual(new['schema_version'], 2)

    def test_restore_recovers_pre_migration_schema(self):
        self.demo.upgrade(1)
        self.demo.upgrade(2)
        restored = self.demo.restore()
        self.assertEqual(restored['schema_version'], 1)
        self.assertNotIn('email', restored['accounts'][0])
        self.assertTrue(list(self.demo.directory.glob('identity-before-restore-*.sqlite')))

    def test_failed_migration_rolls_back_changes(self):
        self.demo.upgrade(1)
        script = self.directory / 'local-sources/migrations/identity/V002__email.sql'
        script.write_text('ALTER TABLE accounts ADD COLUMN email TEXT;\nINVALID SQL;')
        with self.assertRaises(sqlite3.Error):
            self.demo.upgrade(2)
        status = self.demo.status()
        self.assertEqual(status['schema_version'], 1)
        self.assertNotIn('email', status['accounts'][0])

    def test_image_style_version_revert_is_not_schema_downgrade(self):
        self.demo.upgrade(2)
        with self.assertRaisesRegex(ValueError, 'downgrade'):
            self.demo.upgrade(1)
        self.assertEqual(self.demo.status()['schema_version'], 2)


if __name__ == '__main__':
    unittest.main()
