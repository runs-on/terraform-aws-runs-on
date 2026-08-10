'use strict';

const crypto = require('node:crypto');

let sts;
let AssumeRoleCommand;
let s3;
let GetObjectCommand;
let cachedJwks;
let cachedJwksExpiresAt = 0;

const enterpriseURL = normalizeOptionalURL(process.env.GITHUB_ENTERPRISE_URL || '');
const configuredIssuer = String(process.env.GITHUB_TOKEN_ISSUER || '').trim();
const issuer = normalizeOptionalURL(configuredIssuer || (enterpriseURL ? `${enterpriseURL}/_services/token` : 'https://token.actions.githubusercontent.com'));
const bucketArn = process.env.CACHE_BUCKET_ARN;
const bucketName = bucketNameFromArn(bucketArn);
// The control planes (fleet and flex) publish GitHub's OIDC JWKS to this key
// every 5 minutes (pkg/jwkscache); the broker validates runtime tokens
// exclusively against that S3 copy and never fetches from GitHub itself. The
// copy is accepted regardless of age — a stale key set still verifies
// signatures correctly, and rotation lag is bounded by the refresh interval.
const jwksObjectKey = 'agents/github-jwks.json';
const jwksCacheTTLMS = 2 * 60 * 1000;
const runnerRoleArn = process.env.RUNNER_ROLE_ARN;
const expectedAWSPartition = partitionFromArn(runnerRoleArn);
const expectedAccountID = accountIDFromArn(runnerRoleArn);
const expectedAWSRegion = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION || '';
const sessionDurationSeconds = Number(process.env.SESSION_DURATION_SECONDS || '3600');
const brokeredTagKey = 'runs-on-cache-brokered';
const brokeredTagValue = 'true';
const brokeredSessionNamePrefix = 'runs-on-cache-';
const repositoryTagKey = 'runs-on-cache-repository';
const maxAssumeRolePolicyChars = 2048;

async function handler(event) {
  const input = normalizeEvent(event);
  // The caller-identity proof is the anti-abuse gate: only an assumed session
  // of this account's runner role can redeem a runtime token for credentials.
  const caller = await fetchCallerIdentity(input.caller_identity);

  // Scoped credentials are only ever minted from a job's runtime token: the
  // agent's Magic Cache server is the sole consumer, and every cache-protocol
  // request carries one. There is no token-less base path.
  if (input.runtime_token === '') {
    throw new Error('runtime token is required');
  }
  const token = await validateRuntimeToken(input.runtime_token);
  const ac = normalizeAccessControls(token.payload.ac);
  // The cache prefix is a pure function of the GitHub-signed token: the same
  // signature that authorizes the ac scopes carries the repository IDs, so a
  // token can only ever mint credentials into its own repository's prefix.
  const { ownerID, repoID } = tokenRepositoryIDs(token.payload);
  const repository = repositoryPath(ownerID, repoID);

  const readPrefixes = prefixesFor(ownerID, repoID, ac.readScopes);
  const writePrefixes = prefixesFor(ownerID, repoID, ac.writeScopes);
  if (readPrefixes.length === 0 && writePrefixes.length === 0) {
    throw new Error('runtime token has no usable cache scopes');
  }
  const durationSeconds = sessionDuration(token.payload.exp);

  const assumed = await getSTSClient().send(new AssumeRoleCommand(buildAssumeRoleInput({
    instanceID: caller.instanceID,
    ownerID,
    repoID,
    durationSeconds,
    readPrefixes,
    writePrefixes,
  })));

  return {
    access_key_id: assumed.Credentials.AccessKeyId,
    secret_access_key: assumed.Credentials.SecretAccessKey,
    session_token: assumed.Credentials.SessionToken,
    expiration: assumed.Credentials.Expiration.toISOString(),
    repository,
    read_prefixes: readPrefixes,
    write_prefixes: writePrefixes,
    expires_at: assumed.Credentials.Expiration.toISOString(),
  };
}

