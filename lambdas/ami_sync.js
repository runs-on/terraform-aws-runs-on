'use strict';

// Scheduled cross-region AMI syncer.
//
// Copies the most-recent RunsOn-published AMIs from a source region (where RunsOn
// publishes, default us-east-1) into this Lambda's own region ("self"), tagging
// both the image and its snapshot at create time, then prunes older synced copies
// down to a retention count. The RunsOn control-plane AMI finder queries
// "self" + the public RunsOn owner, so once these copies exist every product
// running in the region resolves them with no extra wiring.
//
// Driven entirely by its event/env (see configFromEvent); the canonical caller is
// the ami_sync Terraform module (scheduler + seed invocation).

const EC2_SDK = '@aws-sdk/client-ec2';

const DEFAULT_SOURCE_REGION = 'us-east-1';
const DEFAULT_SOURCE_OWNER = '135269210855';
const DEFAULT_RETENTION = 2;

// Sync-specific tag keys (JS literals mirroring the runs-on-* tag vocabulary in
// pkg/ec2meta/tag.go; the three sync-specific keys are not Go constants on main).
const TAG_AMI_SYNC = 'runs-on-ami-sync';
const TAG_AMI_SOURCE_ID = 'runs-on-ami-source-id';
const TAG_AMI_SOURCE_REGION = 'runs-on-ami-source-region';
const TAG_AMI_NAME = 'runs-on-ami-name';
const TAG_STACK_NAME = 'runs-on-stack-name';
const TAG_PROVIDER = 'provider';

function log(level, message, fields = {}) {
  const rendered = JSON.stringify({ level, message, ...fields });
  if (level === 'error') {
    console.error(rendered);
  } else if (level === 'warn') {
    console.warn(rendered);
  } else {
    console.log(rendered);
  }
}

function trimString(value) {
  return String(value === undefined || value === null ? '' : value).trim();
}

// createDefaultAws lazily builds region-scoped EC2 clients. The source client is
// pinned to sourceRegion; the dest client uses the Lambda runtime region.
function createDefaultAws() {
  let sdk;
  const clients = new Map();

  function clientFor(region) {
    if (!sdk) {
      sdk = require(EC2_SDK);
    }
    if (!clients.has(region)) {
      clients.set(region, new sdk.EC2Client(region ? { region } : {}));
    }
    return { client: clients.get(region), sdk };
  }

  async function send(region, commandName, params) {
    const { client, sdk: loaded } = clientFor(region);
    return client.send(new loaded[commandName](params));
  }

  return {
    describeImages: (region, params) => send(region, 'DescribeImagesCommand', params),
    describeSnapshots: (region, params) => send(region, 'DescribeSnapshotsCommand', params),
    copyImage: (region, params) => send(region, 'CopyImageCommand', params),
    deregisterImage: (region, params) => send(region, 'DeregisterImageCommand', params),
    deleteSnapshot: (region, params) => send(region, 'DeleteSnapshotCommand', params),
  };
}

// configFromEvent resolves config from the event (flat, as the scheduler/seed
// deliver it) with a nested `event.input` fallback, then env vars. The image list
// and user tags are passed in by value; everything else has an env default.
function configFromEvent(event = {}, env = process.env) {
  const nested = event && typeof event.input === 'object' && event.input ? event.input : {};
  const get = (key) => (event[key] !== undefined ? event[key] : nested[key]);

  const images = Array.isArray(get('images')) ? get('images') : [];
  const tags = get('tags') && typeof get('tags') === 'object' ? get('tags') : {};

  let retention = parseInt(trimString(get('retention') || env.RUNS_ON_AMI_SYNC_RETENTION), 10);
  if (!Number.isInteger(retention) || retention < 1) {
    retention = DEFAULT_RETENTION;
  }

  return {
    images: images
      .map((image) => ({
        name: trimString(image && image.name),
        architecture: trimString(image && image.architecture) || 'x86_64',
      }))
      .filter((image) => image.name),
    tags,
    sourceRegion: trimString(get('sourceRegion') || env.RUNS_ON_AMI_SYNC_SOURCE_REGION) || DEFAULT_SOURCE_REGION,
    sourceOwner: trimString(get('sourceOwner') || env.RUNS_ON_AMI_SOURCE_OWNER) || DEFAULT_SOURCE_OWNER,
    stackName: trimString(get('stackName') || env.RUNS_ON_STACK_NAME),
    kmsKeyId: trimString(get('kmsKeyId') || env.RUNS_ON_KMS_KEY_ID),
    retention,
    destRegion: trimString(env.AWS_REGION || env.AWS_DEFAULT_REGION),
  };
}

