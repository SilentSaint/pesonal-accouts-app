# 2. Flutter for Cross-Platform Mobile and Web Development

Date: 2026-07-26

## Status

Accepted

## Context

The automatic expense tracker requires a responsive user interface that runs on Android mobile devices (with background SMS listening capabilities) and Web Browsers (for desktop/tablet access). We aimed to minimize code duplication across platforms for domain logic, state management, and UI components.

Options evaluated:
1. Flutter (Dart) - single codebase for Mobile and Web with native platform channel support for Android SMS.
2. React Native + React Native Web (TypeScript).
3. Separate Native Android (Kotlin) app + Web (React/Next.js) app.

## Decision

We chose **Flutter (Dart)** as the core frontend framework for both Mobile and Web applications.

## Consequences

### Positive
* **Maximum Code Sharing**: 100% shared domain models, deduplication logic, state management, and UI widgets between mobile and web.
* **Native Android SMS Access**: Direct integration via Flutter MethodChannels and Android `BroadcastReceiver` for real-time `SMS_RECEIVED` events.
* **Consistent Design & Aesthetics**: Fluid 60/120fps UI animations, responsive layouts, glassmorphism, and dark mode themes supported across web and mobile.

### Negative / Trade-offs
* Web initial bundle size is larger than standard lightweight HTML/JS web apps, though negligible for desktop browser usage in a personal app context.