function getSTSClient() {
  if (!sts) {
    const awsSTS = require('@aws-sdk/client-sts');
    AssumeRoleCommand = awsSTS.AssumeRoleCommand;
    sts = new awsSTS.STSClient({});
  }
  return sts;
}

function getS3Client() {
  if (!s3) {
    const awsS3 = require('@aws-sdk/client-s3');
    GetObjectCommand = awsS3.GetObjectCommand;
    s3 = new awsS3.S3Client({});
  }
  return s3;
}

// setS3ClientForTesting injects a fake S3 client and command constructor so
// unit tests can serve JWKS payloads without the AWS SDK. Also resets the
// in-memory JWKS cache so each test starts cold.
function setS3ClientForTesting(client, commandCtor) {
  s3 = client;
  GetObjectCommand = commandCtor;
  cachedJwks = undefined;
  cachedJwksExpiresAt = 0;
}

function normalizeEvent(event) {
  const body = typeof event === 'string' ? JSON.parse(event) : event;
  if (!body || typeof body !== 'object') {
    throw new Error('missing request body');
  }
  const runtimeToken = typeof body.runtime_token === 'string' ? body.runtime_token.trim() : '';
  return {
    runtime_token: runtimeToken,
    caller_identity: normalizeCallerIdentityProof(body.caller_identity),
  };
}

async function validateRuntimeToken(token) {
  // This is the Actions runtime/cache token, not the OIDC identity token. It is
  // still verified against GitHub's token issuer/JWKS before trusting its ac claim.
  const parts = token.split('.');
  if (parts.length !== 3) {
    throw new Error('runtime token is not a JWT');
  }
  const header = JSON.parse(base64urlDecode(parts[0]).toString('utf8'));
  const payload = JSON.parse(base64urlDecode(parts[1]).toString('utf8'));
  if (header.alg !== 'RS256' || !header.kid) {
    throw new Error('runtime token uses an unsupported signing algorithm');
  }
  if (payload.iss !== issuer) {
    throw new Error('runtime token issuer is not trusted');
  }
  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.nbf === 'number' && payload.nbf > now + 60) {
    throw new Error('runtime token is not active yet');
  }
  if (typeof payload.exp !== 'number' || payload.exp <= now) {
    throw new Error('runtime token is expired');
  }

  let jwk = (await loadJwks()).keys.find((key) => key.kid === header.kid);
  if (!jwk) {
    // A kid miss on a warm Lambda usually means GitHub rotated the signing
    // key inside our in-memory cache window; re-read the S3 copy once before
    // rejecting. If the control plane has not refreshed the copy yet the
    // mint fails until its next 5-minute pass — agents retry.
    cachedJwksExpiresAt = 0;
    jwk = (await loadJwks()).keys.find((key) => key.kid === header.kid);
  }
  if (!jwk) {
    throw new Error('runtime token signing key is not trusted');
  }
  const verifier = crypto.createVerify('RSA-SHA256');
  verifier.update(`${parts[0]}.${parts[1]}`);
  verifier.end();
  const ok = verifier.verify(crypto.createPublicKey({ key: jwk, format: 'jwk' }), base64urlDecode(parts[2]));
  if (!ok) {
    throw new Error('runtime token signature is invalid');
  }
  return { header, payload };
}

async function loadJwks() {
  const now = Date.now();
  if (cachedJwks && cachedJwksExpiresAt > now) {
    return cachedJwks;
  }
  cachedJwks = await loadJwksFromS3();
  cachedJwksExpiresAt = now + jwksCacheTTLMS;
  return cachedJwks;
}

async function loadJwksFromS3() {
  let output;
  try {
    output = await getS3Client().send(new GetObjectCommand({
      Bucket: bucketName,
      Key: jwksObjectKey,
    }));
  } catch (err) {
    // Without ListBucket a missing object surfaces as 403 AccessDenied, so a
    // miss and a permission problem are indistinguishable here — both mean
    // the broker cannot mint until the control plane publishes the JWKS.
    throw new Error(`JWKS cache object s3://${bucketName}/${jwksObjectKey} is unavailable (the control plane publishes it every 5 minutes — is the app running?): ${err.message}`);
  }
  const payload = JSON.parse(await bodyToString(output.Body));
  if (payload.issuer !== issuer) {
    throw new Error(`JWKS cache issuer ${payload.issuer} does not match configured issuer ${issuer}`);
  }
  if (!Array.isArray(payload.keys) || payload.keys.length === 0) {
    throw new Error('JWKS cache object contains no keys');
  }
  return { keys: payload.keys };
}

