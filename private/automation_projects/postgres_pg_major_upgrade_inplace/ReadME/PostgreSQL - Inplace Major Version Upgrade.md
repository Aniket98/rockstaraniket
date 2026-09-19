# PostgreSQL - In-Place Major Version Ugprade

OS: Linux Rocky 8

## Prechecks

Assumption 1: You have already manually installed required postgres packages for New PG Version.
Assumption 2: OS is Rocky Linux

-- STEP 1: Variables Validation

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

-- Step 3: Check Extensions

7. In Old PG, check installed extensions in each database. If any installed extension is found to be out of contrib package, then stop automation, mark step FAILED. Ask user to do manual check.

-- Step 3: Take backups of conf files

8. Under PG_RUN_ID_R$N directory, create a new directory 'backups'.
   Create sub-directories:
   		|_ backups/old_PG_$OLDVERSION_datadir_confs
   		|_ backups/old_PG_$OLDVERSION_systemctl_confs
   		|_ backups/prepared_PG_$NEWVERSION_datadir_confs
   		|_ backups/prepared_PG_$NEWVERSION_systemctl_confs
9. Start copying:
		cp -a OLD_DATA_DIR/*conf* backups/old_PG_$OLDVERSION_datadir_confs
		cp -a /usr/lib/systemd/system/postgresql-$OLDVERSION.service backups/old_PG_$OLDVERSION_systemctl_confs

-- Step 4: Prepare New PG Version conf files

10. Under PG_RUN_ID_R$N/backups/
   Create sub-directories:
   		|_ backups/prepared_PG_$NEWVERSION_datadir_confs
   		|_ backups/prepared_PG_$NEWVERSION_systemctl_confs
11. pg_hba.conf can be copied as it is from Old PG Version
		cp ....................

-- Step 3: Create New PG Version Cluster

6. From Old postgres cluster, collect values required for INIT:
	encoding
	lc collate
	lc char
	datachecksums
	+ check more
7. Do init for New PG Version in NEW_DATA_DIR

-- Step 4:


## Upgrade



## Post Upgrade


