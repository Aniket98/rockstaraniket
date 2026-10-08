# postgres_pg_major_upgrade_inplace

Modular Bash framework for an in-place PostgreSQL major-version upgrade.

The PostgreSQL precheck and upgrade operations are intentionally dummy placeholders for now. The framework for configuration, run IDs, attempts, step state/log files, resume behavior within an attempt, and run destruction is included.

## Bootstrap

```bash
./init.sh
```

## Configure

Edit `config/pgupgrade.conf` and provide the old/new `pg_config` paths and data directories.

## Run

Create a new run and execute dummy prechecks:

```bash
./scripts/postgres_pg_major_upgrade_inplace.sh prechecks --runid=new
```

Rerun prechecks for an existing run ID; the previous `*_LATEST` attempt is archived as `*_OLD`:

```bash
./scripts/postgres_pg_major_upgrade_inplace.sh prechecks --runid=R1
```

Run the dummy upgrade after a successful latest precheck:

```bash
./scripts/postgres_pg_major_upgrade_inplace.sh upgrade --runid=R1 --mode=copy
```

or:

```bash
./scripts/postgres_pg_major_upgrade_inplace.sh upgrade --runid=R1 --mode=link
```

Destroy one run without resetting the global run-number history:

```bash
./scripts/destroy.sh --runid=R1
```

## Step state files

Each step has one file containing its log/output and state suffix:

- `.WIP` = running/incomplete
- `.SUCCESS` = completed successfully
- `.FAILED` = completed but failed

A successful step is skipped on a later execution of the same attempt. Failed steps are retried.