async function bodyToString(body) {
  if (!body) {
    return '';
  }
  if (typeof body.transformToString === 'function') {
    return body.transformToString();
  }
  const chunks = [];
  for await (const chunk of body) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString('utf8');
}

async function fetchCallerIdentity(proof) {
  // Replay is bounded by X-Amz-Expires, then STS verifies that the signed URL was
  // minted by the caller's current instance role credentials.
  const url = validateCallerIdentityProof(proof).url;
  const response = await fetch(url, { method: 'GET' });
  if (!response.ok) {
    throw new Error(`failed to verify caller identity: ${response.status}`);
  }
  const xml = await response.text();
  const accountID = extractXMLTag(xml, 'Account');
  if (accountID !== expectedAccountID) {
    throw new Error('caller identity account does not match runner role account');
  }
  const userID = extractXMLTag(xml, 'UserId');
  const instanceID = instanceIDFromCallerUserID(userID);
  const arn = extractXMLTag(xml, 'Arn');
  validateCallerArn(arn, instanceID);
  return { userID, instanceID, arn };
}

function normalizeCallerIdentityProof(raw) {
  if (!raw || typeof raw !== 'object') {
    throw new Error('missing caller identity proof');
  }
  const url = typeof raw.url === 'string' ? raw.url.trim() : '';
  if (url === '') {
    throw new Error('missing caller identity proof URL');
  }
  return { url };
}

function validateCallerIdentityProof(proof) {
  const normalized = normalizeCallerIdentityProof(proof);
  let parsed;
  try {
    parsed = new URL(normalized.url);
  } catch (err) {
    throw new Error(`caller identity proof URL is invalid: ${err.message}`);
  }
  if (parsed.protocol !== 'https:') {
    throw new Error('caller identity proof must use https');
  }
  if (parsed.searchParams.get('Action') !== 'GetCallerIdentity' || parsed.searchParams.get('Version') !== '2011-06-15') {
    throw new Error('caller identity proof must call STS GetCallerIdentity');
  }
  if (parsed.searchParams.get('X-Amz-Algorithm') !== 'AWS4-HMAC-SHA256') {
    throw new Error('caller identity proof must use SigV4 query signing');
  }
  if (parsed.searchParams.get('X-Amz-SignedHeaders') !== 'host') {
    throw new Error('caller identity proof signed headers are unsupported');
  }
  const expires = Number(parsed.searchParams.get('X-Amz-Expires'));
  if (!Number.isInteger(expires) || expires <= 0 || expires > 60) {
    throw new Error('caller identity proof expiry is invalid');
  }
  const credential = parsed.searchParams.get('X-Amz-Credential') || '';
  const credentialParts = credential.split('/');
  if (credentialParts.length !== 5 || credentialParts[3] !== 'sts' || credentialParts[4] !== 'aws4_request') {
    throw new Error('caller identity proof credential scope is invalid');
  }
  const signedRegion = credentialParts[2];
  if (expectedAWSRegion !== '' && signedRegion !== expectedAWSRegion) {
    throw new Error('caller identity proof region does not match Lambda region');
  }
  const host = parsed.hostname.toLowerCase();
  if (!stsHostnamesForRegion(expectedAWSPartition, signedRegion).includes(host)) {
    throw new Error('caller identity proof host is not an AWS STS endpoint');
  }
  if (!parsed.searchParams.has('X-Amz-Signature') || !parsed.searchParams.has('X-Amz-Security-Token')) {
    throw new Error('caller identity proof is not signed with temporary credentials');
  }
  return { url: parsed.toString(), region: signedRegion };
}

