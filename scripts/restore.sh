#!/usr/bin/env bash
# Restore POS data from an archive produced by the backup service.
#
#   bash scripts/restore.sh drill [pos-<stamp>.dump.gz]
#   bash scripts/restore.sh restore <pos-<stamp>.dump.gz> [uploads-<stamp>.tgz]
#
# drill is the safe mode and the reason this file exists: it starts a
# throwaway mongo container, restores the dump into it and prints
# per-collection document counts, proving the archive is a backup and not
# a compressed illusion. Run it after every deploy that changes the backup
# service, and at least quarterly. With no argument it drills the newest
# dump found in BACKUP_DIR.
#
# restore is the real thing and is destructive: it stops api and file for its
# duration, drops the live pos database before replaying the archive, and
# unpacking an uploads archive wipes the file-uploads volume first. It asks
# for the word yes unless --yes is given.
#
# Run from the repository / DEPLOY_DIR root. The database name and backup
# directory are read from .env below; the root credentials come from the
# running mongo container's own environment, so they never reach this host.
set -euo pipefail

cd "$(dirname "$0")/.."
# Both settings resolve the way compose resolves them: an exported value wins,
# then the key in this .env, then the default. Hard-coding the database name
# once made the archive match no namespace, and resolving only the database
# name made a no-argument drill search ./backups while the backup service
# wrote elsewhere - both looked healthy while changing nothing.
from_env() {
  local value="${!1:-}"
  if [ -z "$value" ]; then
    value="$(sed -n "s/^$1=//p" .env 2> /dev/null | tail -n 1 || true)"
  fi
  printf '%s' "${value:-$2}"
}
backup_dir="$(from_env BACKUP_DIR ./backups)"
db="$(from_env MONGO_APP_DATABASE pos)"

usage() {
  # Everything above the first line of code, so the header can grow freely.
  awk 'NR > 1 { if ($0 !~ /^#/) exit; print }' "$0"
  exit 2
}

find_newest_dump() {
  find "$backup_dir" -maxdepth 1 -type f -name 'pos-*.dump.gz' | sort | tail -n 1
}

drill() {
  local dump="${1:-$(find_newest_dump)}"
  if [ ! -f "$dump" ]; then
    echo "no dump found in $backup_dir - pass one explicitly" >&2
    exit 1
  fi
  echo "drilling $dump into a throwaway container"
  # The container is created without credentials, so the restore inside it
  # needs none either - and nothing here can touch the running stack.
  local name=pos-restore-drill
  docker rm -f "$name" > /dev/null 2>&1 || true
  # --rm plus this trap: a drill that hangs must not leak a container.
  trap "docker rm -f $name > /dev/null 2>&1 || true" EXIT
  docker run --rm -d --name "$name" mongo:7 > /dev/null
  docker exec -i "$name" mongorestore --gzip --archive --drop \
    --nsInclude "$db.*" < "$dump"
  echo
  echo "== document counts in the restored copy =="
  docker exec "$name" mongosh --quiet "$db" --eval '
    db.getCollectionNames()
      .map((c) => c + ": " + db.getCollection(c).countDocuments({}))
      .join("\n")
  '
  echo
  echo "drill finished: the archive restored. Do the counts look like the"
  echo "shop's data? A restore of an empty-but-valid database is still a"
  echo "failed backup - that judgement is deliberately left to a human."
}

restore() {
  local dump="$1"
  shift
  local uploads="" assume_yes=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --yes) assume_yes=1 ;;
      *) uploads="$1" ;;
    esac
    shift
  done
  if [ ! -f "$dump" ]; then
    echo "dump not found: $dump" >&2
    exit 1
  fi

  echo "THIS REPLACES LIVE DATA."
  echo "  database $db  <- $dump"
  [ -n "$uploads" ] && echo "  uploads volume <- $uploads"
  if [ "$assume_yes" != 1 ]; then
    read -r -p "type 'yes' to proceed: " answer
    [ "$answer" = "yes" ] || { echo "aborted"; exit 1; }
  fi

  echo "--- stopping api and file so nothing writes mid-restore"
  docker compose stop api file

  echo "--- restoring the database via the running mongo container"
  # The root user exists on any host created after auth was introduced; on
  # a pre-auth host the runbook created it first. Either way it lives in
  # the container's environment, so the password never appears on the host.
  #
  # The database is dropped first because --drop clears only the collections
  # the archive contains: anything created since the backup would survive and
  # the database would never return to the snapshot. User records live in
  # admin.system.users, so dropping pos leaves the application user intact.
  docker compose exec -T mongo bash -c '
    set -e
    mongosh --host 127.0.0.1 --quiet \
      -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
      --authenticationDatabase admin \
      --eval "db.getSiblingDB(\"$1\").dropDatabase()"
    mongorestore --host 127.0.0.1 \
      -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
      --authenticationDatabase admin --gzip --archive --drop \
      --nsInclude "$1.*"
  ' restore-db "$db" < "$dump"

  if [ -n "$uploads" ]; then
    echo "--- replacing the uploads volume"
    # Empty the volume, unpack the archive, hand ownership to the uid the
    # file service runs as (see file/Dockerfile). The archive path is passed
    # as an argument instead of being pasted into the program text: a name
    # containing a double quote would otherwise close the argument early and
    # run whatever followed it.
    docker run --rm \
      -v pos_file-uploads:/d \
      -v "$(cd "$(dirname "$uploads")" && pwd):/b:ro" \
      alpine sh -c '
        find /d -mindepth 1 -delete
        tar xzf "$1" -C /d
        chown -R 65534:65534 /d
      ' sh "/b/$(basename "$uploads")"
  fi

  echo "--- starting api and file again"
  docker compose start api file

  # They were stopped, so wait for the apps to bind their ports rather than
  # assuming they were already serving.
  for _ in $(seq 1 30); do
    if docker compose exec -T api /app/probe http://127.0.0.1:3000/readyz > /dev/null 2>&1 \
      && docker compose exec -T file /app/probe http://127.0.0.1:8080/readyz > /dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  echo "--- verifying the live stack agrees"
  docker compose exec -T api /app/probe http://127.0.0.1:3000/readyz
  docker compose exec -T file /app/probe http://127.0.0.1:8080/readyz
  echo "restore complete"
}

case "${1:-}" in
  drill)
    drill "${2:-}"
    ;;
  restore)
    shift
    [ -n "${1:-}" ] || usage
    restore "$@"
    ;;
  *)
    usage
    ;;
esac
