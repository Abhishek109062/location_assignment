# Location Tracker — Flutter Technical Assessment

Offline-first Flutter app that tracks GPS (real or simulated), queues points locally when offline, and syncs them to a **mock REST API** when connectivity returns — without duplicate uploads.

It also demonstrates assignment-level **background tracking** on Android/iOS (minimized, locked, and resume-after-kill).

## Requirements coverage

| # | Requirement | Implementation |
|---|-------------|----------------|
| 1 | Start/stop tracking with real or simulated GPS | Start/Stop controls + simulated GPS toggle (`LocationService` / background service) |
| 2 | Store locations locally when offline | SQLite queue (`pending` / `failed`) |
| 3 | Auto-sync to mock REST API; prevent duplicates | `SyncService` + `MockLocationApiClient` (client UUID idempotency) |
| 4 | Maintainable architecture + state management | Layered `data` / `services` / `presentation` + **Riverpod** |
| 5 | Automated test for offline / sync / retry | `test/sync_service_test.dart` (+ model & widget smoke tests) |
| 6 | Background GPS approach (min / locked / interrupted) | Implemented demo + notes in this README |

## Quick start

```bash
flutter pub get
flutter run          # prefer Android/iOS device or emulator for background demo
flutter test
```

### Permissions (Android)

On first **Start tracking**, allow:

- **Location** (While using the app) — required even for simulated GPS because the background service uses `foregroundServiceType="location"`
- **Notifications** — required for the ongoing tracking notification

### Demo flow for reviewers

1. Keep **Use simulated GPS** on (default).
2. Turn on **Force offline**.
3. Tap **Start tracking** — new points are queued locally.
4. Open **Locations** — pending and synced items appear in one list with status chips (paginated via **Show more**).
5. Turn **Force offline** off (or tap the cloud upload icon) — queue syncs; statuses flip to Synced in place.
6. Minimize / lock the phone — tracking continues via the background service (Android notification stays visible).
7. Force-kill and reopen — session can auto-resume; pending points sync when online.

> Desktop (macOS) runs foreground tracking only. Use Android/iOS for background / killed-state demos.

## Architecture

Layered structure with **Riverpod** for state:

```
lib/
  main.dart
  app/app.dart
  data/
    models/location_record.dart
    datasources/
      local/location_database.dart      # SQLite offline queue
      remote/location_api_client.dart   # MockLocationApiClient
    repositories/location_repository.dart
  services/
    location_service.dart               # Real / simulated GPS (UI)
    connectivity_service.dart           # Network + Force offline
    sync_service.dart                   # Drain queue, idempotent uploads
    background_tracking_service.dart    # Android/iOS background isolate
    tracking_session_store.dart         # SharedPreferences session flags
  presentation/
    providers/tracking_providers.dart
    screens/home_screen.dart
    widgets/                            # Status banner, tiles, actions
```

### Data flow

```
GPS fix (UI or background)
  → LocationRecord (client UUID)
  → SQLite insert (status = pending)
  → if online: upload via MockLocationApiClient
  → success / server duplicate → status = synced
  → failure → status = failed, retry_count++
```

### Who collects GPS when

| App state | Collector |
|-----------|-----------|
| App open / resumed | UI `LocationService` (live list updates) |
| Minimized / locked | Background service takes over |
| Killed → reopen | Session flag in prefs; service can resume, then UI takes over again |

Handoff uses `ui_collecting` in SharedPreferences so UI and background do not both write at once.

### Preventing duplicate uploads

| Layer | Mechanism |
|-------|-----------|
| Client | Stable UUID created before insert |
| Local DB | Only `pending` / `failed` rows are synced |
| Sync mutex | One UI sync pass at a time |
| Mock API | Remembers accepted IDs; retries return `duplicate` success |
| After success | Row marked `synced` and never re-queued |

This matches the common REST **Idempotency-Key** pattern.

### UI behavior

- One **Locations** list (newest first) with Pending / Syncing / Synced / Failed chips.
- Loads 10 at a time; **Show more** pages from SQLite.
- Status banner height is fixed so Start/Stop does not jump the layout.
- Start/Stop buttons stack on narrow screens.

### State management

`TrackingController` (Riverpod `Notifier`) owns tracking, connectivity, status text, and the displayed record list. Services are app-lifetime providers so they stay easy to mock in tests.

## Automated tests

```bash
flutter test
```

| File | What it covers |
|------|----------------|
| `test/sync_service_test.dart` | Offline queue, sync-on-online, no re-upload, retry after failure, server-side duplicate → local synced |
| `test/location_record_test.dart` | Serialization / API payload id |
| `test/widget_smoke_test.dart` | Home screen controls render |

## Background GPS (Android & iOS)

### What this app implements

| State | Behavior |
|-------|----------|
| Minimized / screen locked | Android location foreground service + notification; iOS background location mode |
| Process killed / swiped away | SQLite + `tracking_active` prefs survive; reopen can auto-resume and sync |
| User force-stop (Android settings) | OS blocks restarts until the user opens the app; then recovery applies |
| Offline | Same local queue; sync when connectivity returns |



## Stack

| Area | Choice |
|------|--------|
| Flutter / Dart | 3.x |
| State management | flutter_riverpod |
| Local DB | sqflite |
| Connectivity | connectivity_plus |
| Location | geolocator (+ built-in simulator) |
| Background | flutter_background_service |
| Session flags | shared_preferences |
| Notifications (Android FGS) | flutter_local_notifications |
