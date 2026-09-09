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
import { readdir, stat, readFile, writeFile, mkdir } from 'node:fs/promises';
import { watch } from 'node:fs';
import { join, relative, sep } from 'node:path';

const workspace = process.env.DSH_WORKSPACE || '/root';
const bucket = process.env.S3_BUCKET || '';
const prefix = String(process.env.S3_PATH || '').replace(/^\/+|\/+$/g, '');
const endpoint = (process.env.S3_ENDPOINT || '').trim().replace(/\/+$/, '');
const region = (process.env.S3_REGION || '').trim() || 'us-east-1';
const accessKey = (process.env.S3_ACCESS_KEY || '').trim();
const secretKey = (process.env.S3_SECRET_KEY || '').trim();
const debounceMs = 500;
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
// forcePathStyle only for localhost/IP endpoints.
let forcePathStyle = false;
try {
  const host = new URL(endpoint).hostname;
  if (host === 'localhost' || host.endsWith('.localhost')) forcePathStyle = true;
  else if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) forcePathStyle = true;
} catch { forcePathStyle = true; }

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

// HOME cache dirs skipped by default; override via SYNC_EXCLUDE (comma-sep).
// Keeps caches out of the bucket while syncing the rest of the HOME.
const CACHE_DIRS = '.npm,.cache,.local,.config';
const exclude = new Set(
  (process.env.SYNC_EXCLUDE || CACHE_DIRS).split(',').map((s) => s.trim()).filter(Boolean),
);

// True when a remote key's first path segment is an excluded cache dir.
function isExcluded(key) {
  const rel = keyToLocal(key);
  const top = rel.split('/')[0];
  return exclude.has(top);
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
      if (!isExcluded(o.Key)) keys.set(o.Key, { size: o.Size, etag: o.ETag });
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
      if (exclude.has(e.name)) continue;
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

async function pull(key, remoteMeta) {
  const get = await client.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  const chunks = [];
  for await (const chunk of get.Body) chunks.push(chunk);
  const buf = Buffer.concat(chunks);
  await ensureLocalDir(key);
  await writeFile(join(workspace, ...keyToLocal(key).split('/')), buf);
  return buf.length;
}

async function push(key, localPath) {
  const data = await readFile(localPath);
  await client.send(new PutObjectCommand({ Bucket: bucket, Key: key, Body: data }));
}

async function removeRemote(key) {
  await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
}

// One sync pass: upload local changes, download remote changes, prune deletions.
async function syncOnce() {
  const [remote, local] = await Promise.all([listRemote(), listLocal()]);
  let up = 0, down = 0, del = 0;

  // Upload: local file that's new or differs in size from remote.
  for (const [key, l] of local) {
    const r = remote.get(key);
    if (!r || r.size !== l.size) {
      try {
        await push(key, join(workspace, ...keyToLocal(key).split('/')));
        up++;
        dbg(`upload ${localAbsPath(key)} -> ${s3Url(key)}`);
      } catch (e) {
        console.error(`s3-sync: push ${key} failed: ${e.message}`);
      }
    }
  }

  // Download: remote object missing locally (and we're not just boot-pulling everything).
  for (const [key, r] of remote) {
    const l = local.get(key);
    if (!l) {
      try {
        await pull(key, r);
        down++;
        dbg(`download ${s3Url(key)} -> ${localAbsPath(key)}`);
      } catch (e) {
        console.error(`s3-sync: pull ${key} failed: ${e.message}`);
      }
    }
  }

  // Delete remote objects that no longer exist locally.
  for (const key of remote.keys()) {
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
  // Boot: pull remote down first (source of truth).
  const remote = await listRemote();
  let pulled = 0;
  for (const [key] of remote) {
    try {
      await pull(key);
      pulled++;
      dbg(`boot download ${s3Url(key)} -> ${localAbsPath(key)}`);
    }
    catch (e) { console.error(`s3-sync: boot pull ${key} failed: ${e.message}`); }
  }
  log(`boot pull complete (${pulled} objects) -> ${workspace}`);

  // Watch workspace; debounce bursts of events, then run one sync pass.
  let dirty = false;
  let running = false;
  let timer = null;

  const runSync = async () => {
    if (running) { dirty = true; return; }
    running = true;
    try {
      const { up, down, del } = await syncOnce();
      if (up || down || del) log(`sync up=${up} down=${down} del=${del}`);
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
    // Make sure any in-flight sync finishes; then final pass.
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
