#!/usr/bin/env node
// Bidirectional sync between /root (root user's HOME = dsh working area) and
// an S3-compatible bucket (KS3 etc).
// Uses @aws-sdk/client-s3 with the same client params that storage-console uses
// against KS3 (virtual-host style, requestChecksumCalculation WHEN_REQUIRED),
// which is verified to work where rclone's generic S3 driver fails.
//
// Behavior:
//   boot : ListObjectsV2 bucket/PREFIX -> download all remote objects into workspace
//   watch: fs.watch on workspace; on any change, debounce then do one sync pass:
//            upload local files that are new/changed/removed vs remote
//            download remote objects that are new/changed vs local
//   exit : final upload pass (SIGTERM/SIGINT via process handlers)
import { S3Client, ListObjectsV2Command, GetObjectCommand, PutObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { createHash } from 'node:crypto';
import { readdir, stat, readFile, writeFile, mkdir, chmod, rm } from 'node:fs/promises';
import { watch } from 'node:fs';
import { join, relative, sep, dirname } from 'node:path';

const workspace = process.env.DSH_WORKSPACE || '/root';
const bucket = process.env.S3_BUCKET || '';
const prefix = String(process.env.S3_PATH || '').replace(/^\/+|\/+$/g, '');
const endpoint = (process.env.S3_ENDPOINT || '').trim().replace(/\/+$/, '');
const region = (process.env.S3_REGION || '').trim() || 'us-east-1';
const accessKey = (process.env.S3_ACCESS_KEY || '').trim();
const secretKey = (process.env.S3_SECRET_KEY || '').trim();
const debounceMs = 500;
// How many objects to download in parallel during the boot pull. Serial pulls
// of thousands of objects stall on per-object network RTT; a bounded pool keeps
// throughput high without tripping S3 rate limits. Configurable via
// BOOT_PULL_CONCURRENCY (default 32).
const BOOT_PULL_CONCURRENCY = Math.max(1, parseInt(process.env.BOOT_PULL_CONCURRENCY || '32', 10) || 32);
const isDebug = (process.env.LOG_LEVEL || '').toLowerCase() === 'debug';

// info level (default): lifecycle + per-pass sync counts only.
function log(...args) {
  console.log('s3-sync:', ...args);
}
// debug level: per-file sync details (which file, which direction).
function dbg(...args) {
  if (isDebug) console.log('s3-sync: [debug]', ...args);
}

if (!bucket || !endpoint || !accessKey || !secretKey) {
  console.error('s3-sync: missing required env (S3_BUCKET/S3_ENDPOINT/S3_ACCESS_KEY/S3_SECRET_KEY)');
  process.exit(1);
}

// Same effective params as storage-console's createS3Client (verified on KS3).
// forcePathStyle defaults to auto (localhost/IP endpoints use path-style).
// Explicit S3_PATH_STYLE=1 forces path-style (MinIO/self-hosted); =0 forces
// virtual-host style (AWS/Kingsoft).
const pathStyleEnv = String(process.env.S3_PATH_STYLE || '').trim();
let forcePathStyle;
if (pathStyleEnv === '1') forcePathStyle = true;
else if (pathStyleEnv === '0') forcePathStyle = false;
else {
  forcePathStyle = false;
  try {
    const host = new URL(endpoint).hostname;
    if (host === 'localhost' || host.endsWith('.localhost')) forcePathStyle = true;
    else if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) forcePathStyle = true;
  } catch { forcePathStyle = true; }
}

const client = new S3Client({
  endpoint,
  region,
  forcePathStyle,
  requestChecksumCalculation: 'WHEN_REQUIRED',
  credentials: { accessKeyId: accessKey, secretAccessKey: secretKey },
});

// objectKey for a local relative path (relative to workspace).
const localToKey = (relPath) => [prefix, relPath].filter(Boolean).join('/');
// local relative path for a remote key under prefix.
const keyToLocal = (key) => (prefix && key.startsWith(prefix + '/') ? key.slice(prefix.length + 1) : key);
// Helper: local absolute path for a remote key.
const localAbsPath = (key) => join(workspace, ...keyToLocal(key).split('/'));
// Helper: full s3 URL for a key.
const s3Url = (key) => `s3://${bucket}/${key}`;

// Every file under the workspace (~/, /root) is synced — no exclusions.

