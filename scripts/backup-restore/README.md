# backup-restore

Aurora (pg_dump/pg_restore) + DocumentDB (mongodump/mongorestore) + S3
static-assets backup and restore for the mall data stores. `backup.sh` writes a
single `mall-data-backup-<region>-<timestamp>.tar.gz` (with a `manifest.json`)
into the private backups bucket; `restore.sh` restores from one such archive.
Both run as Kubernetes Jobs (`k8s/jobs/`) under per-direction IRSA roles
(`mall-apne2-backup` / `mall-apne2-restore`, see `shared/main.tf`).

## Prerequisites

1. **The `mall/core/aurora` Secrets Manager entry must exist.** The Jobs read
   `AURORA_PASSWORD` from the `order-secrets` ExternalSecret, which sources
   `mall/core/aurora` — an entry that does **not** exist in the live account as
   of this PR (see `docs/portability-assessment.md`). Without it the Job pod
   never starts (`CreateContainerConfigError`). Create it once per account:

   ```bash
   aws secretsmanager create-secret \
     --region ap-northeast-2 \
     --name mall/core/aurora \
     --secret-string '{"host":"<aurora-cluster-endpoint>","port":"5432","dbname":"mall","username":"mall_admin","password":"<password>"}'
   ```

   Follow-up (tracked): backups should run under a dedicated read-only DB
   principal instead of `mall_admin` — the backup Job does not need write
   access to Aurora at all.

2. **The container image.** `bash build-and-push.sh` builds and pushes
   `shopping-mall/backup-restore` to ECR (the repository itself is managed by
   `ecr.tf` — do not create it by hand).

3. **Restore target must be writable.** Korea's DocumentDB is a read-only
   global-cluster secondary; `restore.sh`'s `assert_docdb_writable` (and the
   symmetric Aurora guard) abort on read-only targets by design. Restore into
   the us-east-1 primary, or promote the Korea cluster first
   (`aws docdb remove-from-global-cluster`). On a genuinely standalone target
   (fresh account) the topology query returns nothing — that is fail-closed
   too; set `ALLOW_NO_GLOBAL_CLUSTERS=1` only after verifying the target is
   not part of any global cluster.

## Running

```bash
# backup (fill in <AWS_ACCOUNT_ID> placeholders first)
kubectl apply -f k8s/jobs/backup-job.yaml

# restore — edit the env block first: ARCHIVE_S3_URI, a WRITABLE
# DOCUMENTDB_HOST cluster endpoint, and STATIC_ASSETS_BUCKET
kubectl apply -f k8s/jobs/restore-job.yaml
```

`restore.sh` is fail-fast: the first failing destructive step aborts the run
(the target may then be partially restored — fix the cause and re-run the full
restore from the same archive), and a target that would be skipped because its
env var is unset also aborts unless `ALLOW_PARTIAL_RESTORE=1`. An archive whose
manifest records failed/skipped targets is refused outright by
`assert_manifest_complete` (same override).

## Known limitations (documented, tracked as follow-ups)

- Aurora and DocumentDB are dumped sequentially with no write quiesce — the
  manifest records the window, but cross-store consistency at a single point
  in time is NOT guaranteed. Not suitable as the only recovery mechanism for
  money-path data.
- The backups bucket is same-region with a 90-day expiry and the backup is a
  one-shot `Job` (no schedule, no failure alarm) — RPO is undefined until a
  CronJob + alarm exist.
- Valkey/MSK/OpenSearch are not in the archive — re-seed via
  `scripts/seed-data/` after a restore.

## Self-checks

```bash
bash restore.sh --self-check   # exercises the guards without touching AWS
```
