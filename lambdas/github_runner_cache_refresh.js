'use strict';

const { createHash, randomUUID } = require('node:crypto');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { Readable } = require('node:stream');
const { pipeline } = require('node:stream/promises');

// runs-on/runner publishes RunsOn's build of each actions/runner release as
// v<version>-runs-on.<revision>, with upstream's file names and a SHA256SUMS.
const defaultReleaseUrl = 'https://api.github.com/repos/runs-on/runner/releases/latest';
// The same answer without an API quota: this page redirects to .../releases/tag/<tag>.
const releaseRedirectUrl = 'https://github.com/runs-on/runner/releases/latest';
const releaseDownloadUrl = 'https://github.com/runs-on/runner/releases/download';
const latestVersionAttempts = 3;
const defaultPrefix = 'agents/github-runner';
const defaultManifestKey = `${defaultPrefix}/latest.json`;
const releaseTagPattern = /^v(\d+\.\d+\.\d+)-runs-on\.\d+$/;

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
  const properties = event?.ResourceProperties || {};
  const input = event?.input && typeof event.input === 'object' ? event.input : {};
  const prefix = trimString(properties.Prefix || input.prefix || env.RUNS_ON_GITHUB_RUNNER_CACHE_PREFIX || defaultPrefix) || defaultPrefix;

  return {
    bucket: trimString(properties.Bucket || input.bucket || env.RUNS_ON_RUNNER_CACHE_BUCKET),
    prefix,
    manifestKey: trimString(properties.ManifestKey || input.manifest_key || env.RUNS_ON_GITHUB_RUNNER_MANIFEST_KEY || `${prefix}/latest.json`) || defaultManifestKey,
    releaseUrl: trimString(properties.ReleaseUrl || input.release_url || env.RUNS_ON_GITHUB_RUNNER_RELEASE_URL || defaultReleaseUrl) || defaultReleaseUrl,
  };
}

// parseReleaseTag returns the release a runs-on/runner tag names; version is
// the upstream version the runner reports to GitHub.
function parseReleaseTag(tag) {
  const match = trimString(tag).match(releaseTagPattern);
  return match ? { tag: match[0], version: match[1] } : null;
}

// The platforms RunsOn offers; the agent looks assets up by these keys.
function runnerAssetSpecs({ tag, version }) {
  return [
    { key: 'linux-x64', filename: `actions-runner-linux-x64-${version}.tar.gz`, contentType: 'application/gzip' },
    { key: 'linux-arm64', filename: `actions-runner-linux-arm64-${version}.tar.gz`, contentType: 'application/gzip' },
    { key: 'windows-x64', filename: `actions-runner-win-x64-${version}.zip`, contentType: 'application/zip' },
  ].map((asset) => ({
    ...asset,
    githubUrl: `${releaseDownloadUrl}/${tag}/${asset.filename}`,
  }));
}

async function fetchLatestReleaseFromApi(fetchImpl, releaseUrl) {
  const response = await fetchImpl(releaseUrl, {
    headers: {
      Accept: 'application/json',
      'User-Agent': 'runs-on-github-runner-cache-refresh',
    },
  });
  if (!response.ok) {
    const error = new Error(`GitHub latest runner release request failed with status ${response.status}`);
    // Lambda shares its egress addresses, so GitHub's anonymous API quota
    // (60 requests an hour per address) is often already spent.
    error.rateLimited = response.status === 403 || response.status === 429;
    throw error;
  }

  const payload = await response.json();
  const release = parseReleaseTag(payload?.tag_name);
  if (!release) {
    throw new Error(`GitHub latest runner release response did not include a valid tag_name: ${payload?.tag_name}`);
  }
  return release;
}