// Files the entrypoint regenerates from env on every boot (sync-provider.sh
// writes settings.yaml; entrypoint.sh copies cordis.patch.yml). The bucket may
// hold a stale copy from an earlier run, so downloading it during the boot
// pull could clobber the env-driven config with an older one (e.g. a settings
// file without the current thinking-strength selector). The boot pull skips
// these; uploads still happen, so the fresh local copy converges the bucket.
function isEntrypointManaged(key) {
  const rel = keyToLocal(key);
  return rel === '.dsh/settings.yaml' || rel === '.dsh/cordis.patch.yml';
}

// Local coordination sentinel written by the daemon after boot pull + purge;
// never synced to the bucket (see sync-workspace.sh, which polls it). Folded
// into shouldIgnore below.
const READY_FILE = '.dsh-sync-ready';

// Cache directories that are rebuilt automatically and never need to be
// synced: npm/yarn caches, editor config caches, and the dsh plugin bundle's
// internal .cache. They bloat the bucket and slow the boot pull for nothing.
// A rel path (relative to the workspace) or a bucket key is ignored when its
// first segment — or the leading `.dsh/profiles/web/node_modules` segment — is
// one of these.
const IGNORED_PREFIXES = [
  '.dsh/profiles/web/node_modules/.cache',
  '.npm',
  '.cache',
  '.local',
  '.config',
];
function shouldIgnore(rel) {
  if (rel === READY_FILE) return true;
  for (const p of IGNORED_PREFIXES) {
    if (rel === p || rel.startsWith(p + '/')) return true;
  }
  return false;
}

async function listRemote() {
  const keys = new Map(); // key -> {size, etag}
  let token;
  do {
    const cmd = new ListObjectsV2Command({
      Bucket: bucket,
      Prefix: prefix ? `${prefix}/` : '',
      ContinuationToken: token,
    });
    const res = await client.send(cmd);
    for (const o of res.Contents || []) {
      keys.set(o.Key, { size: o.Size, etag: o.ETag });
    }
    token = res.IsTruncated ? res.NextContinuationToken : undefined;
  } while (token);
  return keys;
}

async function listLocal() {
  const files = new Map(); // key -> {size, mtimeMs}
  async function walk(dir) {
    let entries;
    try { entries = await readdir(dir, { withFileTypes: true }); }
    catch { return; }
    for (const e of entries) {
      const full = join(dir, e.name);
      const relPath = relative(workspace, full);
      if (shouldIgnore(relPath)) continue;
      if (e.isDirectory()) {
        await walk(full);
      } else if (e.isFile()) {
        const st = await stat(full).catch(() => null);
        if (st) files.set(localToKey(relPath.split(sep).join('/')), { size: st.size, mtimeMs: st.mtimeMs });
      }
    }
  }
  await walk(workspace);
  return files;
}

async function ensureLocalDir(key) {
  const dir = join(workspace, ...keyToLocal(key).split('/').slice(0, -1));
  await mkdir(dir, { recursive: true });
}

// Content hash (md5) of a local file, used for change detection beyond size.
async function hashFile(path) {
  const buf = await readFile(path);
  return createHash('md5').update(buf).digest('hex');
}

// Run `fn` over `items` with at most `limit` concurrent invocations, in order
// of submission. Each failure is surfaced via the returned per-item result so
// a slow/failed item does not stall the whole batch.
async function mapLimit(items, limit, fn) {
  const results = new Array(items.length);
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const i = next++;
      try { results[i] = await fn(items[i], i); }
      catch (e) { results[i] = { error: e }; }
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return results;
}

async function pull(key, remoteMeta) {
  const get = await client.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  const chunks = [];
  for await (const chunk of get.Body) chunks.push(chunk);
  const buf = Buffer.concat(chunks);
  await ensureLocalDir(key);
  const dest = join(workspace, ...keyToLocal(key).split('/'));
  await writeFile(dest, buf);
  // Restore the original mode recorded at upload (metadata dsh-mode).
  const modeStr = get.Metadata?.['dsh-mode'];
  if (modeStr && /^0?[0-7]{3,4}$/.test(modeStr)) {
    try { await chmod(dest, parseInt(modeStr, 8)); } catch { /* ignore */ }
  }
  return buf.length;
}

async function push(key, localPath) {
  const data = await readFile(localPath);
  const st = await stat(localPath).catch(() => null);
  const metadata = st ? {
    'dsh-mode': (st.mode & 0o777).toString(8),
    'dsh-hash': createHash('md5').update(data).digest('hex'),
  } : undefined;
  await client.send(new PutObjectCommand({ Bucket: bucket, Key: key, Body: data, Metadata: metadata }));
}

async function removeRemote(key) {
  await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
}

