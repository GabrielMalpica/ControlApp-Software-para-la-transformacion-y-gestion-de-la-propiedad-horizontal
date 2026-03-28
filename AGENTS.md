# AGENTS.md

## Scope

- Workspace root: `C:\Users\Acer\Desktop\Proyecto de grado`.
- `controlapp_frontend/`: Flutter client.
- `contorlapp_backend/`: Node.js + TypeScript + Express + Prisma API.
- Root `package.json` only proxies backend install/build/start tasks.
- Keep the folder name `contorlapp_backend` as-is; the typo is part of the repo.

## Instruction Sources

- Existing root agent guide: this file.
- Cursor rules checked in `.cursor/rules/`: none found.
- `.cursorrules`: none found.
- Copilot instructions checked in `.github/copilot-instructions.md`: none found.
- When repo-specific guidance is missing, follow nearby code and config files.

## Build, Lint, And Test Commands

### Root

- Install backend deps: `npm run install:backend`
- Build backend via root proxy: `npm run build`
- Start backend via root proxy: `npm start`
- There is no root lint command.
- There is no root unified test command.

### Frontend (`controlapp_frontend/`)

- Install deps: `flutter pub get`
- Run app: `flutter run`
- Run app against local backend: `flutter run --dart-define=API_BASE_URL=http://localhost:3000`
- Analyze/lint: `flutter analyze`
- Format: `dart format lib test`
- Run all tests: `flutter test`
- Run a single test file: `flutter test test/path/to/file_test.dart`
- Run a single test by name: `flutter test --plain-name "case name" test/path/to/file_test.dart`
- Build web: `flutter build web`
- Build web with explicit API URL: `flutter build web --dart-define=API_BASE_URL=https://...`

### Backend (`contorlapp_backend/`)

- Install deps: `npm install`
- Dev server: `npm run dev`
- Compile TypeScript: `npm run build`
- Start production script: `npm start`
- Run all backend tests: `npm test`
- Run a single backend test file: `npx jest tests/path/to/file.test.ts --runInBand`
- Run a single backend test by name: `npx jest --runInBand -t "case name"`
- Prisma client generation: runs automatically via `postinstall`
- Prisma smoke script: `npm run test-prisma`
- Helper cleanup script: `npm run clear-maquinaria`
- There is no dedicated backend lint script.

## Single-Test Reality

- Frontend supports narrow test execution through `flutter test` file paths and `--plain-name`.
- Frontend currently has no `test/` directory, so single-test commands are future-ready rather than immediately usable.
- Backend uses Jest with `ts-jest` from `contorlapp_backend/tests/`.
- Backend supports narrow execution through `npx jest tests/path/to/file.test.ts --runInBand` and `npx jest --runInBand -t "case name"`.
- `npm run test-prisma` remains a Prisma smoke script, not a replacement for the Jest suite.

## Minimum Validation Expectations

- Backend-only edits: run `npm --prefix contorlapp_backend run build`.
- Backend logic changes with tests available: run `npm --prefix contorlapp_backend test`.
- Frontend-only edits: run `flutter analyze` in `controlapp_frontend/`.
- Frontend behavior changes: run the narrowest relevant `flutter test` command when tests exist.
- Cross-stack API contract changes: run frontend analyze plus backend build.
- Do not invent lint/test commands that are not present in the repo.

## Frontend Style Guidelines