function validateCallerArn(arn, instanceID) {
  const expectedPrefix = `arn:${expectedAWSPartition}:sts::${expectedAccountID}:assumed-role/`;
  if (!arn.startsWith(expectedPrefix) || !arn.endsWith(`/${instanceID}`)) {
    throw new Error('caller identity is not an assumed runner role session');
  }
  const roleName = roleNameFromArn(runnerRoleArn);
  if (roleName !== '' && !arn.startsWith(`${expectedPrefix}${roleName}/`)) {
    throw new Error('caller identity role does not match runner role');
  }
}

function instanceIDFromCallerUserID(userID) {
  if (typeof userID !== 'string' || !/^[A-Za-z0-9+=,.@_-]+:i-[A-Fa-f0-9]{8,32}$/.test(userID)) {
    throw new Error('caller identity user id is invalid');
  }
  return normalizeRoleSessionName(userID.slice(userID.lastIndexOf(':') + 1));
}

// tokenRepositoryIDs extracts the GitHub numeric repository and owner
// identifiers from a validated runtime token payload. GitHub mints
// repository_id / repository_owner_id as decimal-string claims (per the
// committed fixtures in test/fixtures/runtime-token-claims). Both are
// required: the signed IDs are the sole scoping authority, so a token
// without them cannot mint scoped credentials.
function tokenRepositoryIDs(payload) {
  return {
    ownerID: requiredNumericClaim(payload.repository_owner_id, 'repository_owner_id'),
    repoID: requiredNumericClaim(payload.repository_id, 'repository_id'),
  };
}

function requiredNumericClaim(raw, name) {
  if (raw === undefined || raw === null || raw === '') {
    throw new Error(`runtime token has no ${name} claim`);
  }
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`runtime token ${name} claim is invalid`);
  }
  return value;
}

// repositoryPath is the {ownerId}/{repoId} pair used in scoped prefixes and
// the STS session tag. IDs are immutable, so the layout is rename-proof.
function repositoryPath(ownerID, repoID) {
  for (const [name, value] of [['owner id', ownerID], ['repository id', repoID]]) {
    if (!Number.isSafeInteger(value) || value <= 0) {
      throw new Error(`repository ${name} is invalid`);
    }
  }
  return `${ownerID}/${repoID}`;
}

function extractXMLTag(xml, tag) {
  const match = String(xml).match(new RegExp(`<${tag}>([^<]+)</${tag}>`));
  if (!match) {
    throw new Error(`caller identity response is missing ${tag}`);
  }
  return match[1];
}

function normalizeAccessControls(rawAC) {
  if (typeof rawAC !== 'string' || rawAC.trim() === '') {
    throw new Error('runtime token has no ac claim');
  }
  const entries = JSON.parse(rawAC);
  if (!Array.isArray(entries)) {
    throw new Error('runtime token ac claim must be an array');
  }
  const readScopes = new Set();
  const writeScopes = new Set();
  for (const entry of entries) {
    const scope = normalizeScope(entry && (entry.scope ?? entry.Scope));
    const permission = Number(entry && (entry.permission ?? entry.Permission));
    if (!scope || !Number.isInteger(permission)) {
      throw new Error('runtime token ac entry is invalid');
    }
    if ((permission & 1) !== 0) {
      readScopes.add(scope);
    }
    if ((permission & 2) !== 0) {
      writeScopes.add(scope);
    }
  }
  return {
    readScopes: [...readScopes].sort(),
    writeScopes: [...writeScopes].sort(),
  };
}

function normalizeScope(raw) {
  if (typeof raw !== 'string') {
    return '';
  }
  const scope = raw.trim();
  if (scope === '' || scope.includes('..') || scope.startsWith('/') || scope.includes('\\')) {
    throw new Error('runtime token ac scope is unsafe');
  }
  // Scopes only ever reach S3 paths and session policies as sha256 segments
  // (scopeSegment), so any git-valid ref text is acceptable here — branch
  // names like feature#123 or release=2026 must not be rejected. Control
  // characters are still refused for log hygiene.
  if (/[\u0000-\u001f\u007f]/.test(scope)) {
    throw new Error('runtime token ac scope contains unsupported characters');
  }
  return scope;
}

