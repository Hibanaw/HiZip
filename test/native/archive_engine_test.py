"""End-to-end native ABI checks. Build the shared library before running."""
import ctypes, io, json, os, pathlib, subprocess, tarfile, tempfile, unittest, zipfile
LIBRARY = os.environ.get('HIZIP_NATIVE_LIBRARY', '/tmp/libhizip_native.dylib')
lib = ctypes.CDLL(LIBRARY)
for name in ['hz_list', 'hz_extract', 'hz_replace', 'hz_create', 'hz_extract_batch', 'hz_extract_batch_detailed']:
    getattr(lib, name).restype = ctypes.c_void_p
lib.hz_list.argtypes = [ctypes.c_char_p]
lib.hz_extract.argtypes = [ctypes.c_char_p] * 3 + [ctypes.c_int64]
lib.hz_replace.argtypes = [ctypes.c_char_p] * 4
lib.hz_create.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_char_p), ctypes.c_int]
lib.hz_extract_batch.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_int64), ctypes.c_int, ctypes.c_int64, ctypes.c_void_p]
lib.hz_extract_batch_detailed.argtypes = lib.hz_extract_batch.argtypes
lib.hz_free.argtypes = [ctypes.c_void_p]
def call(name, *args):
    args = [os.fsencode(a) if isinstance(a, (str, pathlib.Path)) else a for a in args]
    ptr = getattr(lib, name)(*args)
    try: return json.loads(ctypes.string_at(ptr).decode())
    finally: lib.hz_free(ptr)
if os.environ.get('HIZIP_TEST_C_LOCALE'):
    ctypes.CDLL(None).setlocale(0, b'C')

lib.hz_update.restype = ctypes.c_void_p
lib.hz_update.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_char_p), ctypes.c_int, ctypes.POINTER(ctypes.c_char_p), ctypes.c_int]

class NativeArchiveTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = pathlib.Path(self.tmp.name)
        self.zip = self.root / 'sample.zip'
        with zipfile.ZipFile(self.zip, 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('资料/hello.txt', 'Hello 世界'); z.writestr('unchanged.bin', bytes(range(256))); z.writestr('empty/', '')
    def tearDown(self): self.tmp.cleanup()
    def test_list_and_utf8_extract(self):
        r = call('hz_list', self.zip); self.assertTrue(r['writable']); self.assertEqual(len(r['entries']), 3)
        output = self.root / 'out'; self.assertTrue(call('hz_extract', self.zip, '资料/hello.txt', output, 1024)['ok']); self.assertEqual(output.read_text(encoding='utf-8'), 'Hello 世界')
    def test_list_large_archives_without_entry_count_limit(self):
        for count in [1001, 100001]:
            with self.subTest(count=count):
                with zipfile.ZipFile(self.zip, 'w') as archive:
                    for index in range(count):
                        archive.writestr(f'files/{index}.txt', b'')
                result = call('hz_list', self.zip)
                self.assertTrue(result['writable'])
                self.assertEqual(len(result['entries']), count)
                self.assertEqual(result['entries'][-1]['path'], f'files/{count - 1}.txt')
                output = self.root / f'last-{count}'
                self.assertTrue(call('hz_extract', self.zip, f'files/{count - 1}.txt', output, 0)['ok'])
                self.assertEqual(output.read_bytes(), b'')
    def test_large_extraction_batch_reaches_entry_validation(self):
        count = 100001
        names = (ctypes.c_char_p * count)(*([b'../unsafe'] * count))
        outputs = (ctypes.c_char_p * count)(*([os.fsencode(self.root / 'out')] * count))
        limits = (ctypes.c_int64 * count)()
        result = call('hz_extract_batch', self.zip, names, outputs, limits, count, 0, None)
        self.assertEqual(result['error'], 'Unsafe archive path or invalid size limit')
        self.assertFalse((self.root / 'out').exists())
    def test_update_without_removal_count_limit(self):
        count = 100001
        removed = (ctypes.c_char_p * count)(*([b'unchanged.bin'] * count))
        output = self.root / 'updated.zip'
        self.assertTrue(call('hz_update', self.zip, output, None, None, 0, removed, count)['ok'])
        with zipfile.ZipFile(output) as archive:
            self.assertEqual(archive.namelist(), ['资料/hello.txt', 'empty/'])
            self.assertIsNone(archive.testzip())
    def test_large_update_batch_reaches_entry_validation(self):
        count = 100001
        paths = (ctypes.c_char_p * count)()
        names = (ctypes.c_char_p * count)(*([b'../unsafe'] * count))
        output = self.root / 'updated.zip'
        result = call('hz_update', self.zip, output, paths, names, count, None, 0)
        self.assertEqual(result['error'], 'Unsafe new entry path')
        self.assertFalse(output.exists())
    def test_replace_preserves_other_entries(self):
        replacement = self.root / 'new'; replacement.write_text('Updated 世界', encoding='utf-8')
        output = self.root / 'updated.zip'; self.assertTrue(call('hz_replace', self.zip, '资料/hello.txt', replacement, output)['ok'])
        with zipfile.ZipFile(output) as z:
            self.assertEqual(z.read('资料/hello.txt').decode(), 'Updated 世界'); self.assertEqual(z.read('unchanged.bin'), bytes(range(256))); self.assertIsNone(z.testzip())
        with zipfile.ZipFile(self.zip) as z: self.assertEqual(z.read('资料/hello.txt').decode(), 'Hello 世界')
    def test_traversal_and_size_limit(self):
        evil = self.root / 'evil.zip'
        with zipfile.ZipFile(evil, 'w') as z: z.writestr('../outside.txt', 'evil')
        self.assertFalse(call('hz_list', evil)['entries'][0]['safe'])
        output = self.root / 'out'; self.assertIn('error', call('hz_extract', evil, '../outside.txt', output, 1024)); self.assertFalse(output.exists())
        self.assertIn('error', call('hz_extract', self.zip, '资料/hello.txt', output, 2)); self.assertFalse(output.exists())
    def test_tar_and_symlink(self):
        tar = self.root / 'sample.tar.gz'
        with tarfile.open(tar, 'w:gz') as t:
            entry = tarfile.TarInfo('note.txt'); data = b'hello'; entry.size = len(data); t.addfile(entry, io.BytesIO(data))
            link = tarfile.TarInfo('link'); link.type = tarfile.SYMTYPE; link.linkname = '/etc/passwd'; t.addfile(link)
        result = call('hz_list', tar); self.assertFalse(result['writable']); self.assertFalse(result['entries'][1]['regular'])
        out = self.root / 'out'; self.assertIn('error', call('hz_extract', tar, 'link', out, 1024)); self.assertTrue(call('hz_extract', tar, 'note.txt', out, 1024)['ok'])
        replacement = self.root / 'new'; replacement.write_text('replacement', encoding='utf-8'); self.assertIn('error', call('hz_replace', tar, 'note.txt', replacement, self.root / 'bad.zip'))
    def test_additional_formats_roundtrip_and_update(self):
        source = self.root / 'source'; source.write_bytes(b'original')
        replacement = self.root / 'replacement'; replacement.write_bytes(b'changed')
        for ext in ['7z', 'tar', 'tar.gz', 'tar.bz2', 'tar.xz', 'tar.lzma',
                    'tar.zst', 'tar.lz4', 'tar.lzip', 'tar.Z', 'cpio', 'ar']:
            with self.subTest(format=ext):
                archive = self.root / ('created.' + ext)
                paths = (ctypes.c_char_p * 1)(os.fsencode(source))
                entry_name = b'test.txt' if ext == 'ar' else '资料/测试.txt'.encode()
                names = (ctypes.c_char_p * 1)(entry_name)
                self.assertTrue(call('hz_create', archive, paths, names, 1).get('ok'))
                info = call('hz_list', archive); self.assertTrue(info.get('writable'), info)
                output = self.root / ('extract-' + ext)
                self.assertTrue(call('hz_extract', archive, entry_name, output, 1024).get('ok'))
                self.assertEqual(output.read_bytes(), b'original')
                updated = self.root / ('updated.' + ext)
                self.assertTrue(call('hz_replace', archive, entry_name, replacement, updated).get('ok'))
                self.assertEqual(call('hz_list', updated)['format'], info['format'])
                final = self.root / ('updated-data-' + ext)
                self.assertTrue(call('hz_extract', updated, entry_name, final, 1024).get('ok'))
                self.assertEqual(final.read_bytes(), b'changed')
                appended = self.root / ('appended.' + ext)
                extra_names = (ctypes.c_char_p * 1)(b'new.txt')
                self.assertTrue(call('hz_update', updated, appended, paths, extra_names, 1, None, 0).get('ok'))
                self.assertEqual(len(call('hz_list', appended)['entries']), 2)

    def test_single_file_compression_roundtrip(self):
        source = self.root / 'single.txt'; source.write_bytes(b'stream content')
        paths = (ctypes.c_char_p * 1)(os.fsencode(source)); names = (ctypes.c_char_p * 1)(b'single.txt')
        for ext in ['gz', 'bz2', 'xz', 'lzma', 'zst', 'lz4', 'lzip', 'Z']:
            with self.subTest(format=ext):
                archive = self.root / ('single.txt.' + ext)
                self.assertTrue(call('hz_create', archive, paths, names, 1).get('ok'))
                info = call('hz_list', archive)
                self.assertTrue(info.get('writable'), info)
                self.assertEqual(info['entries'][0]['path'], 'single.txt')
                self.assertEqual(info['entries'][0]['size'], len(b'stream content'))
                out = self.root / ('stream-' + ext)
                self.assertTrue(call('hz_extract', archive, 'single.txt', out, 1024).get('ok'))
                self.assertEqual(out.read_bytes(), b'stream content')
                stage = self.root / ('staged-' + ext); stage.mkdir()
                changed = stage / ('single.txt.' + ext)
                self.assertTrue(call('hz_replace', archive, 'single.txt', source, changed).get('ok'))
                self.assertEqual(call('hz_list', changed)['entries'][0]['size'], len(b'stream content'))

    def test_create_and_invalid_archive(self):
        source = self.root / 'source'; source.write_bytes(b'created')
        paths = (ctypes.c_char_p * 1)(os.fsencode(source)); names = (ctypes.c_char_p * 1)('测试.txt'.encode())
        output = self.root / 'new.zip'; self.assertTrue(call('hz_create', output, paths, names, 1)['ok'])
        with zipfile.ZipFile(output) as z: self.assertEqual(z.read('测试.txt'), b'created')
        bad = self.root / 'invalid.zip'; bad.write_bytes(b'not an archive'); self.assertIn('error', call('hz_list', bad))
    def test_encrypted_zip_is_read_only(self):
        source = self.root / 'secret.txt'; source.write_text('secret', encoding='utf-8'); encrypted = self.root / 'encrypted.zip'
        subprocess.run(['/usr/bin/zip', '-j', '-P', 'password', str(encrypted), str(source)], check=True, capture_output=True)
        result = call('hz_list', encrypted); self.assertFalse(result['writable']); self.assertTrue(result['entries'][0]['encrypted'])
    def test_existing_output_is_never_deleted(self):
        output = self.root / 'existing'; output.write_text('preserve me', encoding='utf-8')
        self.assertIn('error', call('hz_extract', self.zip, 'missing', output, 1024))
        self.assertEqual(output.read_text(encoding='utf-8'), 'preserve me')
    def test_missing_entry_does_not_create_output(self):
        output = self.root / 'out'; self.assertIn('error', call('hz_extract', self.zip, 'missing', output, 1024)); self.assertFalse(output.exists())
    def batch(self, names, outputs, limits, total):
        n = len(names)
        return call('hz_extract_batch', self.zip,
            (ctypes.c_char_p * n)(*[os.fsencode(v) for v in names]),
            (ctypes.c_char_p * n)(*[os.fsencode(v) for v in outputs]),
            (ctypes.c_int64 * n)(*limits), n, total, None)
    def test_detailed_progress_reports_bytes_inside_large_file(self):
        payload = b'01234567' * (256 * 1024)
        with zipfile.ZipFile(self.zip, 'w', zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('资料/large.bin', payload)
            archive.writestr('a.bin', b'end')
        events = []
        callback_type = ctypes.CFUNCTYPE(None, ctypes.c_int32, ctypes.c_int64, ctypes.c_int32, ctypes.c_int64, ctypes.c_int64)
        callback = callback_type(lambda *values: events.append(values))
        names = (ctypes.c_char_p * 2)('资料/large.bin'.encode(), b'a.bin')
        outputs = (ctypes.c_char_p * 2)(os.fsencode(self.root / 'large'), os.fsencode(self.root / 'small'))
        limits = (ctypes.c_int64 * 2)(len(payload), 3)
        result = call('hz_extract_batch_detailed', self.zip, names, outputs, limits, 2, len(payload) + 3, callback)
        self.assertTrue(result['ok'])
        self.assertTrue(any(done == 0 and index == 0 and 0 < current < size for done, total, index, current, size in events))
        self.assertEqual(events[-1], (2, len(payload) + 3, 1, 3, 3))
        self.assertEqual([e[1] for e in events], sorted(e[1] for e in events))
        self.assertEqual((self.root / 'large').read_bytes(), payload)
    def test_batch_extract_utf8_and_binary(self):
        outputs = [self.root / 'a', self.root / 'b']
        result = self.batch(['资料/hello.txt', 'unchanged.bin'], outputs, [100, 256], 356)
        self.assertTrue(result['ok'])
        self.assertEqual(result['files'], 2)
        self.assertEqual(result['bytes'], len('Hello 世界'.encode()) + 256)
        self.assertEqual(outputs[0].read_text(), 'Hello 世界')
        self.assertEqual(outputs[1].read_bytes(), bytes(range(256)))
    def test_batch_aggregate_limit_removes_partial_outputs(self):
        outputs = [self.root / 'a', self.root / 'b']
        result = self.batch(['资料/hello.txt', 'unchanged.bin'], outputs, [100, 256], 260)
        self.assertIn('error', result)
        self.assertTrue(all(not f.exists() for f in outputs))
    def test_batch_failure_preserves_existing_output(self):
        outputs = [self.root / 'a', self.root / 'b']
        outputs[1].write_bytes(b'keep')
        self.assertIn('error', self.batch(['资料/hello.txt', 'unchanged.bin'], outputs, [100, 256], 356))
        self.assertFalse(outputs[0].exists())
        self.assertEqual(outputs[1].read_bytes(), b'keep')
    def test_batch_missing_or_unsafe_target_rolls_back(self):
        output = self.root / 'a'
        self.assertIn('error', self.batch(['资料/hello.txt', 'missing'], [output, self.root/'b'], [100, 100], 200))
        self.assertFalse(output.exists())
        self.assertIn('error', self.batch(['../outside'], [output], [100], 100))
        self.assertFalse(output.exists())

if __name__ == '__main__': unittest.main(verbosity=2)