function tagsToMap(tags = []) {
  const map = {};
  for (const tag of tags) {
    if (tag && tag.Key) {
      map[tag.Key] = tag.Value;
    }
  }
  return map;
}

// hasTag reports whether a tagged resource (image/snapshot) carries key=value.
function hasTag(resource, key, value) {
  return (resource.Tags || []).some((tag) => tag && tag.Key === key && tag.Value === value);
}

// mostRecentByName sorts a copy of the images most-recent-first by Name. RunsOn
// names end with a date/version suffix, so lexicographic descending == newest.
function mostRecentByName(images = []) {
  return [...images].sort((a, b) => {
    const an = trimString(a.Name);
    const bn = trimString(b.Name);
    if (an === bn) return 0;
    return an > bn ? -1 : 1;
  });
}

// resolveSourceImage finds the newest matching RunsOn AMI in the source region.
async function resolveSourceImage(aws, config, image) {
  const resp = await aws.describeImages(config.sourceRegion, {
    Owners: [config.sourceOwner],
    Filters: [
      { Name: 'name', Values: [image.name] },
      { Name: 'architecture', Values: [image.architecture] },
      { Name: 'state', Values: ['available'] },
    ],
  });
  const images = mostRecentByName(resp.Images || []);
  return images.length > 0 ? images[0] : null;
}

// deregisterCopy deregisters a synced AMI and deletes its backing snapshots.
async function deregisterCopy(aws, config, image) {
  const imageId = trimString(image.ImageId);
  const snapshotIds = (image.BlockDeviceMappings || [])
    .map((mapping) => mapping.Ebs && trimString(mapping.Ebs.SnapshotId))
    .filter(Boolean);

  await aws.deregisterImage(config.destRegion, { ImageId: imageId });
  for (const snapshotId of snapshotIds) {
    await aws.deleteSnapshot(config.destRegion, { SnapshotId: snapshotId });
  }
  return { imageId, snapshotIds };
}

// hasUsableCopy reports whether an available/pending self-owned synced copy of the
// exact source name already exists in the dest region. This is the fast idempotency
// guard. Scheduler/Lambda delivery is at least once, so a concurrent CopyImage can
// still lose the unique-name race and fail harmlessly; a Lambda retry then sees the
// winning pending/available copy here.
// AMI names are unique per account/region, so a copy left in a terminal failure
// state still holds the name and would block the retry's CopyImage — clean those
// up here so the name is free.
async function hasUsableCopy(aws, config, sourceName) {
  const resp = await aws.describeImages(config.destRegion, {
    Owners: ['self'],
    Filters: [
      { Name: 'name', Values: [sourceName] },
      { Name: `tag:${TAG_AMI_SYNC}`, Values: ['true'] },
    ],
  });
  const images = resp.Images || [];

  // The presence check is intentionally not stack-scoped: AMI names are unique per
  // account/region, so a same-named copy from any stack means we must not copy again
  // (a duplicate-name CopyImage would fail).
  if (images.some((img) => img.State === 'available' || img.State === 'pending')) {
    return true;
  }

  // Cleanup, however, only deregisters our own stack's failed copies — the IAM
  // policy permits DeregisterImage only for runs-on-stack-name = this stack, so
  // touching another stack's failed copy would AccessDenied and fail the run.
  for (const img of images) {
    if (
      ['failed', 'error', 'invalid'].includes(String(img.State)) &&
      hasTag(img, TAG_STACK_NAME, config.stackName)
    ) {
      const { imageId, snapshotIds } = await deregisterCopy(aws, config, img);
      log('warn', 'Cleaned up failed synced AMI copy before retry', {
        ami: imageId,
        name: sourceName,
        state: String(img.State),
        snapshots: snapshotIds,
      });
    }
  }
  return false;
}

