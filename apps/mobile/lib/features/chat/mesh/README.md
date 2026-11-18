# Bluetooth offline mesh chat

Unified auto-failover chat: messages send over the trip WebSocket when online,
and over a Bluetooth / Nearby-Connections mesh to nearby trip members when
there's no internet. Mesh-sent messages are reconciled to the server on
reconnect so history stays consistent.

## Pieces

| File | Role |
|------|------|
| `mesh_message.dart` | Wire envelope with a client id, trip id, sender, body, and a relay TTL. |
| `mesh_transport.dart` | `MeshTransport` interface + `NoopMeshTransport` (web / unsupported). |
| `nearby_mesh_transport.dart` | Concrete transport over `flutter_nearby_connections` (Android Nearby + iOS Multipeer). **All plugin-specific code lives here.** |
| `mesh_chat_coordinator.dart` | Ties transport ↔ chat: surfaces inbound peer messages, and on offline-send broadcasts to peers + persists to a durable reconcile outbox. |

Integration lives in `features/map/live_trip_controller.dart`:
`sendChat()` uses the WS when connected, else the mesh; inbound mesh messages
flow into the same `chatStream`; on reconnect the outbox is flushed to the
server (idempotent via client id). `ChatScreen` de-dupes by client id and shows
an offline/nearby-peers banner.

## Trip segregation

iOS Multipeer requires a **static** service type declared in `Info.plist`
(`NSBonjourServices` = `_packpath._tcp`/`_udp`), so we use one fixed service
type and scope trips by a tag in the advertised device name
(`<trip-tag>~<user-id>`) plus a message-level trip-id filter. Only same-tag
peers are invited to the cluster.

## Permissions

- **Android** (`AndroidManifest.xml`): `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`,
  `BLUETOOTH_SCAN`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`,
  `NEARBY_WIFI_DEVICES` (+ legacy `BLUETOOTH`/`BLUETOOTH_ADMIN` ≤ API 30).
- **iOS** (`Info.plist`): `NSBluetoothAlwaysUsageDescription`,
  `NSLocalNetworkUsageDescription`, `NSBonjourServices`.

Runtime permission prompts are handled by the OS on first advertise/scan.

## Testing (requires real hardware)

This cannot be exercised in CI or a simulator. To verify:

1. `flutter pub get` (pulls `flutter_nearby_connections`).
2. Install on **two physical phones**, log in as two members of the same trip.
3. Open the trip chat on both, then put both in airplane mode (leave Bluetooth
   on) to force the WS offline.
4. Send from one — it should appear on the other within a few seconds and the
   banner should read "messaging N nearby … over Bluetooth".
5. Restore connectivity — the message should reconcile to the server and load
   from history on a fresh open, with no duplicate.
