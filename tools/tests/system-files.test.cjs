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
  const uri = 'file://docs/storage/Users/currentUser/Download/HiZip-edit-123/中文%20document.docx';
  const wants = [];
  const systemFiles = new exportsObject.SystemFiles({
    startAbility: async want => wants.push(want),
  });
  for (const writable of [false, true]) {
    await systemFiles.open(uri, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', writable, 'system');
    const want = wants.pop();
    assert.equal(want.uri, uri);
    assert.equal(want.action, 'ohos.want.action.viewData');
    assert.equal(want.flags, writable ? 3 : 1);
    // A stream directory was interpreted by WPS as another document. The only
    // open object must be the file URI, retaining its filename and suffix.
    assert.equal(want.parameters, undefined);
    assert.ok(want.uri.endsWith('.docx'));
  }
  await assert.rejects(systemFiles.open(uri, 'application/msword', true, 'another-app'));
  assert.equal(wants.length, 0);
  console.log('SystemFiles: single document URI, filename/suffix, read/write flags and invalid application passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
