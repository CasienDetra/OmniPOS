#!/bin/bash
# Backup loop for the `backup` compose service; runs inside the mongo:7
# container, not on the host, so it travels with the deploy bundle and the
# mongodump version always matches the server.
#
# Each round writes two artifacts into /backups (a host directory mounted
# from BACKUP_DIR, outside every docker volume):
#
#   pos-<UTC-stamp>.dump.gz     mongodump --archive --gzip of the pos database
#   uploads-<UTC-stamp>.tgz     tar.gz of the whole file-uploads volume
#
# Both land as *.part first and are renamed only after success, so neither
# the pruner nor a human ever mistakes a half-written archive for a good
# one. BACKUP_KEEP files of each kind survive; older ones are deleted.
set -euo pipefail

db="${MONGO_DATABASE:-pos}"
interval="${BACKUP_INTERVAL_SECONDS:-21600}"
keep="${BACKUP_KEEP:-14}"
out="${BACKUP_DIR:-/backups}"

run_backup() {
  local stamp
  # Sortable UTC stamp: ls|sort below relies on it ordering by time.
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"

  # Every step propagates its own failure with `|| return 1`. The callers
  # below run this function as an `if` condition, which switches errexit off
  # for the whole body - without these, a failed mongodump falls through to
  # the `mv`, publishing a half-written archive as a good one and advancing
  # .last-success over it.
  #
  # --archive with no value streams to stdout; the redirect keeps the .part
  # discipline. Flags rather than a URI so the password never needs percent
  # encoding. Authentication against the app database, as the app user.
  mongodump \
    --host "$MONGO_HOST" --port "$MONGO_PORT" \
    --username "$MONGO_USERNAME" --password "$MONGO_PASSWORD" \
    --authenticationDatabase "$db" \
    --db "$db" --archive --gzip > "$out/pos-$stamp.dump.gz.part" || return 1
  mv "$out/pos-$stamp.dump.gz.part" "$out/pos-$stamp.dump.gz" || return 1

  tar czf "$out/uploads-$stamp.tgz.part" -C /uploads . || return 1
  mv "$out/uploads-$stamp.tgz.part" "$out/uploads-$stamp.tgz" || return 1

  # The only file the healthcheck reads: epoch of the last fully successful
  # round, so a silent failure turns the container red within four intervals.
  date -u +%s > "$out/.last-success.part" || return 1
  mv "$out/.last-success.part" "$out/.last-success" || return 1
}

prune() {
  local pattern
  # Names sort newest-first exactly because the stamp is ISO-compact UTC.
  # NUL-delimited end to end rather than newline: quoting "$out" keeps find
  # correct, but a space in BACKUP_DIR would still let xargs split a name
  # into fragments and rm the wrong paths.
  for pattern in 'pos-*.dump.gz' 'uploads-*.tgz'; do
    find "$out" -maxdepth 1 -type f -name "$pattern" -print0 |
      sort -rz | tail -z -n +"$((keep + 1))" | xargs -r0 rm -f
  done
}

# A failed round leaves a *.part carrying that round's stamp, and the next
# attempt writes a fresh one, so nothing else would ever collect it.
discard_partials() {
  rm -f "$out"/*.part
}

# Replace-or-crash beats silent rot: if the very first round fails because
# the deployment forgot a credential, exit and let the restart policy make
# the container visibly unhealthy instead of idling green forever. Pruning is
# tied to a successful round, so retention can never thin the good archives on
# the strength of a round that did not produce one.
if run_backup; then
  prune
else
  discard_partials
  echo "first backup failed" >&2
  exit 1
fi

trap 'exit 0' TERM INT
while :; do
  # sleep in the background so the TERM trap fires promptly on stop instead
  # of after the remainder of the interval.
  sleep "$interval" &
  wait $!
  if run_backup; then
    prune
  else
    discard_partials
    echo "backup round failed; will retry in ${interval}s" >&2
  fi
done
