# Creates the least-privilege application user on a brand-new volume.
#
# The mongo entrypoint sources every *.sh in this directory once, right
# after it has created the root user from MONGO_INITDB_ROOT_* — and only
# while /data/db is empty. That is why an already-populated volume never
# runs this file: see the "Enabling auth on an existing host" runbook in
# the README for creating the users by hand on a deployed host.
#
# The guards make every step "create if missing", so this also runs unharmed
# against a database that already has the users.
#
# The credentials are read from the environment inside mongosh instead of
# being interpolated into the script text, so a password containing a quote
# stays data rather than becoming code. The README runbook does interpolate
# them, so keep generating anything pasted there with `openssl rand -hex 16`.
#
# The eval string is double-quoted only because the JavaScript below is full
# of single quotes; nothing is interpolated into it, so the shell has no `$`
# to expand.

set -euo pipefail

mongosh --quiet \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "
const appDb = db.getSiblingDB(process.env.MONGO_APP_DATABASE);
if (!appDb.getUser(process.env.MONGO_APP_USER)) {
  appDb.createUser({
    user: process.env.MONGO_APP_USER,
    pwd:  process.env.MONGO_APP_PASSWORD,
    // readWrite alone is enough for everything api and file do: it grants
    // collection creation and createIndex as a side effect of write.
    roles: [{ role: 'readWrite', db: process.env.MONGO_APP_DATABASE }],
  });
  print('created application user ' + process.env.MONGO_APP_USER);
} else {
  print('application user ' + process.env.MONGO_APP_USER + ' already exists');
}
"