// One sync pass: upload local changes, download remote changes, prune deletions.
// Change detection: a key differs when its size differs, or — when sizes match
// but content may have changed — when the content hash differs. Remote side
// uses the object's ETag (single-part MD5) as its hash; local side hashes the
// file. Same-size edits are therefore caught in both directions.
async function syncOnce() {
  const [remote, local] = await Promise.all([listRemote(), listLocal()]);
  let up = 0, down = 0, del = 0;

  const remoteHash = (r) => {
    if (r?.hash) return r.hash;
    // ETag is quoted-MD5 for single-part uploads; strip the quotes.
    const etag = r?.etag;
    return etag ? etag.replace(/^"|"$/g, '').toLowerCase() : undefined;
  };

  // Upload: local file that's new or differs from remote (size or content).
  // Ignored cache dirs are skipped entirely (never uploaded).
  for (const [key, l] of local) {
    if (shouldIgnore(keyToLocal(key))) continue;
    const r = remote.get(key);
    const rHash = r ? remoteHash(r) : undefined;
    let differs = !r;
    if (r && r.size !== l.size) differs = true;
    else if (r && r.size === l.size) {
      // Same size — check content hash to catch same-size edits.
      if (rHash) {
        try {
          differs = (await hashFile(join(workspace, ...keyToLocal(key).split('/')))) !== rHash;
        } catch { differs = true; }
      }
      // No remote hash available (multipart/unknown) — treat as differing to
      // be safe? No: that would re-upload everything each pass. Fall back to
      // size-only (i.e. not differing) when we can't compare content.
    }
    if (differs) {
      try {
        await push(key, join(workspace, ...keyToLocal(key).split('/')));
        up++;
        dbg(`upload ${localAbsPath(key)} -> ${s3Url(key)}`);
      } catch (e) {
        console.error(`s3-sync: push ${key} failed: ${e.message}`);
      }
    }
  }

  // Download: remote object missing locally, or whose content differs from
  // the local copy (size or hash). Ignored cache keys are never downloaded.
  for (const [key, r] of remote) {
    if (shouldIgnore(keyToLocal(key))) continue;
    const l = local.get(key);
    const rHash = remoteHash(r);
    let shouldPull = !l;
    if (l && r.size !== l.size) shouldPull = true;
    else if (l && r.size === l.size && rHash) {
      try {
        shouldPull = (await hashFile(join(workspace, ...keyToLocal(key).split('/')))) !== rHash;
      } catch { shouldPull = false; }
    }
    if (shouldPull) {
      try {
        await pull(key, r);
        down++;
        dbg(`download ${s3Url(key)} -> ${localAbsPath(key)}`);
      } catch (e) {
        console.error(`s3-sync: pull ${key} failed: ${e.message}`);
      }
    }
  }

  // Delete remote objects that no longer exist locally — including ignored
  // cache objects that were synced up before this exclusion existed, so the
  // bucket converges to only what the current exclusion policy keeps.
  for (const key of remote.keys()) {
    const rel = keyToLocal(key);
    if (shouldIgnore(rel)) {
      // Stale ignored object: delete it from the bucket.
      try {
        await removeRemote(key);
        del++;
        dbg(`delete ${s3Url(key)} (ignored, cleaned from bucket)`);
      } catch (e) { console.error(`s3-sync: delete ${key} failed: ${e.message}`); }
      continue;
    }
    if (!local.has(key)) {
      try {
        await removeRemote(key);
        del++;
        dbg(`delete ${s3Url(key)} (local ${localAbsPath(key)} removed)`);
      }
      catch (e) { console.error(`s3-sync: delete ${key} failed: ${e.message}`); }
    }
  }

  return { up, down, del };
}

