# Release Checklist

1. Update CHANGELOG.md and RELEASE_NOTES.md
2. Ensure scripts executable:
   - one-shot-migrate.sh
   - Install.command
3. Zip:
   - one-shot-migrate-<version>.zip
4. Tag + push:
   - git tag <version>
   - git push origin <version>
5. Create GitHub Release and attach ZIP
