'use strict';

const { createHash, randomUUID } = require('node:crypto');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { Readable } = require('node:stream');
const { pipeline } = require('node:stream/promises');

const defaultReleaseUrl = 'https://api.github.com/repos/actions/runner/releases/latest';
const defaultPrefix = 'agents/github-runner';
const defaultManifestKey = `${defaultPrefix}/latest.json`;
const runnerVersionPattern = /^\d+\.\d+\.\d+$/;

function createDefaultAws() {
  let initialized = false;
  let s3;
  let HeadObjectCommand;
  let GetObjectCommand;
  let PutObjectCommand;

  function init() {
    if (initialized) return;
    initialized = true;
    const s3Sdk = require('@aws-sdk/client-s3');
    s3 = new s3Sdk.S3Client({});
    HeadObjectCommand = s3Sdk.HeadObjectCommand;
    GetObjectCommand = s3Sdk.GetObjectCommand;
    PutObjectCommand = s3Sdk.PutObjectCommand;
  }

  return {
    async headObject(params) {
      init();
      return s3.send(new HeadObjectCommand(params));
    },
    async getObject(params) {
      init();
      return s3.send(new GetObjectCommand(params));
    },
    async putObject(params) {
      init();
      return s3.send(new PutObjectCommand(params));
    },
  };
}

function log(level, message, fields = {}) {
  const entry = { level, message, ...fields };
  const rendered = JSON.stringify(entry);
  if (level === 'error') {
    console.error(rendered);
    return;
  }
  if (level === 'warn') {
    console.warn(rendered);
    return;
  }
  console.log(rendered);
}

function trimString(value) {
  return String(value || '').trim();
}

function joinS3Key(...parts) {
  return parts
    .map((value) => trimString(value).replace(/^\/+|\/+$/g, ''))
    .filter(Boolean)
    .join('/');
}

function configFromEvent(event = {}, env = process.env) {
  const input = event?.input && typeof event.input === 'object' ? event.input : {};
  const prefix = trimString(input.prefix || env.RUNS_ON_GITHUB_RUNNER_CACHE_PREFIX || defaultPrefix) || defaultPrefix;

  return {
    bucket: trimString(input.bucket || env.RUNS_ON_RUNNER_CACHE_BUCKET),
    prefix,
    manifestKey: trimString(input.manifest_key || env.RUNS_ON_GITHUB_RUNNER_MANIFEST_KEY || `${prefix}/latest.json`) || defaultManifestKey,
    releaseUrl: trimString(input.release_url || env.RUNS_ON_GITHUB_RUNNER_RELEASE_URL || defaultReleaseUrl) || defaultReleaseUrl,
  };
}

function runnerAssetSpecs(version) {
  return [
    { key: 'linux-x64', filename: `actions-runner-linux-x64-${version}.tar.gz`, contentType: 'application/gzip' },
    { key: 'linux-arm64', filename: `actions-runner-linux-arm64-${version}.tar.gz`, contentType: 'application/gzip' },
    { key: 'windows-x64', filename: `actions-runner-win-x64-${version}.zip`, contentType: 'application/zip' },
    { key: 'windows-arm64', filename: `actions-runner-win-arm64-${version}.zip`, contentType: 'application/zip' },
  ].map((asset) => ({
    ...asset,
    githubUrl: `https://github.com/actions/runner/releases/download/v${version}/${asset.filename}`,
  }));
}

async function fetchLatestVersion(fetchImpl, releaseUrl) {
  const response = await fetchImpl(releaseUrl, {
    headers: {
      Accept: 'application/json',
      'User-Agent': 'runs-on-github-runner-cache-refresh',
    },
  });
  if (!response.ok) {
    throw new Error(`GitHub latest runner release request failed with status ${response.status}`);
  }

  const payload = await response.json();
  const version = trimString(payload?.tag_name).replace(/^v/, '');
  if (!runnerVersionPattern.test(version)) {
    throw new Error(`GitHub latest runner release response did not include a valid tag_name: ${payload?.tag_name}`);
  }
  return version;
}

async function getObjectString(aws, bucket, key) {
  const result = await aws.getObject({ Bucket: bucket, Key: key });
  if (!result?.Body) {
    return '';
  }
  if (typeof result.Body.transformToString === 'function') {
    return result.Body.transformToString();
  }

  let body = '';
  for await (const chunk of result.Body) {
    body += Buffer.isBuffer(chunk) ? chunk.toString('utf8') : String(chunk);
  }
  return body;
}

async function loadExistingManifest(aws, bucket, key) {
  try {
    const body = await getObjectString(aws, bucket, key);
    if (!trimString(body)) {
      return null;
    }
    return JSON.parse(body);
  } catch (error) {
    if (isNotFoundError(error)) {
      return null;
    }
    throw error;
  }
}