- Follow `dart format`; do not hand-align spacing.
- The analyzer extends `package:flutter_lints/flutter.yaml` via `controlapp_frontend/analysis_options.yaml`.
- Prefer single quotes, matching current Dart files.
- Group imports as Dart SDK, Flutter/packages, then app-local imports.
- Prefer `package:flutter_application_1/...` imports for cross-folder app code.
- Use relative imports only for very local neighbors if the file already follows that pattern.
- Use `PascalCase` for classes, enums, typedefs, and widget types.
- Use `camelCase` for methods, variables, parameters, and named arguments.
- Use leading `_` for private fields, helpers, and private widgets within a library.
- File names are snake_case; pages usually end with `_page.dart`, APIs with `_api.dart`, services with `_service.dart`.
- Prefer `final` for references and `const` wherever widgets or values are compile-time constant.
- Convert JSON to typed models or typed `Map<String, dynamic>` shapes early.
- Keep network code in `lib/api/`, `lib/service/`, or repositories, not directly in widgets.
- Reuse shared helpers such as `ApiClient`, `AppError`, `AppFeedback`, and `SessionService`.
- In async UI flows, clear stale error state before retrying and restore loading flags in `finally`.
- Use mounted-safe `setState` patterns around awaited work.
- Dispose controllers, focus nodes, animation controllers, and other owned resources.
- Avoid hardcoded localhost URLs in feature code; use existing constants or client helpers.

## Backend Style Guidelines

- Write TypeScript compatible with `strict: true` in `contorlapp_backend/tsconfig.json`.
- Note that `noImplicitAny` is disabled, but new code should still avoid unnecessary `any`.
- Prefer double quotes, matching current backend files.
- Import external packages first, then internal modules.
- Use `import type` for type-only imports when appropriate.
- Use `PascalCase` for classes and service/controller types.
- Use `camelCase` for variables, functions, methods, and local helpers.
- Preserve existing file naming patterns even when they are inconsistent (`AuthController.ts`, `authService.ts`, `GerenteServices.ts`).
- Keep route files thin: register endpoints, middleware, and controller methods only.
- Keep controllers focused on request parsing, auth extraction, Zod validation, and response shaping.
- Put business logic, Prisma access, and multi-step workflows in services.
- Reuse the shared Prisma client from `contorlapp_backend/src/db/prisma.ts`.
- Do not create ad hoc Prisma clients in controllers or services.
- Validate external input near the boundary with `zod` schemas.
- Prefer `async`/`await` over chained promises.
- Keep nullability explicit in Prisma selects/includes and returned objects.
- Use transactions for multi-step writes that must stay consistent.
- Let shared middleware or central error handling perform final HTTP serialization.
- Do not bypass existing auth, role, or request-user patterns.

## Naming And Domain Conventions

- Keep business nouns in Spanish when they already exist in schema, routes, or UI.
- Mirror API field names exactly in DTOs and JSON payloads.
- Preserve established identifiers such as `conjuntoId`, `operarioId`, `supervisorId`, `tareaId`, `nit`, `correo`, and `contrasena`.
- Avoid translating Prisma enum values or route segments unless the contract is intentionally changing.
- Match local naming near the edited file before normalizing anything broadly.

## Error Handling

- Prefer actionable, user-readable messages over raw technical failures.
- Frontend should convert thrown values with `AppError.messageOf(...)` before display when possible.
- Backend services may throw status-bearing errors when HTTP status matters.
- Do not leak stack traces, SQL details, secrets, or env var names to clients.
- Silent failure is acceptable only for explicit best-effort cleanup paths.

## Dependency And Import Rules

- Prefer existing workspace tools and libraries before adding dependencies.
- For backend validation and schema checks, prefer existing `zod` and Prisma patterns.
- For frontend utilities, prefer Flutter/Dart SDK facilities before new packages.
- Do not modify both app manifests for a single-app change.

## Agent Workflow

- Inspect neighboring files before editing so local conventions win over generic style advice.
- Keep changes minimal and targeted unless the task explicitly asks for refactoring.
- After backend edits, default to `npm --prefix contorlapp_backend run build`.
- After frontend edits, default to `flutter analyze` and the narrowest relevant `flutter test` command.
- If you add the first real backend or frontend tests, update this file with the exact commands.
- If a validation command cannot run in the current environment, say so explicitly in your handoff.

## Known Gaps

- No Cursor or Copilot instruction files exist today.
- No root-level lint or test orchestration exists.
- No backend lint script exists.
- Backend single-test workflow is Jest-based rather than npm-script-based.
- No frontend tests exist yet despite `flutter_test` being configured.
