const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../..');
const ts = require(path.join(root,
  '.toolchains/command-line-tools/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'hizip-external-test-'));
const cacheDir = path.join(temporary, 'cache');
const filesDir = path.join(temporary, 'files');
fs.mkdirSync(cacheDir); fs.mkdirSync(filesDir);
const resolve = value => value.startsWith('file://') ? decodeURIComponent(new URL(value).pathname) : value;
const descriptors = new Map();
const mode = { READ_ONLY: fs.constants.O_RDONLY, READ_WRITE: fs.constants.O_RDWR, CREATE: fs.constants.O_CREAT };
let copyHook;
const io = {
  OpenMode: mode, WhenceType: { SEEK_SET: 0 },
  open: async (value, flags) => {
    const fd = fs.openSync(resolve(value), flags);
    descriptors.set(fd, 0); return { fd };
  },
  close: async file => { fs.closeSync(file.fd); descriptors.delete(file.fd); },
  stat: async fd => fs.fstatSync(fd, { bigint: true }),
  read: async (fd, buffer, options) => fs.readSync(fd, new Uint8Array(buffer), 0, options.length, options.offset),
  access: async value => fs.existsSync(resolve(value)),
  mkdir: async value => fs.mkdirSync(value),
  mkdtemp: async prefix => {
    assert.ok(prefix.endsWith('XXXXXX'), 'HarmonyOS mkdtemp requires a six-X template');
    return fs.mkdtempSync(prefix.slice(0, -6));
  },
  rmdir: async value => fs.rmSync(value, { recursive: true }),
  unlink: async value => fs.unlinkSync(value),
  rename: async (from, to) => fs.renameSync(from, to),
  lseek: (fd, position) => descriptors.set(fd, position),
  fsync: async fd => fs.fsyncSync(fd),
  copy: async (from, to) => fs.cpSync(resolve(from), path.join(resolve(to), path.basename(resolve(from))), { recursive: true }),
  copyFile: async (from, to) => {
    if (typeof from === 'string') fs.copyFileSync(from, to);
    else {
      const buffer = Buffer.alloc(Number(fs.fstatSync(from).size));
      fs.readSync(from, buffer, 0, buffer.length, descriptors.get(from));
      fs.writeSync(to, buffer);
    }
    if (copyHook) { const hook = copyHook; copyHook = undefined; hook(); }
  },
};
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,
  'packages/nativeapi/ohos/src/main/ets/ExternalEdits.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 },
}).outputText, {
  exports: exportsObject,
  require: name => {
    if (name === '@kit.CoreFileKit') return {
      fileIo: io,
      fileUri: { getUriFromPath: value => `file://com.hibanaw.hizip${encodeURI(value)}`,
        FileUri: class { constructor(uri) { this.path = resolve(uri); } } },
    };
    if (name === '@kit.CryptoArchitectureKit') return { cryptoFramework: {
      createMd: () => { const hash = crypto.createHash('sha256'); return {
        update: async blob => hash.update(blob.data), digest: async () => ({ data: hash.digest() }),
      }; },
    } };
    return {};
  },
});
(async () => {
  const edits = new exportsObject.ExternalEdits(() => ({ cacheDir, filesDir }));
  const local = path.join(cacheDir, '中文 document.docx');
  fs.writeFileSync(local, 'original document');
  const [uri, concurrentUri] = await Promise.all([edits.prepare(local), edits.prepare(local)]);
  assert.equal(concurrentUri, uri);
  assert.ok(uri.startsWith(`file://com.hibanaw.hizip${filesDir}/hizip-edit-`));
  assert.equal(path.basename(resolve(uri)), '中文 document.docx');
  assert.equal(fs.readFileSync(resolve(uri), 'utf8'), 'original document');
  assert.equal(await edits.synchronize(local), false);
  for (const content of ['saved through replacement', 'saved again']) {
    const pending = resolve(uri) + '.tmp';
    fs.writeFileSync(pending, content); fs.renameSync(pending, resolve(uri));
    assert.equal(await edits.synchronize(local), true);
    assert.equal(fs.readFileSync(local, 'utf8'), content);
    assert.equal(await edits.synchronize(local), false);
    assert.equal(await edits.prepare(local), uri);
    assert.equal(fs.readFileSync(resolve(uri), 'utf8'), content);
  }
  assert.equal(fs.readdirSync(filesDir).length, 1);
  fs.writeFileSync(resolve(uri), 'third-party edit'); fs.writeFileSync(local, 'local edit');
  await assert.rejects(edits.synchronize(local), /同时发生变化/);
  assert.equal(fs.readFileSync(local, 'utf8'), 'local edit');
  fs.writeFileSync(local, 'saved again');
  copyHook = () => fs.writeFileSync(resolve(uri), 'changed during sync');
  assert.equal(await edits.synchronize(local), false);
  assert.equal(fs.readFileSync(local, 'utf8'), 'saved again');
  assert.equal(await edits.synchronize(local), true);
  assert.equal(fs.readFileSync(local, 'utf8'), 'changed during sync');
  fs.unlinkSync(resolve(uri));
  assert.equal(await edits.synchronize(local), false);
  await assert.rejects(edits.prepare(local), /移动或删除/);
  assert.equal(fs.readFileSync(local, 'utf8'), 'changed during sync');
  assert.equal(await edits.synchronize(path.join(cacheDir, 'untracked')), false);
  await edits.release(local);
  assert.deepEqual(fs.readdirSync(filesDir), []);

  // Closing copies a last unpolled save back before deleting the edit directory.
  const finalUri = await edits.prepare(local);
  fs.writeFileSync(resolve(finalUri), 'final save before closing');
  await edits.release(local);
  assert.equal(fs.readFileSync(local, 'utf8'), 'final save before closing');
  assert.deepEqual(fs.readdirSync(filesDir), []);
  await edits.release(path.join(cacheDir, 'untracked'));
  // A conflicting edit prevents cleanup and leaves both versions intact.
  const conflictUri = await edits.prepare(local);
  fs.writeFileSync(resolve(conflictUri), 'external conflict');
  fs.writeFileSync(local, 'local conflict');
  await assert.rejects(edits.release(local), /同时发生变化/);
  assert.equal(fs.readFileSync(resolve(conflictUri), 'utf8'), 'external conflict');
  assert.equal(fs.readFileSync(local, 'utf8'), 'local conflict');
  fs.writeFileSync(local, 'final save before closing');
  await edits.release(local);
  assert.deepEqual(fs.readdirSync(filesDir), []);
  assert.deepEqual(fs.readdirSync(cacheDir), ['中文 document.docx']);
  edits.clear();
  console.log('ExternalEdits: sandbox DOCX URI, repeat saves, reuse, conflicts, moving snapshot, missing file and close cleanup passed.');
})().catch(error => { console.error(error); process.exitCode = 1; })
  .finally(() => fs.rmSync(temporary, { recursive: true, force: true }));
