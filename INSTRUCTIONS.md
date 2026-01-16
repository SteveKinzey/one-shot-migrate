# INSTRUCTIONS — one-shot-migrate (v1.1.1)

## Dialog run (recommended)
Double-click **Install.command** and follow prompts (preset, edit excludes, DRYRUN/RUN, VERIFY, background run).

## Terminal run

```bash
chmod +x ./one-shot-migrate.sh
cd ~/one-shot-migrate
DRYRUN=1 ./one-shot-migrate.sh
nohup ./one-shot-migrate.sh > ~/migration_logs/one_shot_run.out 2>&1 &
tail -n 80 ~/migration_logs/one_shot_run.out
tail -f ~/migration_logs/one_shot_run.out
```

Stop:
```bash
pkill -f one-shot-migrate.sh
pkill -f rsync
```

Resume:
```bash
cd ~/one-shot-migrate
nohup ./one-shot-migrate.sh > ~/migration_logs/one_shot_run.out 2>&1 &
```

Verification:
```bash
VERIFY=1 ./one-shot-migrate.sh
VERIFY=0 ./one-shot-migrate.sh
```

Presets:
```bash
cp -f ./presets/developer-heavy.txt ./exclude.txt
open -t ./exclude.txt
```

Troubleshooting:
```bash
xcode-select --install
```