async function fetchLatestReleaseFromRedirect(fetchImpl) {
  const response = await fetchImpl(releaseRedirectUrl, {
    redirect: 'manual',
    headers: { 'User-Agent': 'runs-on-github-runner-cache-refresh' },
  });
  const location = trimString(response.headers?.get?.('location'));
  const release = parseReleaseTag((location.match(/\/releases\/tag\/([^/?#]+)$/) || [])[1]);
  if (!release) {
    throw new Error(`GitHub latest runner release redirect did not name a release (status ${response.status})`);
  }
  return release;
}

function defaultSleep(ms) {
  return new Promise((resolve) => { setTimeout(resolve, ms); });
}

// fetchLatestRelease asks the GitHub API, falls back to the release page's
// redirect when the API is rate limited, and retries a few times.
async function fetchLatestRelease(fetchImpl, releaseUrl, sleep = defaultSleep) {
  let lastError;
  for (let attempt = 1; attempt <= latestVersionAttempts; attempt += 1) {
    try {
      return await fetchLatestReleaseFromApi(fetchImpl, releaseUrl);
    } catch (error) {
      lastError = error;
      if (error.rateLimited) {
        try {
          return await fetchLatestReleaseFromRedirect(fetchImpl);
        } catch (redirectError) {
          log('warn', 'GitHub runner release redirect lookup failed', { error: String(redirectError?.message || redirectError) });
        }
      }
    }
    if (attempt < latestVersionAttempts) {
      await sleep(attempt * 2000);
    }
  }
  throw lastError;
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

// fetchChecksums reads the release's SHA256SUMS into a file name -> sha256 map.
async function fetchChecksums(fetchImpl, { tag }) {
  const url = `${releaseDownloadUrl}/${tag}/SHA256SUMS`;
  const response = await fetchImpl(url, {
    headers: { 'User-Agent': 'runs-on-github-runner-cache-refresh' },
    redirect: 'follow',
  });
  if (!response.ok) {
    throw new Error(`GitHub runner checksums request failed with status ${response.status} for ${url}`);
  }
  const checksums = new Map();
  for (const line of (await response.text()).split('\n')) {
    const match = line.trim().match(/^([0-9a-f]{64})\s+\*?(\S+)$/);
    if (match) checksums.set(match[2], match[1]);
  }
  return checksums;
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

async function mirrorRunnerAsset(aws, fetchImpl, config, release, spec, existingManifest, getChecksums) {
  // The tag keeps a fork build apart from a same-version copy of another
  // build, such as the stock runner older stacks mirrored.
  const objectKey = joinS3Key(config.prefix, release.tag, spec.filename);
  const s3Url = `s3://${config.bucket}/${objectKey}`;
  const existingAsset = existingManifest?.assets?.[spec.key];
  if (
    trimString(existingManifest?.version) === release.version &&
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
    const expected = (await getChecksums()).get(spec.filename);
    if (sha256 !== expected) {
      throw new Error(`${spec.filename} from ${release.tag} has sha256 ${sha256}, but SHA256SUMS lists ${expected || 'nothing'}`);
    }
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

  const release = await fetchLatestRelease(fetchImpl, config.releaseUrl, options.sleep);
  const existingManifest = await loadExistingManifest(aws, config.bucket, config.manifestKey);
  const specs = runnerAssetSpecs(release);
  // Only a run that downloads something needs the checksums.
  let checksums;
  const getChecksums = () => {
    checksums ||= fetchChecksums(fetchImpl, release);
    return checksums;
  };

  let reused = 0;
  let uploaded = 0;
  const assets = {};
  for (const spec of specs) {
    const mirrored = await mirrorRunnerAsset(aws, fetchImpl, config, release, spec, existingManifest, getChecksums);
    assets[spec.key] = mirrored.asset;
    if (mirrored.reused) {
      reused += 1;
    } else {
      uploaded += 1;
    }
  }

  const manifest = { version: release.version, tag: release.tag, assets };
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
    version: release.version,
    tag: release.tag,
    asset_count: specs.length,
    reused,
    uploaded,
    changed,
  };
  log('info', 'Synchronized GitHub runner mirror into S3 cache', result);
  return result;
}

async function sendCloudFormationResponse(event, status, data, reason, fetchImpl = fetch) {
  const responseUrl = trimString(event?.ResponseURL);
  if (!responseUrl) return;

  const body = JSON.stringify({
    Status: status,
    Reason: reason || `See CloudWatch Logs for details: ${trimString(event?.LogicalResourceId) || 'RunsOnGitHubRunnerCacheRefreshSeed'}`,
    PhysicalResourceId: trimString(event?.PhysicalResourceId) || trimString(event?.LogicalResourceId) || 'RunsOnGitHubRunnerCacheRefreshSeed',
    StackId: trimString(event?.StackId),
    RequestId: trimString(event?.RequestId),
    LogicalResourceId: trimString(event?.LogicalResourceId),
    Data: data || {},
  });

  await fetchImpl(responseUrl, {
    method: 'PUT',
    headers: {
      'content-type': '',
      'content-length': String(Buffer.byteLength(body)),
    },
    body,
  });
}

function seedFailure(error) {
  const message = String(error?.message || error);
  log('error', 'GitHub runner cache seed failed; the hourly refresh will retry', { error: message });
  return { seeded: false, error: message };
}

function isCloudFormationCustomResourceEvent(event) {
  return !!event?.ResponseURL && !!event?.RequestType;
}

async function createHandler(event, options = {}) {
  if (isCloudFormationCustomResourceEvent(event)) {
    if (event.RequestType === 'Delete') {
      await sendCloudFormationResponse(event, 'SUCCESS', { skipped: true }, 'Delete request acknowledged', options.fetchImpl || fetch);
      return { skipped: true };
    }

    // Seeding the cache at install time is an optimisation: the hourly
    // refresh fills it anyway, so a failure here must not roll the stack back.
    try {
      const result = await performSync(event, options);
      await sendCloudFormationResponse(event, 'SUCCESS', result, undefined, options.fetchImpl || fetch);
      return result;
    } catch (error) {
      const result = seedFailure(error);
      await sendCloudFormationResponse(event, 'SUCCESS', result, `Runner cache not seeded, the hourly refresh will retry: ${result.error}`, options.fetchImpl || fetch);
      return result;
    }
  }

  try {
    return await performSync(event, options);
  } catch (error) {
    // Terraform seeds with a direct invocation marked `seed`; like the
    // CloudFormation seed, it must not fail the apply.
    if (event?.input?.seed === true) {
      return seedFailure(error);
    }
    const message = String(error?.message || error);
    log('error', 'GitHub runner cache refresh failed', { error: message });
    throw error;
  }
}

module.exports = {
  configFromEvent,
  createHandler,
  fetchLatestRelease,
  handler: (event) => createHandler(event),
  runnerAssetSpecs,
  sendCloudFormationResponse,
};
