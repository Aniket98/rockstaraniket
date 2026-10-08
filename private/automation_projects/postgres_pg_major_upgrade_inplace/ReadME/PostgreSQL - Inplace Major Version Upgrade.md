# PostgreSQL - In-Place Major Version Ugprade

OS: Linux Rocky 8

## Automation Framework

postgres@rocky810:~/automation/tmp3$ tree
.
├── config
│   └── pgupgrade.conf
├── init.sh
├── runs
│   └── PG_RUN_ID_R2
│       ├── prechecks
│       │   ├── 001_check_old_bin_installed.SUCCESS
│       │   ├── 002_check_new_bin_installed.SUCCESS
│       │   ├── 003_check_old_pg_config.SUCCESS
│       │   ├── 004_check_new_pg_config.SUCCESS
│       │   ├── 005_check_old_version.SUCCESS
│       │   ├── 006_check_new_version.SUCCESS
│       │   ├── 007_check_cluster_status.SUCCESS
│       │   ├── 008_check_extensions.SUCCESS
│       │   ├── 009_check_disk_space.SUCCESS
│       │   ├── 010_check_pg_upgrade_compatibility.SUCCESS
│       │   └── PRECHECKS_OK
│       └── upgrade
│           ├── 001_stop_postgres.SUCCESS
│           ├── 002_backup_configuration.SUCCESS
│           ├── 003_copy_or_link_binaries.SUCCESS
│           ├── 004_run_pg_upgrade.SUCCESS
│           ├── 005_start_new_postgres.SUCCESS
│           └── 006_post_upgrade_checks.SUCCESS
└── scripts
    ├── destroy.sh
    └── postgres_pg_major_upgrade_inplace.sh

6 directories, 21 files
postgres@rocky810:~/automation/tmp3$

## Prechecks

Assumption 1: You have already manually installed required postgres packages for New PG Version.
Assumption 2: OS is Rocky Linux

-- STEP 1: Variables Validation

Variables in config/pgupgrade.conf:

PG_OS_USER
PG_OLD_VERSION
PG_NEW_VERSION
OLD_PG_BIN
NEW_PG_BIN
OLD_DATA_DIR
NEW_DATA_DIR
OLD_PG_SYSTEMCTL_SERVICE_NAME
NEW_PG_SYSTEMCTL_SERVICE_NAME

1. Validate the script is running as user PG_OS_USER.
2. Are values defined in config/pgupgrade.conf are VALID?
3. Validate the Binaries Version (OLD/NEW_PG_CONFIG --version) matches with the Entered Variables PG_OLD_VERSION and PG_NEW_VERSTION.
4. Validate NEW_DATA_DIR must be empty and the directory owner is PG_OS_USER.

-- Step 2: Validate New PG Version PostgreSQL Packages

5. Validate New PG Version packages are installed and must be same as Old PG Version installed packages (contrib, server, client, etc)
   If the packages are fine, then mark success. Else mark step as FAILED, and stop automation. Ask user to do manual check.

-- Step 3: Validate extra packages

6. Check if pg_cron for old PG Version is installed. If yes, check if pg_cron is installed for New PG Version as well.
If for New PG Version pg_cron is not installed, then mark step as FAILED and stop automation. Ask user to do manual check. 

-- Step 4: Check Extensions

7. In Old PG, check installed extensions in each database. If any installed extension is found to be out of contrib package, then stop automation, mark step FAILED. Ask user to do manual check.

-- Step 5: Take backups of Old PG Version Cluster conf files

8. Under PG_RUN_ID_R$N directory, create a new directory 'backups'.
   Create sub-directories:
   		|_ backups/old_PG_$OLDVERSION_datadir_confs
   		|_ backups/old_PG_$OLDVERSION_systemctl_confs
9. Start copying:
		cp -a OLD_DATA_DIR/*conf* backups/old_PG_$OLDVERSION_datadir_confs
		cp -a /usr/lib/systemd/system/postgresql-$OLDVERSION.service backups/old_PG_$OLDVERSION_systemctl_confs

-- Step 6: Prepare New PG Version conf files

10. Under PG_RUN_ID_R$N/backups/
   Create sub-directories:
   		|_ backups/prepared_PG_$NEWVERSION_datadir_confs
11. pg_hba.conf and pg_ident.conf can be copied as it is from Old PG Version because these files syntax should not change over NEW PG Version
		cp backup/old_PG_$OLDVERSION_datadir_confs/pg_hba.conf backups/prepared_PG_$NEWVERSION_datadir_confs/
		cp backup/old_PG_$OLDVERSION_datadir_confs/pg_ident.conf backups/prepared_PG_$NEWVERSION_datadir_confs/
12. Now, comes important part how to compare and prepare postgresql.auto.conf
		<<< logic we discussed >>>

-- Step 7: Create New PG Version Cluster

13. From Old postgres cluster, collect values required for INIT:
	encoding
	lc collate
	lc char
	datachecksums
	+ check more
14. Do init for New PG Version in NEW_DATA_DIR

-- Step 8: Copy preapred conf files to NEW PG Cluster

cp backups/prepared_PG_$NEWVERSION_datadir_confs/pg_hba.conf $NEW_DATA_DIR
cp backups/prepared_PG_$NEWVERSION_datadir_confs/pg_ident.conf $NEW_DATA_DIR
cp backups/prepared_PG_$NEWVERSION_datadir_confs/postgresql.auto.conf $NEW_DATA_DIR

-- Step 9: Startup NEW PG Cluster and check logs for any errors

-- Step 10: Run pg_upgrade --checks (for copy mode)
-- Step 11: Run pg_upgrade --checks --link (for link mode)

Make sure to save respective outputs in the steps file generated.

-- Step 12: If all checks OK, then generate PRECHECKS_OK file.


## Upgrade



## Post Upgrade


