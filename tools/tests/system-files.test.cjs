// Runs the real ArkTS Want construction with host API stubs. The signed HAP
// build separately checks this source against the HarmonyOS SDK.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../..');
const ts = require(path.join(root,
  '.toolchains/command-line-tools/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(root,
  'packages/nativeapi/ohos/src/main/ets/SystemFiles.ets'), 'utf8');
const exportsObject = {};
const fileUri = { getUriFromPath: value => `file://com.hibanaw.hizip${encodeURI(value)}` };
vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 },
}).outputText, {
  exports: exportsObject,
  require: name => {
    if (name === '@kit.AbilityKit') return { wantConstant: { Flags: {
      FLAG_AUTH_READ_URI_PERMISSION: 1, FLAG_AUTH_WRITE_URI_PERMISSION: 2,
    } } };
    if (name === '@kit.CoreFileKit') return { fileUri };
    return {};
  },
});
(async () => {
  const cacheDir = '/data/storage/el2/base/cache';
  const directory = `${cacheDir}/hizip-abc123/archive-DEF456/file-ghi789`;
  const filename = `${directory}/中文 document.docx`;
  const wants = [];
  const systemFiles = new exportsObject.SystemFiles({
    cacheDir, startAbility: async want => wants.push(want),
  });
  await systemFiles.open(filename, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', true, 'system');
  const edit = wants.pop();
  assert.equal(edit.uri, fileUri.getUriFromPath(filename));
  assert.equal(edit.action, 'ohos.want.action.viewData');
  assert.equal(edit.flags, 3);
  assert.equal(edit.parameters['ability.params.stream'].length, 2);
  assert.equal(edit.parameters['ability.params.stream'][0], edit.uri);
  assert.equal(edit.parameters['ability.params.stream'][1], fileUri.getUriFromPath(directory));
  // The main URI identifies the document. Its isolated directory is the final
  // grant, allowing sibling creation and rename without sharing other entries.
  assert.notEqual(edit.parameters['ability.params.stream'][1], edit.uri);
  await systemFiles.open(filename, 'application/msword', false, 'system');
  const read = wants.pop();
  assert.equal(read.flags, 1);
  assert.equal(read.parameters, undefined);
  for (const unsafe of [
    `${cacheDir}/document.docx`,
    `${cacheDir}/hizip-abc123/archive-DEF456/document.docx`,
    '/data/storage/el2/base/files/imports/document.docx',
    `${cacheDir}-other/hizip-abc123/archive-DEF456/file-ghi789/document.docx`,
    `${directory}/nested/document.docx`,
    `${directory}/..`,
    `${directory}/.`,
    `${directory}/document\0.docx`,
  ]) {
    await systemFiles.open(unsafe, 'application/msword', true, 'system');
    assert.equal(wants.pop().parameters, undefined, unsafe);
  }
  await assert.rejects(systemFiles.open(filename, 'application/msword', true, 'another-app'));
  assert.equal(wants.length, 0);
  console.log('SystemFiles: editable directory grant, read-only access, 8 isolation cases and invalid application passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
