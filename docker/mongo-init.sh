# Creates the least-privilege application user on a brand-new volume.
#
# The mongo entrypoint sources every *.sh in this directory once, right
# after it has created the root user from MONGO_INITDB_ROOT_* — and only
# while /data/db is empty. That is why an already-populated volume never
# runs this file: see the "Enabling auth on an existing host" runbook in
# the README for creating the users by hand on a deployed host.
#
# The guards make every step "create if missing", so the same snippet the
# runbook tells a human to paste into a mongosh session can also be run
# against a database that already has the users without failing.
#
# Passwords are interpolated into mongosh here and into mongodump's argv
# in scripts/backup.sh, so they must stay free of quotes, $ and backticks;
# generate them with `openssl rand -hex 16`.

set -euo pipefail

mongosh --quiet \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "
const appDb = db.getSiblingDB('$MONGO_APP_DATABASE');
if (!appDb.getUser('$MONGO_APP_USER')) {
  appDb.createUser({
    user: '$MONGO_APP_USER',
    pwd:  '$MONGO_APP_PASSWORD',
    // readWrite alone is enough for everything api and file do: it grants
    // collection creation and createIndex as a side effect of write.
    roles: [{ role: 'readWrite', db: '$MONGO_APP_DATABASE' }],
  });
  print('created application user ' + '$MONGO_APP_USER');
} else {
  print('application user ' + '$MONGO_APP_USER' + ' already exists');
}
"
