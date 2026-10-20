#!/usr/bin/env python3
"""A real, disposable SQLite migration exercise. Never connects to a server."""
import argparse
import json
from pathlib import Path
import sqlite3


class MigrationDemo:
    def __init__(self, root):
        self.root = Path(root)
        self.directory = self.root / 'rendered/migrations'
        self.database = self.directory / 'identity.sqlite'

    def status(self):
        if not self.database.exists():
            return {'schema_version': 0, 'accounts': [], 'database': str(self.database)}
        with sqlite3.connect(self.database) as connection:
            version = connection.execute('PRAGMA user_version').fetchone()[0]
            connection.row_factory = sqlite3.Row
            rows = connection.execute('SELECT * FROM accounts').fetchall() if version else []
            return {'schema_version': version, 'accounts': [dict(row) for row in rows],
                    'database': str(self.database)}

    def backup(self, label):
        index = len(list(self.directory.glob(f'identity-{label}-*.sqlite'))) + 1
        destination = self.directory / f'identity-{label}-{index:03}.sqlite'
        with sqlite3.connect(self.database) as source, sqlite3.connect(destination) as target:
            source.backup(target)
        return destination

    def upgrade(self, target):
        if target not in (1, 2):
            raise ValueError('This exercise provides schema versions 1 and 2 only.')
        current = self.status()['schema_version']
        if target < current:
            raise ValueError('Schema downgrade is unsupported; use the explicit backup-restore exercise.')
        self.directory.mkdir(parents=True, exist_ok=True)
        for version in range(current + 1, target + 1):
            if version > 1:
                self.backup(f'before-v{version}')
            scripts = list((self.root / 'local-sources/migrations/identity').glob(f'V{version:03}__*.sql'))
            if len(scripts) != 1:
                raise ValueError(f'Expected exactly one migration for schema {version}.')
            with sqlite3.connect(self.database) as connection:
                try:
                    connection.executescript('BEGIN IMMEDIATE;\n' + scripts[0].read_text()
                                             + f'\nPRAGMA user_version = {version};\nCOMMIT;')
                except sqlite3.Error:
                    connection.rollback()
                    raise
        return self.status()

    def restore(self):
        backups = sorted(self.directory.glob('identity-before-v2-*.sqlite'))
        if not backups:
            raise ValueError('No pre-v2 backup exists. Run init, then upgrade first.')
        self.backup('before-restore')
        with sqlite3.connect(backups[-1]) as source, sqlite3.connect(self.database) as target:
            source.backup(target)
        return self.status()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['status', 'init', 'upgrade', 'restore'])
    parser.add_argument('--to', type=int, default=2, dest='target')
    args = parser.parse_args()
    demo = MigrationDemo(Path(__file__).resolve().parent.parent)
    if args.action == 'status':
        result = demo.status()
    elif args.action == 'init':
        result = demo.upgrade(1)
    elif args.action == 'upgrade':
        result = demo.upgrade(args.target)
    else:
        result = demo.restore()
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, sqlite3.Error) as error:
        raise SystemExit(f'FAIL: {error}')
