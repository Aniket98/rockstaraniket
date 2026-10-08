Automation Project: PostgreSQL Major Version Upgrade (In-Place)
Author: Aniket Tomar
Email: workwithaniket@hotmail.com
Supported OS: Rocky 8

---------------
Versioning:

mark1 - 19sept2026
	|_ initial draft
	|_ a working framework with dummy upgrade steps



---------------


# Structure

postgres_pg_major_upgrade_inplace/
│
├── scripts/
│   ├── postgres_pg_major_upgrade_inplace.sh
│   └── destroy.sh
│
├── config/
│   └── pgupgrade.conf
│
└── runs/
    ├── PG_RUN_ID_R1/
    │   ├── prechecks/
    │   │       ├── 001_check_old_bin_installed.SUCCESS
    │   │       ├── 002_check_new_bin_installed.SUCCESS
    │   │       └── PRECHECKS_OK
    │   │
    │   └── upgrade/
    │           ├── 001_stop_postgres.SUCCESS
    │           ├── 002_backup_configuration.SUCCESS
    │           └── 003_run_pg_upgrade.WIP
    │
    └── PG_RUN_ID_R2/
        ├── prechecks/
        └── upgrade/

# Commands (CLI)

```bash
# init
./scripts/postgres_pg_major_upgrade_inplace.sh init

# prechecks
./scripts/postgres_pg_major_upgrade_inplace.sh prechecks --runid=new
./scripts/postgres_pg_major_upgrade_inplace.sh prechecks --runid=R1

# upgrade
./scripts/postgres_pg_major_upgrade_inplace.sh upgrade --runid=R1 --mode=copy
./scripts/postgres_pg_major_upgrade_inplace.sh upgrade --runid=R1 --mode=link

# destroy RUN ID files
./scripts/destroy.sh --runid=R1
```

