# PackPath Mobile

Flutter 3.x app for PackPath. Single codebase for iOS + Android.

## Run

```bash
flutter pub get
cp lib/config/env.example.dart lib/config/env.dart
# Put your Mapbox public token in env.dart
flutter run
```

## Layout

```
lib/
├── main.dart
├── app.dart                  # MaterialApp.router + theme
├── config/
│   ├── env.example.dart      # template — copy to env.dart
│   └── theme.dart
├── core/
│   ├── api_client.dart       # Dio instance with auth interceptor
│   ├── token_storage.dart    # JWT persistence
│   └── ws_client.dart        # /ws/trips/{id} channel
├── features/
│   ├── auth/                 # phone OTP screens, providers
│   ├── trips/                # trip list, create, join, detail
│   ├── map/                  # live group map (Weekend 3)
│   ├── chat/                 # in-app chat (Weekend 5)
│   └── voice/                # PTT (Weekend 6)
├── routing/
│   └── router.dart           # go_router config
└── shared/
    ├── widgets/
    └── models/
```

## State management

[Riverpod 2](https://riverpod.dev). Providers live next to the feature they
power. Run `dart run build_runner build` after editing annotated providers.
