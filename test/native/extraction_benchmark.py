"""Reproducible native extraction benchmark; no UI interaction.
HIZIP_NATIVE_LIBRARY=/tmp/libhizip_native.dylib python3 test/native/extraction_benchmark.py
"""
import concurrent.futures, ctypes, hashlib, json, os, pathlib, random, statistics, tempfile, time, zipfile
lib = ctypes.CDLL(os.environ.get('HIZIP_NATIVE_LIBRARY', '/tmp/libhizip_native.dylib'))
lib.hz_extract.restype = lib.hz_extract_batch.restype = ctypes.c_void_p
lib.hz_extract.argtypes = [ctypes.c_char_p] * 3 + [ctypes.c_int64]
lib.hz_extract_batch.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_int64), ctypes.c_int, ctypes.c_int64, ctypes.c_void_p]
lib.hz_free.argtypes = [ctypes.c_void_p]
def check(ptr):
    try:
        result = json.loads(ctypes.string_at(ptr))
        if 'error' in result: raise RuntimeError(result['error'])
    finally: lib.hz_free(ptr)
def batch(archive, names, outputs, size):
    count = len(names)
    check(lib.hz_extract_batch(os.fsencode(archive),
        (ctypes.c_char_p * count)(*[os.fsencode(n) for n in names]),
        (ctypes.c_char_p * count)(*[os.fsencode(o) for o in outputs]),
        (ctypes.c_int64 * count)(*[size] * count), count, count * size, None))
def run(archive, names, payload, mode, root):
    outputs = [root / str(i) for i in range(len(names))]
    started = time.perf_counter()
    if mode == 'old_per_file':
        for name, output in zip(names, outputs):
            check(lib.hz_extract(os.fsencode(archive), os.fsencode(name), os.fsencode(output), len(payload)))
    elif mode == 'batch_1': batch(archive, names, outputs, len(payload))
    else:
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            tasks = [pool.submit(batch, archive, names[i::4], outputs[i::4], len(payload)) for i in range(4)]
            for task in tasks: task.result()
    elapsed = time.perf_counter() - started
    expected = hashlib.sha256(payload).digest()
    for output in outputs:
        if hashlib.sha256(output.read_bytes()).digest() != expected: raise AssertionError(output)
    return elapsed
results = {}
with tempfile.TemporaryDirectory(prefix='hizip-benchmark-') as tmp:
    base = pathlib.Path(tmp)
    cases = [('small_files', 400, b'hello world\n' * 10),
             ('large_files', 32, random.Random(42).randbytes(16384) * 512)]
    for case, count, payload in cases:
        archive = base / (case + '.zip'); names = ['file-%05d.bin' % i for i in range(count)]
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
            for name in names: z.writestr(name, payload)
        timings = {}
        for mode in ['old_per_file', 'batch_1', 'batch_4']:
            samples = []
            for repeat in range(3):
                with tempfile.TemporaryDirectory(dir=base) as out:
                    samples.append(run(archive, names, payload, mode, pathlib.Path(out)))
            timings[mode] = round(statistics.median(samples), 4)
        results[case] = {'files': count, 'uncompressed_bytes': count * len(payload),
                         'seconds_median_of_3': timings,
                         'old_to_parallel_speedup': round(timings['old_per_file'] / timings['batch_4'], 2),
                         'batch_parallel_speedup': round(timings['batch_1'] / timings['batch_4'], 2)}
print(json.dumps(results, indent=2), flush=True)
