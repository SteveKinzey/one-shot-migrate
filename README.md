# one-shot-migrate (v1.1.1)

Data-only macOS user migration helper.

- Prompts for OLD + NEW usernames
- Copies: Desktop, Documents, Downloads, Pictures, Movies, Music
- Skips `~/Library` by default to avoid dragging broken per-user state
- Guided UX via **Install.command**
- Optional checksum verification pass (default on)

## Quick start using Terminal
```bash
chmod +x ./one-shot-migrate.sh
DRYRUN=1 ./one-shot-migrate.sh
nohup ./one-shot-migrate.sh > ~/migration_logs/one_shot_run.out 2>&1 &
tail -n 80 ~/migration_logs/one_shot_run.out
```

## License
MIT License. See the LICENSE file for details.