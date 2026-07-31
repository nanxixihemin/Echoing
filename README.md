# Echoing

> Status: **Current mainline**

`echoing` is the active product in this workspace. All new feature development, bug fixes, backend evolution, and production deployment changes should originate here.

## Structure

```text
echoing/
|-- AppScope/      HarmonyOS application configuration
|-- entry/         ArkTS application module, pages, components, and services
|-- backend/       Python standard-library HTTP API and SQLite persistence
`-- deploy/        systemd, nginx, and environment templates
```

The backend-specific setup and API documentation lives in `backend/README.md`. Deployment instructions live in `deploy/README.md`.

## Repository Policy

- Use this repository as the source of truth for the application and backend.
- Migrate useful ideas from `../In_zzu/` deliberately instead of editing both implementations in parallel.
- Keep deployment worktree changes synchronized through Git branches and commits rather than manual file copying.
