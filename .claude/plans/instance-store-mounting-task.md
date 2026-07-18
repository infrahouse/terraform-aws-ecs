# Task: add instance-store (local NVMe) mounting to terraform-aws-ecs

**Status:** proposed
**Priority:** MEDIUM — niche demand, but it gates a public commitment (see "Why now")
**Module:** terraform-aws-ecs

## Why now

Experiment 1 measured that per-node model distribution is **disk-write-bound**: uncapped, a
node landed 1.05 Gbit/s (= 125 MB/s = the gp3 default), while the same fetch to `/dev/null`
moved ≥ 4.4 Gbit/s. The network and S3 deliver ~4× what a default gp3 root volume can absorb.
(Full data: `test_data/experiment1/BENCHMARK.md`.)

The module writes the model to the **root EBS volume** and offers no way to use the
instance's local NVMe — a `g5.2xlarge` has 450 GB of NVMe sitting idle. Experiment 2's
README notes this as a forced deviation: "root EBS, not instance-store NVMe — the module
exposes no instance-store mounting."

Blog Post 3 ("your model download is disk-bound") will say instance-store mounting is **on
the roadmap**. That line needs a real, tracked commitment behind it, not vaporware. Opening
this issue is what makes "on the roadmap" true.

## Problem

- Model / data writes go to root gp3 at its 125 MB/s default.
- Instances with local NVMe (g5, g6, c5d, i3, i4i, m6id, ...) leave that NVMe unused.
- No knob to format + mount the NVMe and point the workload's data dir at it.

## Ask

Add an opt-in that, on instances with instance-store NVMe, formats and mounts it and exposes
a path a task can write the model (and any throughput-sensitive data) to.

## Design sketch (for whoever picks this up)

- New variable, e.g. `enable_instance_store` (bool, default false) + optional `instance_store_mount_path`
  (default `/mnt/instance-store`).
- In the launch template user-data / cloud-init: detect NVMe instance-store devices (they are
  distinct from the EBS root — enumerate via `nvme list` / `lsblk` by model, or the AWS NVMe
  ephemeral device symlinks), `mkfs` and mount at the path. If the instance has no instance
  store, no-op cleanly (don't fail the boot).
- Ephemeral by nature: reformat/remount on every boot; never assume prior contents. This is
  correct for a model re-pulled on scale-out.
- Multiple NVMe volumes: optional RAID0 (stretch goal), or just mount the first.
- ECS wiring: expose the mount so a task can bind-mount it (or point the model dir / a volume
  at it). Decide whether it's a host bind mount the task references, or a module-managed
  volume.
- Default OFF — this is a lever for throughput-sensitive fleets (model serving/distribution),
  not the common case. For most fleets gp3 default is fine; a simpler alternative is
  provisioning gp3 `throughput`/`iops`, which the module could also surface.

## Acceptance criteria

- With the flag set on an NVMe-bearing instance (e.g. g5.2xlarge), the model dir resolves to
  the local NVMe mount, and measured write throughput exceeds the gp3 default (target: the
  ~4 Gbit/s the network/S3 can feed, from the Experiment 1 sink run).
- With the flag set on an instance with no instance store, boot succeeds and falls back to
  EBS (no-op, logged).
- Docs: variable reference + a note on ephemerality and when to use it.

## Side benefit

Unblocks Experiment 1's optional instance-store measurement — the rig currently can't mount
NVMe, which is exactly this gap. Once shipped, the disk-fix number in Post 3 can be measured
instead of modeled.

## Next step

Open a GitHub issue on `infrahouse/terraform-aws-ecs` mirroring this, so Post 3's "on the
roadmap" points at a real, linkable commitment before it publishes.
