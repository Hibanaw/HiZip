import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

interface EditingDocument {
  uri: string;
  hash: string;
  version: string;
}

// Office editors need a document URI, not an application directory in Want's
// stream list. Public editing copies also allow sibling-file replacement saves.
export class ExternalEdits {
  private context: () => common.UIAbilityContext;
  private documents: Map<string, EditingDocument> = new Map();
  private preparing: Map<string, Promise<string>> = new Map();
  private synchronizing: Map<string, Promise<boolean>> = new Map();
  constructor(context: () => common.UIAbilityContext) { this.context = context; }
  clear(): void { this.documents.clear(); this.preparing.clear(); this.synchronizing.clear(); }

  private version(stat: fs.Stat): string {
    return stat.ino.toString() + ':' + stat.size + ':' + (stat.mtimeNs ?? stat.mtime).toString();
  }
  private async digest(fd: number): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    const buffer = new ArrayBuffer(1024 * 1024);
    let offset = 0;
    while (true) {
      const count = await fs.read(fd, buffer, { offset: offset, length: buffer.byteLength });
      if (count === 0) break;
      await md.update({ data: new Uint8Array(buffer, 0, count) });
      offset += count;
    }
    return Array.from((await md.digest()).data).map((byte: number) => byte.toString(16).padStart(2, '0')).join('');
  }
  private async fileDigest(path: string): Promise<string> {
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try { return await this.digest(file.fd); } finally { await fs.close(file); }
  }

  prepare(path: string): Promise<string> {
    const pending = this.preparing.get(path);
    if (pending) return pending;
    const job = this.prepareDocument(path).finally(() => { this.preparing.delete(path); });
    this.preparing.set(path, job);
    return job;
  }
  private async prepareDocument(path: string): Promise<string> {
    const existing = this.documents.get(path);
    if (existing) {
      if (!await fs.access(new fileUri.FileUri(existing.uri).path)) {
        throw new Error('外部编辑副本已被移动或删除，请重新打开压缩包。');
      }
      await this.synchronize(path);
      return existing.uri;
    }
    const name = path.substring(path.lastIndexOf('/') + 1);
    if (!name || name === '.' || name === '..' || /[\/\\\u0000]/.test(name)) throw new Error('Invalid document name.');
    const options = new picker.DocumentSaveOptions();
    options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
    const folders = await new picker.DocumentViewPicker(this.context()).save(options);
    if (folders.length !== 1 || !folders[0].startsWith('file://docs/')) {
      throw new Error('无法取得系统编辑副本的保存位置。');
    }
    // fs.mkdir is limited to the sandbox; fs.copy exports a fresh directory to
    // the authorized DOWNLOAD URI. Each entry keeps its original filename.
    const folderName = 'HiZip-edit-' + Date.now() + '-' + Math.floor(Math.random() * 1000000000);
    const staging = this.context().cacheDir + '/' + folderName;
    await fs.mkdir(staging);
    try {
      await fs.copyFile(path, staging + '/' + name);
      await fs.copy(fileUri.getUriFromPath(staging), folders[0]);
      const uri = folders[0].replace(/\/$/, '') + '/' + folderName + '/' + encodeURIComponent(name);
      const file = await fs.open(uri, fs.OpenMode.READ_WRITE);
      try {
        if (!(await fs.stat(file.fd)).isFile()) throw new Error('Editing source must be a regular file.');
        const hash = await this.digest(file.fd);
        if (hash !== await this.fileDigest(path)) throw new Error('文件在准备编辑副本时发生变化，请重试。');
        this.documents.set(path, { uri: uri, hash: hash, version: this.version(await fs.stat(file.fd)) });
      } finally { await fs.close(file); }
      return uri;
    } finally { await fs.rmdir(staging); }
  }

  synchronize(path: string): Promise<boolean> {
    const pending = this.synchronizing.get(path);
    if (pending) return pending;
    const job = this.synchronizeDocument(path).finally(() => { this.synchronizing.delete(path); });
    this.synchronizing.set(path, job);
    return job;
  }
  private async synchronizeDocument(path: string): Promise<boolean> {
    const document = this.documents.get(path);
    if (!document || !await fs.access(path) || !await fs.access(new fileUri.FileUri(document.uri).path)) return false;
    const file = await fs.open(document.uri, fs.OpenMode.READ_ONLY);
    const staging = path + '.hizip-sync-' + Date.now() + '-' + Math.floor(Math.random() * 1000000000);
    try {
      const stat = await fs.stat(file.fd);
      if (!stat.isFile()) throw new Error('外部编辑副本不是普通文件。');
      const version = this.version(stat);
      if (version === document.version) return false;
      const hash = await this.digest(file.fd);
      if (hash === document.hash) { document.version = version; return false; }
      if (await this.fileDigest(path) !== document.hash) {
        throw new Error('编辑副本和 HiZip 中的文件同时发生变化，请保留编辑副本后重新打开压缩包。');
      }
      const output = await fs.open(staging, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      try {
        fs.lseek(file.fd, 0, fs.WhenceType.SEEK_SET);
        await fs.copyFile(file.fd, output.fd);
        await fs.fsync(output.fd);
      } finally { await fs.close(output); }
      // A save can replace the public inode while we are copying. Defer a
      // moving snapshot to the next poll instead of publishing partial edits.
      if (await this.fileDigest(staging) !== hash || await this.fileDigest(document.uri) !== hash) return false;
      if (await this.fileDigest(path) !== document.hash) throw new Error('本地编辑文件在同步期间发生变化，请重试。');
      await fs.rename(staging, path);
      document.hash = hash;
      document.version = version;
      return true;
    } finally {
      await fs.close(file);
      if (await fs.access(staging)) await fs.unlink(staging);
    }
  }
}