// copyImage starts a CopyImage into the dest region, tagging the image and its
// snapshot at create time (tag-on-create is what satisfies a tag-enforcing SCP).
async function copyImage(aws, config, sourceImage) {
  const sourceId = trimString(sourceImage.ImageId);
  const sourceName = trimString(sourceImage.Name);

  // Merge user tags first, then the canonical runs-on-* tags, so the canonical
  // values win on any key collision and EC2 never sees a duplicate tag key
  // (CopyImage rejects duplicate keys, which would wedge the whole copy).
  const tagMap = {};
  for (const [key, value] of Object.entries(config.tags)) {
    if (trimString(key)) {
      tagMap[key] = trimString(value);
    }
  }
  tagMap[TAG_AMI_SYNC] = 'true';
  tagMap[TAG_AMI_SOURCE_ID] = sourceId;
  tagMap[TAG_AMI_SOURCE_REGION] = config.sourceRegion;
  tagMap[TAG_AMI_NAME] = sourceName;
  tagMap[TAG_STACK_NAME] = config.stackName;
  tagMap[TAG_PROVIDER] = 'runs-on';
  const tags = Object.entries(tagMap).map(([Key, Value]) => ({ Key, Value }));

  const params = {
    Name: sourceName,
    SourceImageId: sourceId,
    SourceRegion: config.sourceRegion,
    Description: `RunsOn cross-region AMI sync of ${sourceId} from ${config.sourceRegion}`,
    TagSpecifications: [
      { ResourceType: 'image', Tags: tags },
      { ResourceType: 'snapshot', Tags: tags },
    ],
  };
  if (config.kmsKeyId) {
    params.Encrypted = true;
    params.KmsKeyId = config.kmsKeyId;
  }

  const out = await aws.copyImage(config.destRegion, params);
  log('info', 'Started cross-region AMI copy', {
    source_ami: sourceId,
    source_region: config.sourceRegion,
    name: sourceName,
    copied_ami: trimString(out.ImageId),
  });
  return trimString(out.ImageId);
}

// prune deregisters older synced copies of this image family (the configured name
// glob + architecture), keeping the newest `retention`, and deletes their backing
// snapshots. Scoped to this stack's own self-owned, sync-tagged, available images
// only — the runs-on-stack-name filter keeps prune aligned with the IAM policy
// (which only permits DeregisterImage/DeleteSnapshot for this stack's tag), so a
// second syncer or a renamed stack can't make prune pick an AMI it can't delete.
async function prune(aws, config, image) {
  const resp = await aws.describeImages(config.destRegion, {
    Owners: ['self'],
    Filters: [
      { Name: 'name', Values: [image.name] },
      { Name: 'architecture', Values: [image.architecture] },
      { Name: 'state', Values: ['available'] },
      { Name: `tag:${TAG_AMI_SYNC}`, Values: ['true'] },
      { Name: `tag:${TAG_STACK_NAME}`, Values: [config.stackName] },
    ],
  });

  const sorted = mostRecentByName(resp.Images || []);
  const stale = sorted.slice(config.retention);
  let pruned = 0;

  for (const img of stale) {
    const { imageId, snapshotIds } = await deregisterCopy(aws, config, img);
    pruned += 1;
    log('info', 'Pruned stale synced AMI copy', {
      ami: imageId,
      name: trimString(img.Name),
      snapshots: snapshotIds,
    });
  }
  return pruned;
}

// sweepOrphanedSnapshots deletes this stack's synced snapshots that are no longer
// backed by any synced AMI. deregisterCopy deregisters the AMI before deleting its
// snapshots (a snapshot in use by a registered AMI can't be deleted), so a transient
// DeleteSnapshot failure would otherwise orphan the snapshot — undiscoverable via
// DescribeImages and never retried. This tag-scoped sweep reclaims those each run.
async function sweepOrphanedSnapshots(aws, config) {
  const resp = await aws.describeSnapshots(config.destRegion, {
    OwnerIds: ['self'],
    Filters: [
      { Name: `tag:${TAG_AMI_SYNC}`, Values: ['true'] },
      { Name: `tag:${TAG_STACK_NAME}`, Values: [config.stackName] },
    ],
  });
  const snapshots = resp.Snapshots || [];
  if (snapshots.length === 0) {
    return 0;
  }

  // Snapshot IDs still backing a synced AMI we own (pending copies included).
  const imagesResp = await aws.describeImages(config.destRegion, {
    Owners: ['self'],
    Filters: [{ Name: `tag:${TAG_AMI_SYNC}`, Values: ['true'] }],
  });
  const referenced = new Set();
  for (const img of imagesResp.Images || []) {
    for (const mapping of img.BlockDeviceMappings || []) {
      if (mapping.Ebs && mapping.Ebs.SnapshotId) {
        referenced.add(trimString(mapping.Ebs.SnapshotId));
      }
    }
  }

  let deleted = 0;
  for (const snapshot of snapshots) {
    const snapshotId = trimString(snapshot.SnapshotId);
    if (snapshotId && !referenced.has(snapshotId)) {
      await aws.deleteSnapshot(config.destRegion, { SnapshotId: snapshotId });
      deleted += 1;
      log('warn', 'Deleted orphaned synced snapshot', { snapshot: snapshotId });
    }
  }
  return deleted;
}

