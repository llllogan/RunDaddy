# Repository Guidelines

## Project Structure & Module Organization
This repo hosts three coordinated apps: `Api` (TypeScript/Express service under `src` with Prisma schemas in `DB/prisma` and seed SQL in `DB/sql`), `Site` (Angular client with feature modules in `src/app` and shared styles in `src/styles.scss`), and `App` (SwiftUI iOS client inside `App/PickerAgent`). Temporary artifacts land in each package’s `dist` or `DerivedData` folders—keep them out of commits. Add new assets to `App/PickerAgent/Assets.xcassets` and static web content to `Site/public`.

## Build, Test, and Development Commands
- API: `cd Api && npm run dev` for hot reload with `.env`, `npm run build && npm start` for production, `npm run prisma:generate` after schema edits, `npm run db:sync` to replay migrations plus seed SQL.
- Site: `cd Site && npm start` serves Angular locally, `npm run build` outputs to `dist/`, `npm test` runs Karma/Jasmine, `npm run watch` rebuilds on change.
- iOS: Open `App/PickerAgent.xcodeproj` and run the `PickAgent` scheme; `xcodebuild -workspace PickerAgent.xcodeproj -scheme PickAgent` works in CI.

## Coding Style & Naming Conventions
TypeScript follows ESLint defaults with 2-space indents and explicit `camelCase` for variables, `PascalCase` for classes and Prisma models. Angular templates respect the repo Prettier config (`singleQuote`, `printWidth: 100`). SwiftUI views use 4-space indents, `struct` names end with `View`, and async services live under `Services/*Service.swift`. Keep env keys SCREAMING_SNAKE_CASE in `.env`, and name new files after their primary export (`runs.service.ts`, `runs-service.ts`).

## Website Visual Guidlines
- Overall feel is bright and calm: light gray gradient background (`#f8fafc → #e5e7eb`), charcoal text, and large white “soft cards” with rounded corners and gentle shadows for primary containers.
- CTA buttons stay pill-shaped, uppercase, and use either solid gray/black fills or white backgrounds with gray borders; keep supporting buttons outlined for hierarchy.
- All page titles, section headings, and form labels must be left-aligned (no centered hero or form headers) to match the current typography rhythm.
- Use Tailwind’s built-in tracking utilities (`tracking-wide`, etc.); never apply ad-hoc utilities like `class="tracking-[0.3em]"`.

## Testing Guidelines
Target fast unit coverage in both TypeScript apps: colocate API tests beside implementation (`src/**/__tests__/*.spec.ts`) and run via `npm run typecheck && npm test` before opening a PR. Angular specs belong under `src/app/.../*.spec.ts`. For iOS, add XCTest cases to the `PickerAgentTests` target and run with `Cmd+U`. Block merges if regressions appear; prefer deterministic fixtures over network calls.

## Commit & Pull Request Guidelines
Git history favors short, imperative subjects (e.g., “Update site auth flow”). Keep one logical change per commit and mention affected modules in the body if cross-cutting. PRs should include: purpose summary, testing evidence (commands or screenshots for UI changes), linked issues, and any schema or env updates. Request at least one reviewer familiar with the touched surface and ensure CI (Angular tests, API typecheck, Xcode build) is green.

## Security & Configuration Tips
Never commit `.env` files or Prisma credentials; sample keys belong in `.env.example`. Rotate JWT secrets and database passwords per environment. When sharing debug data, strip PII from Excel uploads under `Api/requests`. Use `npm audit` and `xcodebuild -showBuildSettings` in CI to surface dependency or signing issues early.
