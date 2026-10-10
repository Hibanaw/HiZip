"""Real RAR regression fixtures; no installed rar/unrar executable is needed."""
import concurrent.futures
import ctypes
import os
import pathlib
import shutil
import tempfile
import unittest

from archive_engine_test import lib, call

FIXTURES = pathlib.Path(__file__).resolve().parents[1] / 'fixtures' / 'rar'
lib.hz_configure_security.argtypes = [ctypes.c_char_p] * 3
lib.hz_verify.restype = ctypes.c_void_p
lib.hz_verify.argtypes = [ctypes.c_char_p]
lib.hz_control_create.restype = ctypes.c_void_p
lib.hz_control_bind.argtypes = lib.hz_control_free.argtypes = [ctypes.c_void_p]
lib.hz_control_set.argtypes = [ctypes.c_void_p, ctypes.c_int]
lib.hz_set_read_only.restype = ctypes.c_void_p
lib.hz_set_read_only.argtypes = [ctypes.c_char_p, ctypes.c_int]


class RarEngineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        lib.hz_configure_security(b'', b'none', b'deflate')

    def tearDown(self):
        lib.hz_control_bind(None)
        lib.hz_configure_security(b'', b'none', b'deflate')
        self.tmp.cleanup()

    def fixture(self, name):
        return FIXTURES / ('test_read_format_' + name + '.rar')

    def batch(self, archive, names, limits=None, progress=None):
        outputs = [self.root / ('out-' + str(i)) for i in range(len(names))]
        strings = ctypes.c_char_p * len(names)
        sizes = ctypes.c_int64 * len(names)
        result = call('hz_extract_batch_detailed', archive,
                      strings(*(name.encode() for name in names)),
                      strings(*(os.fsencode(path) for path in outputs)),
                      sizes(*(limits or [2**63 - 1] * len(names))), len(names),
                      2**63 - 1, progress)
        return result, outputs

    def test_capabilities_and_read_only(self):
        capabilities = call('hz_capabilities')
        for key in ['rarRead', 'rarEncryption', 'rarVolumes']:
            self.assertTrue(capabilities[key])
        self.assertNotIn('rar', capabilities['writableFormats'])
        self.assertFalse(call('hz_list', self.fixture('rar'))['writable'])

    def test_password_and_header_encryption_rar4_and_rar5(self):
        for version in [4, 5]:
            for variant in ['encrypted_filenames', 'solid_encrypted_filenames']:
                archive = self.fixture(f'rar{version}_{variant}')
                lib.hz_configure_security(b'', b'none', b'deflate')
                self.assertIn('password', call('hz_list', archive)['error'])
                lib.hz_configure_security(b'wrong', b'none', b'deflate')
                self.assertIn('error', call('hz_verify', archive))
                lib.hz_configure_security(b'password', b'none', b'deflate')
                entries = call('hz_list', archive)['entries']
                self.assertEqual([e['path'] for e in entries], ['a.txt', 'b.txt', 'c.txt', 'd.txt'])
                self.assertTrue(all(e['encrypted'] for e in entries))
                self.assertEqual(call('hz_verify', archive)['bytes'], 72)
                output = self.root / f'{version}-{variant}'
                self.assertTrue(call('hz_extract', archive, 'd.txt', output, 18)['ok'])
                self.assertEqual(output.read_bytes(), b'This is from d.txt')

    def test_solid_data_encryption_and_batch_progress(self):
        callback_type = ctypes.CFUNCTYPE(None, ctypes.c_int32, ctypes.c_int64, ctypes.c_int32, ctypes.c_int64, ctypes.c_int64)
        events = []
        progress = callback_type(lambda *args: events.append(args))
        for version in [4, 5]:
            archive = self.fixture(f'rar{version}_solid_encrypted')
            lib.hz_configure_security(b'', b'none', b'deflate')
            self.assertTrue(all(e['encrypted'] for e in call('hz_list', archive)['entries']))
            self.assertIn('error', call('hz_verify', archive))
            lib.hz_configure_security(b'password', b'none', b'deflate')
            result, outputs = self.batch(archive, ['d.txt', 'a.txt'], progress=progress)
            self.assertTrue(result['ok'], result)
            self.assertEqual(outputs[0].read_bytes(), b'This is from d.txt')
            self.assertEqual(outputs[1].read_bytes(), b'This is from a.txt')
            self.assertEqual(events[-1][:2], (2, 36))
            for output in outputs:
                output.unlink()

    def test_unicode_and_content_signature_dispatch(self):
        archive = self.root / '中文 archive.data'
        shutil.copyfile(self.fixture('rar5_unicode'), archive)
        entries = call('hz_list', archive)['entries']
        self.assertEqual(entries[0]['path'], '👋🌎.txt')
        output = self.root / '中文 📄.txt'
        self.assertTrue(call('hz_extract', archive, '👋🌎.txt', output, 13)['ok'])
        self.assertEqual(output.stat().st_size, 13)
        self.assertFalse(entries[1]['regular'])  # Hard links must not become empty files.

    def test_real_multivolume_and_missing_volume_rollback(self):
        for fixture in FIXTURES.glob('test_read_format_rar5_multiarchive_solid.part*.rar'):
            shutil.copyfile(fixture, self.root / fixture.name)
        first = self.root / 'test_read_format_rar5_multiarchive_solid.part01.rar'
        self.assertEqual(len(call('hz_list', first)['entries']), 9)
        self.assertEqual(call('hz_verify', first)['bytes'], 117398)
        result, outputs = self.batch(first, ['test6.bin', 'cebula.txt'])
        self.assertTrue(result['ok'], result)
        self.assertEqual([p.stat().st_size for p in outputs], [4096, 814])
        for output in outputs:
            output.unlink()
        (self.root / 'test_read_format_rar5_multiarchive_solid.part04.rar').unlink()
        self.assertIn('Missing RAR volume', call('hz_list', first)['error'])
        result, outputs = self.batch(first, ['cebula.txt'])
        self.assertIn('Missing RAR volume', result['error'])
        self.assertFalse(any(p.exists() for p in outputs))

    def test_size_limit_failure_removes_all_batch_outputs(self):
        lib.hz_configure_security(b'password', b'none', b'deflate')
        result, outputs = self.batch(self.fixture('rar5_solid_encrypted'), ['a.txt', 'd.txt'], [18, 17])
        self.assertIn('limit', result['error'])
        self.assertFalse(any(p.exists() for p in outputs))

    def test_rar4_legacy_volume_names(self):
        parts = sorted(FIXTURES.glob('test_read_format_rar_multivolume.part*.rar'))
        self.assertEqual(len(parts), 4)
        for i, fixture in enumerate(parts):
            shutil.copyfile(fixture, self.root / ('legacy.rar' if i == 0 else f'legacy.r{i-1:02}'))
        archive = self.root / 'legacy.rar'
        self.assertEqual(len(call('hz_list', archive)['entries']), 7)
        output = self.root / 'small.txt'
        self.assertTrue(call('hz_extract', archive, 'testdir/test.txt', output, 20)['ok'])
        self.assertEqual(output.stat().st_size, 20)
        (self.root / 'legacy.r01').unlink()
        self.assertIn('Missing RAR volume', call('hz_list', archive)['error'])

    def test_never_overwrites_existing_files_or_follows_output_links(self):
        archive = self.fixture('rar5_unicode')
        output = self.root / 'existing'
        output.write_bytes(b'keep')
        self.assertIn('error', call('hz_extract', archive, '👋🌎.txt', output, 13))
        self.assertEqual(output.read_bytes(), b'keep')
        if os.name != 'nt':
            link = self.root / 'link'
            link.symlink_to(output)
            self.assertIn('error', call('hz_extract', archive, '👋🌎.txt', link, 13))
            self.assertTrue(link.is_symlink())
            self.assertEqual(output.read_bytes(), b'keep')
        self.assertIn('error', call('hz_extract', archive, '../unsafe', self.root / 'unsafe', 13))

    def test_cancellation_removes_outputs(self):
        control = lib.hz_control_create()
        callback_type = ctypes.CFUNCTYPE(None, ctypes.c_int32, ctypes.c_int64, ctypes.c_int32, ctypes.c_int64, ctypes.c_int64)
        progress = callback_type(lambda *args: lib.hz_control_set(control, 2) if args[1] > 0 else None)
        lib.hz_control_bind(control)
        try:
            result, outputs = self.batch(self.fixture('rar5_multiple_files_solid'), ['test1.bin', 'test4.bin'], progress=progress)
            self.assertEqual(result['error'], 'Operation cancelled')
            self.assertFalse(any(p.exists() for p in outputs))
        finally:
            lib.hz_control_bind(None)
            lib.hz_control_free(control)

    def test_concurrent_passwords_do_not_share_decoder_state(self):
        archive = self.fixture('rar5_solid_encrypted_filenames')
        def verify(password):
            lib.hz_configure_security(password, b'none', b'deflate')
            try:
                return call('hz_verify', archive).get('ok', False)
            finally:
                lib.hz_configure_security(b'', b'none', b'deflate')
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            self.assertEqual(list(pool.map(verify, [b'password', b'wrong'] * 8)), [True, False] * 8)

    def test_read_only_permissions_and_cleanup_restore(self):
        path = self.root / 'file'
        path.write_bytes(b'data')
        self.assertTrue(call('hz_set_read_only', path, 1)['ok'])
        if os.name != 'nt':
            self.assertEqual(path.stat().st_mode & 0o222, 0)
            with self.assertRaises(PermissionError):
                path.write_bytes(b'changed')
        self.assertTrue(call('hz_set_read_only', path, 0)['ok'])
        path.write_bytes(b'changed')


if __name__ == '__main__':
    unittest.main()
