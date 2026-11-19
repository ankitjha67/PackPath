# Contributing to PackPath

Thanks for your interest in improving PackPath! It's a free, open-source
(MIT) group-navigation app — a Flutter client and a FastAPI backend. This
guide covers how to get set up, the quality bar, and how to send changes.

## Repository layout

```
apps/mobile      Flutter app (iOS + Android)
apps/backend     FastAPI backend (Python 3.11)
infra            docker-compose + .env.example for self-hosting
docs             Architecture, PRD, session findings
designs          Brand / design system
```

## Getting set up

### Backend

```bash
cd apps/backend
python -m venv .venv && . .venv/Scripts/activate   # or .venv/bin/activate
pip install -r requirements-dev.txt
cp ../../infra/.env.example .env                    # set ENVIRONMENT=local
alembic upgrade head                                # needs Postgres + PostGIS + TimescaleDB
uvicorn app.main:app --reload
```

### Mobile

```bash
cd apps/mobile
cp lib/config/env.example.dart lib/config/env.dart  # fill in your server URL / keys
flutter pub get
flutter run
```

The project pins **Flutter 3.41.4** (see `.github/workflows/ci.yml`). Please
match it — newer SDKs surface different lints and APIs than CI accepts.

## Before you open a PR

Run the same checks CI does:

**Backend**

```bash
cd apps/backend
ruff check app
pytest -q
```

**Mobile**

```bash
cd apps/mobile
dart format lib test
flutter analyze
flutter test
```

- Keep `flutter analyze` free of **errors** (warnings/infos are tolerated but
  please don't add new ones).
- `dart format` must leave no diff.
- Add or update tests for behaviour changes where practical.

## Pull request guidelines

- Branch from `main`; keep each PR focused on one thing.
- Write a clear description: what changed and why.
- Use conventional-style commit subjects where you can (`fix:`, `feat:`,
  `docs:`, `refactor:`, `test:`, `style:`).
- Don't commit secrets, API keys, or `lib/config/env.dart`.
- CI (lint, tests, migrations, Android build) must be green before merge.

## Reporting bugs & requesting features

Open a GitHub issue with steps to reproduce (for bugs) or a short description
of the use case (for features). Security-sensitive reports: please avoid
filing a public issue with exploit details — open a minimal issue asking a
maintainer to get in touch, or contact the repository owner directly.

## License

By contributing, you agree that your contributions will be licensed under the
project's [MIT License](LICENSE).