// scopeSegment returns the fixed-width path segment used for a cache scope in
// scoped bucket keys. Scopes are branch refs of arbitrary length; one prefix
// per scope is embedded in the STS session policy, so the segment must stay
// bounded or long branch names exceed the packed-policy quota
// (PackedPolicyTooLargeException). Must match the agent proxy's scopeSegment.
function scopeSegment(scope) {
  return crypto.createHash('sha256').update(scope, 'utf8').digest('hex').slice(0, 16);
}

function prefixesFor(ownerID, repoID, scopes) {
  if (scopes.length === 0) {
    return [];
  }
  const repository = repositoryPath(ownerID, repoID);
  return scopes.map((scope) => `scoped-cache/${repository}/${scopeSegment(scope)}/*`);
}

function buildSessionPolicy(ownerID, repoID, readPrefixes, writePrefixes) {
  if (readPrefixes.length === 0 && writePrefixes.length === 0) {
    throw new Error('runtime token has no usable cache scopes');
  }
  const statements = [
    {
      Effect: 'Allow',
      Action: 's3:ListBucket',
      Resource: bucketArn,
      Condition: {
        StringLike: {
          // Object access stays scoped per token below; list access is repo-wide
          // to keep the inline STS policy under the plaintext character limit.
          's3:prefix': `scoped-cache/${repositoryPath(ownerID, repoID)}/*`,
        },
      },
    },
  ];
  const writePrefixSet = new Set(writePrefixes);
  const readPrefixSet = new Set(readPrefixes);
  const readOnlyPrefixes = readPrefixes.filter((prefix) => !writePrefixSet.has(prefix));
  const readWritePrefixes = readPrefixes.filter((prefix) => writePrefixSet.has(prefix));
  const writeOnlyPrefixes = writePrefixes.filter((prefix) => !readPrefixSet.has(prefix));
  if (readOnlyPrefixes.length > 0) {
    statements.push({
      Effect: 'Allow',
      Action: 's3:GetObject',
      Resource: readOnlyPrefixes.map((prefix) => `${bucketArn}/${prefix}`),
    });
  }
  if (readWritePrefixes.length > 0) {
    statements.push({
      Effect: 'Allow',
      Action: ['s3:GetObject', 's3:PutObject', 's3:AbortMultipartUpload'],
      Resource: readWritePrefixes.map((prefix) => `${bucketArn}/${prefix}`),
    });
  }
  if (writeOnlyPrefixes.length > 0) {
    statements.push({
      Effect: 'Allow',
      Action: ['s3:PutObject', 's3:AbortMultipartUpload'],
      Resource: writeOnlyPrefixes.map((prefix) => `${bucketArn}/${prefix}`),
    });
  }
  return {
    Version: '2012-10-17',
    Statement: statements,
  };
}

function buildAssumeRoleInput({ instanceID, ownerID, repoID, durationSeconds, readPrefixes = [], writePrefixes = [] }) {
  const input = {
    RoleArn: runnerRoleArn,
    // The runner role's scoped-cache grants also check aws:userid, whose
    // assumed-role suffix is this RoleSessionName. Role tags can satisfy
    // aws:PrincipalTag, but raw EC2 instance-profile sessions cannot forge
    // this broker-only prefix.
    RoleSessionName: brokeredRoleSessionName(instanceID),
    DurationSeconds: durationSeconds,
    Tags: [
      {
        Key: brokeredTagKey,
        Value: brokeredTagValue,
      },
      {
        Key: repositoryTagKey,
        Value: repositoryPath(ownerID, repoID),
      },
    ],
  };
  // The scoped statements ARE the whole session policy: brokered
  // credentials never leave the agent's cache server, so there is no base
  // boundary to merge and no packed-policy pressure from pass-through
  // statements.
  input.Policy = JSON.stringify(buildSessionPolicy(ownerID, repoID, readPrefixes, writePrefixes));
  if (input.Policy.length > maxAssumeRolePolicyChars) {
    throw new Error(`broker session policy exceeds STS plaintext limit (${input.Policy.length}/${maxAssumeRolePolicyChars} characters)`);
  }
  return input;
}

