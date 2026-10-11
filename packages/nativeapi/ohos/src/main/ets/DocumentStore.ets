import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

export interface DocumentLocation {
  workingPath: string;
  uri: string;
  displayPath: string;
  writable: boolean;
}
interface SourceDocument {
  location: DocumentLocation;
  hash: string;
}
interface PendingWrite {
  file: fs.File;
  backup: string;
  hash: string;
  ino: bigint;
  writing: boolean;
}

// Keep URI grants intact. Only private working copies are passed to the C engine.
export class DocumentStore {
  private sources: Map<string, SourceDocument> = new Map();
  private writes: Map<string, PendingWrite> = new Map();
  private activeUris: Set<string> = new Set();
  private workspace: () => Promise<string>;
  constructor(workspace: () => Promise<string>) { this.workspace = workspace; }

  location(path: string, uri: string, writable: boolean): DocumentLocation {
    return { workingPath: path, uri: uri, displayPath: new fileUri.FileUri(uri).path, writable: writable };
  }
  getLocation(path: string): DocumentLocation | null {
    return this.sources.get(path)?.location ?? null;
  }
  private name(uri: string): string {
    const name = new fileUri.FileUri(uri).name;
    if (!name || name === '.' || name === '..' || /[\/\\\u0000]/.test(name)) throw new Error('Invalid document name.');
    return name;
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
    const bytes = (await md.digest()).data;
    return Array.from(bytes).map((byte: number) => byte.toString(16).padStart(2, '0')).join('');
  }
  private async copyFd(source: number, destination: string): Promise<void> {
    const file = await fs.open(destination, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      fs.lseek(source, 0, fs.WhenceType.SEEK_SET);
      await fs.copyFile(source, file.fd);
    }
    finally { await fs.close(file); }
  }
  async importFile(uri: string, readOnly: boolean = false): Promise<DocumentLocation> {
    if (!uri.startsWith('file://')) throw new Error('Only file document URIs are supported.');
    const file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      if (!(await fs.stat(file.fd)).isFile()) throw new Error('The selected document is not a file.');
      const originalHash = await this.digest(file.fd);
      const path = await this.workspace() + '/' + this.name(uri);
      await this.copyFd(file.fd, path);
      const copied = await fs.open(path, fs.OpenMode.READ_ONLY);
      try {
        if (await this.digest(copied.fd) !== originalHash || await this.digest(file.fd) !== originalHash) {
          throw new Error('The source document changed while opening. Please reopen it.');
        }
      } finally { await fs.close(copied); }
      let writable = false;
      if (!readOnly) {
        try {
          const probe = await fs.open(uri, fs.OpenMode.READ_WRITE);
          await fs.close(probe);
          writable = true;
        } catch (_) {}
      }
      const location = this.location(path, uri, writable);
      this.sources.set(path, { location: location, hash: originalHash });
      return location;
    } finally { await fs.close(file); }
  }
  async registerSaved(path: string, uri: string): Promise<DocumentLocation> {
    const file = await fs.open(uri, fs.OpenMode.READ_WRITE);
    try {
      const location = this.location(path, uri, true);
      this.sources.set(path, { location: location, hash: await this.digest(file.fd) });
      return location;
    } finally { await fs.close(file); }
  }
  async prepareWrite(path: string): Promise<void> {
    const source = this.sources.get(path);
    if (!source) return;
    if (!source.location.writable) throw new Error('Source document is read-only. Use Save a Copy.');
    if (this.writes.has(path)) throw new Error('A document write is already in progress.');
    if (this.activeUris.has(source.location.uri)) throw new Error('The source document is already being saved.');
    this.activeUris.add(source.location.uri);
    let file: fs.File;
    try { file = await fs.open(source.location.uri, fs.OpenMode.READ_WRITE); }
    catch (error) { this.activeUris.delete(source.location.uri); throw error as Error; }
    try {
      if (await this.digest(file.fd) !== source.hash) throw new Error('The source document was changed by another app. Reopen it or save a copy.');
      const backup = await this.workspace() + '/recovery-' + this.name(source.location.uri);
      await this.copyFd(file.fd, backup);
      this.writes.set(path, { file: file, backup: backup, hash: source.hash, ino: (await fs.stat(file.fd)).ino, writing: false });
    } catch (error) {
      this.activeUris.delete(source.location.uri);
      await fs.close(file);
      throw error as Error;
    }
  }
  async finishWrite(path: string): Promise<void> {
    const pending = this.writes.get(path);
    const source = this.sources.get(path);
    if (!pending || !source) return;
    pending.writing = true;
    let started = false;
    let succeeded = false;
    try {
      const fresh = await fs.open(source.location.uri, fs.OpenMode.READ_ONLY);
      try {
        if ((await fs.stat(fresh.fd)).ino !== pending.ino ||
            await this.digest(fresh.fd) !== pending.hash || await this.digest(pending.file.fd) !== pending.hash) {
          throw new Error('The source document changed during editing. The working copy was retained at ' + source.location.workingPath);
        }
      } finally { await fs.close(fresh); }
      const input = await fs.open(source.location.workingPath, fs.OpenMode.READ_ONLY);
      try {
        const expected = await this.digest(input.fd);
        started = true;
        fs.lseek(input.fd, 0, fs.WhenceType.SEEK_SET);
        fs.lseek(pending.file.fd, 0, fs.WhenceType.SEEK_SET);
        await fs.copyFile(input.fd, pending.file.fd);
        await fs.truncate(pending.file.fd, (await fs.stat(input.fd)).size);
        await fs.fsync(pending.file.fd);
        if (await this.digest(pending.file.fd) !== expected) throw new Error('Source document verification failed.');
        source.hash = expected;
        succeeded = true;
      } finally { await fs.close(input); }
    } catch (error) {
      if (started) {
        try {
          const backup = await fs.open(pending.backup, fs.OpenMode.READ_ONLY);
          try {
            fs.lseek(pending.file.fd, 0, fs.WhenceType.SEEK_SET);
            await fs.copyFile(backup.fd, pending.file.fd);
            await fs.truncate(pending.file.fd, (await fs.stat(backup.fd)).size);
            await fs.fsync(pending.file.fd);
            if (await this.digest(pending.file.fd) !== pending.hash) throw new Error('Recovery verification failed.');
          } finally { await fs.close(backup); }
        } catch (_) {
          throw new Error('Could not restore the source document. Recovery copy: ' + pending.backup + '. Edited copy: ' + source.location.workingPath);
        }
      }
      throw new Error((error as Error).message + '\nEdited copy: ' + source.location.workingPath + '\nRecovery copy: ' + pending.backup);
    } finally {
      this.writes.delete(path);
      this.activeUris.delete(source.location.uri);
      await fs.close(pending.file);
      if (succeeded) { try { await fs.unlink(pending.backup); } catch (_) {} }
    }
  }
  // A Save a Copy overwrite must not rebind the open archive to its new URI.
  async writeCopy(path: string, uri: string): Promise<void> {
    const key = path + '.copy-' + Date.now() + '-' + Math.floor(Math.random() * 1000000000);
    const file = await fs.open(uri, fs.OpenMode.READ_WRITE);
    let originalHash: string;
    try { originalHash = await this.digest(file.fd); }
    finally { await fs.close(file); }
    const destination: SourceDocument = { location: this.location(path, uri, true), hash: originalHash };
    this.sources.set(key, destination);
    try {
      await this.prepareWrite(key);
      await this.finishWrite(key);
      const original = this.sources.get(path);
      if (original?.location.uri === uri) original.hash = destination.hash;
    } finally {
      await this.abortWrite(key);
      this.sources.delete(key);
    }
  }

  async abortWrite(path: string): Promise<void> {
    const pending = this.writes.get(path);
    if (!pending) return;
    this.writes.delete(path);
    const source = this.sources.get(path);
    if (source) this.activeUris.delete(source.location.uri);
    await fs.close(pending.file);
    try { await fs.unlink(pending.backup); } catch (_) {}
  }
  clear(): void {
    this.writes.forEach((pending: PendingWrite) => { if (!pending.writing) { try { fs.closeSync(pending.file); } catch (_) {} } });
    this.writes.clear();
    this.activeUris.clear();
    this.sources.clear();
  }
}