async function main() {
  // Boot: pull the full remote tree down first — but only for files missing
  // locally. The workspace is bind-mounted/volume-persisted, so a file that
  // already exists locally is the authoritative, newer copy (e.g. a session
  // log dsh is still appending to, or a config the entrypoint regenerated).
  // Overwriting it with a stale bucket object — the boot pull's old behavior —
  // is what corrupted session logs across restarts ("corrupt session log: seq
  // gap"). The bucket is therefore a recovery source for missing files, not a
  // competing copy of existing ones. Entrypoint-managed files and ignored
  // cache dirs are skipped as before.
  const [remote, local] = await Promise.all([listRemote(), listLocal()]);
  const pullKeys = [...remote.keys()].filter(
    (k) => !isEntrypointManaged(k)
      && !shouldIgnore(keyToLocal(k))
      && !local.has(k)
  );
  log(`boot pull: ${pullKeys.length} objects to download (${remote.size} remote, concurrency ${BOOT_PULL_CONCURRENCY})`);
  // Bounded concurrency: serial downloads of thousands of objects stall on
  // per-object network RTT. A fixed worker pool keeps throughput high without
  // tripping S3 rate limits. Per-item failures are isolated (mapLimit).
  const results = await mapLimit(pullKeys, BOOT_PULL_CONCURRENCY, async (key) => {
    await pull(key);
    dbg(`boot download ${s3Url(key)} -> ${localAbsPath(key)}`);
  });
  let pulled = 0, pullFail = 0;
  for (let i = 0; i < results.length; i++) {
    if (results[i] && results[i].error) {
      pullFail++;
      console.error(`s3-sync: boot pull ${pullKeys[i]} failed: ${results[i].error.message}`);
    } else {
      pulled++;
    }
  }
  log(`boot pull complete (${pulled} objects${pullFail ? `, ${pullFail} failed` : ''}) -> ${workspace}`);

  // Version-aware purge of the persisted plugin directory. The boot pull just
  // brought down the bucket's .dsh (which may include plugins a previous dsh
  // version installed — e.g. the 0.1.5-alpha.2 documentpreview loader that
  // crashes the browser with "Can't find variable: Iterator"). When the
  // recorded version differs from the image's DSH_VERSION, wipe the profile's
  // node_modules so dsh rebuilds its plugin set from the current image.
  // Same-version boots keep the directory untouched.
  const dshVersion = process.env.DSH_VERSION || '';
  if (dshVersion) {
    const markerPath = join(workspace, '.dsh', '.dsh-web-version');
    let prev = '';
    try { prev = (await readFile(markerPath, 'utf8')).trim(); } catch { /* no marker yet */ }
    if (prev !== dshVersion) {
      if (prev) console.log(`s3-sync: dsh version changed (${prev} -> ${dshVersion}); purging persisted web plugins`);
      await rm(join(workspace, '.dsh', 'profiles', 'web', 'node_modules'), { recursive: true, force: true });
      await mkdir(dirname(markerPath), { recursive: true });
      await writeFile(markerPath, `${dshVersion}\n`);
    }
  }

  // Signal readiness so the entrypoint does not start dsh before the boot pull
  // and version purge above have completed (see sync-workspace.sh which polls
  // this sentinel). Excluded from sync by isSyncedRoot below.
  const readyPath = join(workspace, '.dsh-sync-ready');
  await writeFile(readyPath, `${dshVersion}\n`);

  // Watch workspace; debounce bursts of events, then run one sync pass.
  let dirty = false;
  let running = false;
  let timer = null;

  const runSync = async () => {
    if (running) { dirty = true; return; }
    running = true;
    try {
      const { up, down, del } = await syncOnce();
      dbg(`sync up=${up} down=${down} del=${del}`);
    } catch (e) {
      console.error(`s3-sync: sync failed: ${e.message}`);
    } finally {
      running = false;
      // A change arrived while we were syncing (e.g. the sync itself wrote files).
      // Re-run once to catch anything we missed, then clear the flag.
      if (dirty) {
        dirty = false;
        await runSync();
      }
    }
  };

  const scheduleSync = () => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(runSync, debounceMs);
  };

  // Recursively watch the workspace (on Linux, {recursive:true} needs inotify
  // support; Node 20+ has it for Linux. Fall back to watching root only).
  let watcher;
  try {
    watcher = watch(workspace, { recursive: true }, scheduleSync);
  } catch {
    watcher = watch(workspace, scheduleSync);
  }
  console.log(`s3-sync: watching ${workspace} for changes`);

  // Stop cleanly on signals; never force-quit before final upload.
  const shutdown = async () => {
    if (timer) clearTimeout(timer);
    if (watcher) try { watcher.close(); } catch {}
    // watcher.close() is not a hard stop of the callback stream: an fs event
    // already queued can fire scheduleSync after clearTimeout and arm a fresh
    // timer. Drain one tick so any such timer is cleared too, then wait for an
    // in-flight sync to finish, then do the final pass.
    await new Promise((resolve) => setImmediate(resolve));
    if (timer) clearTimeout(timer);
    await new Promise((resolve) => {
      const check = () => (running ? setTimeout(check, 100) : resolve());
      check();
    });
    try { await syncOnce(); } catch (e) { console.error(`s3-sync: final pass failed: ${e.message}`); }
    console.log('s3-sync: exiting');
    process.exit(0);
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
  // Let the event loop stay alive via the watcher.
}

main().catch((e) => { console.error('s3-sync fatal:', e); process.exit(1); });