function sessionDuration(tokenExp) {
  const remaining = Math.floor(tokenExp - Date.now() / 1000);
  // STS AssumeRole floors DurationSeconds at 900, so near token expiry the
  // session may outlive the token by up to 15 minutes rather than refusing
  // to mint. Token expiry itself is enforced by JWT validation upstream.
  return Math.max(900, Math.min(sessionDurationSeconds, remaining));
}

function normalizeRoleSessionName(raw) {
  if (typeof raw !== 'string') {
    throw new Error('instance_id is invalid');
  }
  const instanceID = raw.trim();
  if (!/^i-[A-Fa-f0-9]{8,32}$/.test(instanceID)) {
    throw new Error('instance_id is invalid');
  }
  return instanceID;
}

function brokeredRoleSessionName(instanceID) {
  return `${brokeredSessionNamePrefix}${normalizeRoleSessionName(instanceID)}`;
}

function base64urlDecode(value) {
  return Buffer.from(value, 'base64url');
}

function normalizeOptionalURL(raw) {
  const value = String(raw || '').trim();
  if (value === '') {
    return '';
  }
  const parsed = new URL(value);
  if (parsed.protocol !== 'https:') {
    throw new Error('GitHub URL must use https');
  }
  return parsed.toString().replace(/\/+$/, '');
}

function bucketNameFromArn(arn) {
  const parts = arnParts(arn, 'CACHE_BUCKET_ARN');
  if (parts[2] !== 's3' || parts[5] === '') {
    throw new Error('CACHE_BUCKET_ARN is invalid');
  }
  return parts.slice(5).join(':');
}

function accountIDFromArn(arn) {
  const parts = arnParts(arn, 'RUNNER_ROLE_ARN');
  if (!/^\d{12}$/.test(parts[4])) {
    throw new Error('RUNNER_ROLE_ARN is invalid');
  }
  return parts[4];
}

function partitionFromArn(arn) {
  return arnParts(arn, 'RUNNER_ROLE_ARN')[1];
}

function roleNameFromArn(arn) {
  const marker = ':role/';
  if (typeof arn !== 'string' || !arn.includes(marker)) {
    return '';
  }
  const rolePath = arn.slice(arn.indexOf(marker) + marker.length);
  const parts = rolePath.split('/').filter(Boolean);
  return parts[parts.length - 1] || '';
}

function arnParts(arn, name) {
  if (typeof arn !== 'string') {
    throw new Error(`${name} is invalid`);
  }
  const parts = arn.split(':');
  if (parts.length < 6 || parts[0] !== 'arn' || parts[1] === '') {
    throw new Error(`${name} is invalid`);
  }
  return parts;
}

const partitionDNSSuffixes = {
  'aws-cn': 'amazonaws.com.cn',
  'aws-eusc': 'amazonaws.eu',
  'aws-iso': 'c2s.ic.gov',
  'aws-iso-b': 'sc2s.sgov.gov',
};

function stsHostnamesForRegion(partition, region) {
  const dnsSuffix = partitionDNSSuffixes[partition] || 'amazonaws.com';
  return [`sts.${region}.${dnsSuffix}`, `sts.${dnsSuffix}`];
}

module.exports = {
  handler,
  buildAssumeRoleInput,
  buildSessionPolicy,
  instanceIDFromCallerUserID,
  normalizeAccessControls,
  normalizeCallerIdentityProof,
  normalizeEvent,
  normalizeRoleSessionName,
  prefixesFor,
  repositoryPath,
  scopeSegment,
  sessionDuration,
  setS3ClientForTesting,
  stsHostnamesForRegion,
  tokenRepositoryIDs,
  validateRuntimeToken,
  validateCallerIdentityProof,
};