async function objectExists(aws, bucket, key) {
  try {
    await aws.headObject({ Bucket: bucket, Key: key });
    return true;
  } catch (error) {
    if (isNotFoundError(error)) {
      return false;
    }
    throw error;
  }
}

function isNotFoundError(error) {
  const name = trimString(error?.name);
  const code = trimString(error?.Code || error?.code);
  return name === 'NotFound' ||
    name === 'NoSuchKey' ||
    code === 'NotFound' ||
    code === 'NoSuchKey' ||
    error?.$metadata?.httpStatusCode === 404;
}

async function downloadToFile(fetchImpl, url, filePath) {
  const response = await fetchImpl(url, {
    headers: {
      Accept: 'application/octet-stream',
      'User-Agent': 'runs-on-github-runner-cache-refresh',
    },
    redirect: 'follow',
  });
  if (!response.ok) {
    throw new Error(`GitHub runner asset request failed with status ${response.status} for ${url}`);
  }
  if (!response.body) {
    throw new Error(`GitHub runner asset response did not include a body for ${url}`);
  }

  await pipeline(Readable.fromWeb(response.body), fs.createWriteStream(filePath));
}

async function sha256ForFile(filePath) {
  const hash = createHash('sha256');
  const stream = fs.createReadStream(filePath);
  for await (const chunk of stream) {
    hash.update(chunk);
  }
  return hash.digest('hex');
}

function manifestAssetChanged(existing, expectedUrl) {
  return trimString(existing?.url) !== expectedUrl ||
    trimString(existing?.sha256) === '';
}

async function mirrorRunnerAsset(aws, fetchImpl, config, version, spec, existingManifest) {
  const objectKey = joinS3Key(config.prefix, version, spec.filename);
  const s3Url = `s3://${config.bucket}/${objectKey}`;
  const existingAsset = existingManifest?.assets?.[spec.key];
  if (
    trimString(existingManifest?.version) === version &&
    !manifestAssetChanged(existingAsset, s3Url) &&
    await objectExists(aws, config.bucket, objectKey)
  ) {
    return {
      reused: true,
      asset: {
        url: s3Url,
        sha256: trimString(existingAsset.sha256),
      },
    };
  }

  const tempPath = path.join(os.tmpdir(), `${randomUUID()}-${spec.filename}`);
  try {
    await downloadToFile(fetchImpl, spec.githubUrl, tempPath);
    const sha256 = await sha256ForFile(tempPath);
    await aws.putObject({
      Bucket: config.bucket,
      Key: objectKey,
      Body: fs.createReadStream(tempPath),
      ContentType: spec.contentType,
    });

    return {
      reused: false,
      asset: {
        url: s3Url,
        sha256,
      },
    };
  } finally {
    await fsp.rm(tempPath, { force: true });
  }
}

function manifestsEqual(left, right) {
  return JSON.stringify(left || null) === JSON.stringify(right || null);
}

async function performSync(event, options = {}) {
  const aws = options.aws || createDefaultAws();
  const fetchImpl = options.fetchImpl || fetch;
  const config = configFromEvent(event, options.env || process.env);
  if (!config.bucket) {
    throw new Error('RUNS_ON_RUNNER_CACHE_BUCKET must be configured');
  }

  const version = await fetchLatestVersion(fetchImpl, config.releaseUrl);
  const existingManifest = await loadExistingManifest(aws, config.bucket, config.manifestKey);
  const specs = runnerAssetSpecs(version);

  let reused = 0;
  let uploaded = 0;
  const assets = {};
  for (const spec of specs) {
    const mirrored = await mirrorRunnerAsset(aws, fetchImpl, config, version, spec, existingManifest);
    assets[spec.key] = mirrored.asset;
    if (mirrored.reused) {
      reused += 1;
    } else {
      uploaded += 1;
    }
  }

  const manifest = { version, assets };
  const changed = uploaded > 0 || !manifestsEqual(existingManifest, manifest);
  if (changed) {
    await aws.putObject({
      Bucket: config.bucket,
      Key: config.manifestKey,
      Body: JSON.stringify(manifest, null, 2),
      ContentType: 'application/json',
    });
  }

  const result = {
    bucket: config.bucket,
    manifest_key: config.manifestKey,
    version,
    asset_count: specs.length,
    reused,
    uploaded,
    changed,
  };
  log('info', 'Synchronized GitHub runner mirror into S3 cache', result);
  return result;
}

async function createHandler(event, options = {}) {
  try {
    return await performSync(event, options);
  } catch (error) {
    const message = String(error?.message || error);
    log('error', 'GitHub runner cache refresh failed', { error: message });
    throw error;
  }
}

module.exports = {
  configFromEvent,
  createHandler,
  fetchLatestVersion,
  handler: (event) => createHandler(event),
  runnerAssetSpecs,
};