async function syncImage(aws, config, image) {
  const sourceImage = await resolveSourceImage(aws, config, image);
  if (!sourceImage) {
    // A configured image with no matching source (typo, wrong owner/region, or an
    // unpublished image) is an error, not a skip: otherwise the run reports success
    // while runners in unsupported regions keep failing with "no AMI found".
    throw new Error(
      `no source AMI found for ${image.name} (${image.architecture}) in ${config.sourceRegion}`,
    );
  }

  const sourceName = trimString(sourceImage.Name);
  let copied = 0;
  let skipped = 0;

  if (await hasUsableCopy(aws, config, sourceName)) {
    skipped = 1;
    log('info', 'Copy already present; skipping', { name: sourceName });
  } else {
    await copyImage(aws, config, sourceImage);
    copied = 1;
  }

  // Prune every run so retention reductions converge without requiring a new copy.
  const pruned = await prune(aws, config, image);
  return { copied, skipped, pruned };
}

async function performSync(event, options = {}) {
  const config = configFromEvent(event, options.env || process.env);
  const aws = options.aws || createDefaultAws();

  if (config.images.length === 0) {
    log('warn', 'No images configured; nothing to sync');
    return { copied: 0, skipped: 0, pruned: 0, errored: 0, errors: [] };
  }

  // Same-region deployment has nothing to copy: skip rather than self-copy.
  if (config.sourceRegion === config.destRegion) {
    log('info', 'Source region equals destination region; nothing to sync', {
      region: config.destRegion,
    });
    return { copied: 0, skipped: 0, pruned: 0, errored: 0, errors: [] };
  }

  const summary = { copied: 0, skipped: 0, pruned: 0, snapshotsSwept: 0, errored: 0, errors: [] };
  for (const image of config.images) {
    try {
      const result = await syncImage(aws, config, image);
      summary.copied += result.copied;
      summary.skipped += result.skipped;
      summary.pruned += result.pruned;
    } catch (error) {
      const message = String((error && error.message) || error);
      summary.errored += 1;
      summary.errors.push({ name: image.name, architecture: image.architecture, error: message });
      log('error', 'Failed to sync image', {
        name: image.name,
        architecture: image.architecture,
        error: message,
      });
    }
  }

  // Best-effort orphaned-snapshot reclamation. A failure here is logged but not
  // fatal: the sweep is idempotent, so the next run reclaims whatever was missed.
  try {
    summary.snapshotsSwept = await sweepOrphanedSnapshots(aws, config);
  } catch (error) {
    log('warn', 'Orphaned-snapshot sweep failed; will retry next run', {
      error: String((error && error.message) || error),
    });
  }

  log('info', 'AMI sync complete', summary);

  // Every image was attempted; now fail the invocation if any errored so the
  // Lambda Errors metric and the synchronous Terraform seed see it. EventBridge
  // Scheduler invokes Lambda asynchronously, so Lambda owns scheduled retries.
  if (summary.errored > 0) {
    const error = new Error(
      `AMI sync completed with ${summary.errored} image error(s): ${JSON.stringify(summary.errors)}`,
    );
    error.summary = summary;
    throw error;
  }
  return summary;
}

async function createHandler(event, options = {}) {
  try {
    return await performSync(event, options);
  } catch (error) {
    log('error', 'AMI sync failed', { error: String((error && error.message) || error) });
    throw error;
  }
}

module.exports = {
  configFromEvent,
  createHandler,
  performSync,
  prune,
  sweepOrphanedSnapshots,
  syncImage,
  tagsToMap,
  mostRecentByName,
  handler: (event) => createHandler(event),
};
