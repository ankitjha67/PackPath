# PackPath — Product Requirements Document (v1)

**Owner:** Ankit Jha
**Status:** Draft
**Last updated:** 2026-04-12

---

## 1. Problem

Groups traveling together — road trips, treks, airport runs, weddings, pilgrimages — have no single app that handles *all* of:

1. **Where is everyone right now?** (live location, like Life360)
2. **Where are we going and how far am I?** (shared route + per-member ETA, like Google Maps but for a group)
3. **Talk to the group fast.** (chat + push-to-talk voice — no screen required while driving)
4. **Plan the trip together.** (waypoints, stops, pickup points)
5. **Work offline.** (hills, highways, dead zones)

People currently stitch together Google Maps + WhatsApp + phone calls + Life360. Each has gaps:

| App           | Live map | Shared route | Group chat | Voice PTT | Offline | Trip plan |
| ------------- | -------- | ------------ | ---------- | --------- | ------- | --------- |
| Life360       | ✅       | ❌          | Basic      | ❌        | ❌     | ❌        |
| Google Maps   | Partial  | ❌          | ❌         | ❌        | Partial| ❌        |
| WhatsApp      | 1-person | ❌          | ✅         | ❌        | ❌     | ❌        |
| Zello         | ❌       | ❌          | ❌         | ✅        | ❌     | ❌        |
| WolfPack      | ✅       | ❌          | Basic      | ❌        | ❌     | ❌        |
| **PackPath**  | ✅       | ✅          | ✅         | ✅        | ✅     | ✅        |

## 2. Target users

- **Primary:** Indian families and friend groups going on road trips, weekend getaways, wedding convoys, Himalayan treks.
- **Secondary:** Global users doing similar trips (US national parks, European road trips).
- **Tertiary later:** Delivery fleets, school bus groups, event staff.

## 3. Goals

- **Solo-shipped** by one engineer over ~6 weekends.
- **Real product** on Google Play and App Store.
- **Portfolio-grade** code and docs.
- **Hackathon entry** for VibeCon.

## 4. Non-goals (v1)

- Web dashboard (mobile-first).
- Public/social features. Trips are private-invite only.
- Ads or selling location data. Ever.
- Full-blown navigation turn-by-turn voice prompts (Mapbox Navigation SDK is v2).

## 5. v1 features (all must-have)

### 5.1 Trips
- Create a trip (name, destination, time window, max members).
- Join a trip via 6-digit code or QR.
- Roles: **owner**, **member**.
- Trip ends → location sharing auto-expires for all members.

### 5.2 Live group map
- Every member sees every other member as a colored avatar on a shared map.
- Each avatar shows: name, heading arrow, battery %, last-updated timestamp.
- Location updates broadcast every 5s when moving, every 30s when stationary, paused <15% battery.

### 5.3 Shared route + ETA
- Long-press on map → add waypoint.
- Ordered list of waypoints; owner can reorder.
- Mapbox Directions API draws the polyline.
- For each member, compute ETA to the *next* waypoint; show in a collapsible member panel.

### 5.4 In-app chat
- Group chat scoped to the trip.
- Messages persist in Postgres.
- Typing indicators.
- FCM push when app is backgrounded.
- Geofenced auto-message: *"Rahul has arrived at Dhaba Junction"* when a member enters a 150m radius of a waypoint.

### 5.5 Push-to-talk voice
- One LiveKit room per trip.
- Hold-to-talk button; releases when you lift finger.
- Mute all / mute self controls.
- Visual indicator of who's currently talking.

### 5.6 Offline maps
- At trip creation, pre-download Mapbox vector tiles for a corridor around the planned route (default 10 km radius around the polyline).
- Offline tiles available for the trip's duration + 24 h.
- Works without data; locations queue and sync when connectivity returns.

## 6. Privacy as a feature

- Location sharing **auto-expires** when the trip ends.
- **Ghost mode**: temporary per-user opt-out; user stays in the trip and can see others but they can't see them.
- **Never sell data.** Location data deleted 7 days after a trip ends.
- Clear in-app privacy dashboard: "Here's exactly what we store."

## 7. Licensing & distribution

- **Free and open source** (MIT). All features are available to everyone; there
  are no paid tiers, limits, or paywalls.
- **Self-hostable**: one APK points at any backend you run.

## 8. Success metrics (first 90 days post-launch)

- 2,000 installs
- 500 trips created
- 20% D30 retention on trip creators
- < 2% crash-free sessions
- Battery drain < 4% / hour during active trip (below Life360)

## 9. Constraints

- **Battery** is the category killer. Adaptive intervals, FusedLocationProvider, iOS significant-change API.
- **Mobile data**: compress location updates; websocket heartbeat tuning.
- **Indoor accuracy**: fall back to last-known + confidence cone.
- **Solo dev**: every feature needs to be shippable by one person in a weekend.

## 10. Risks

| Risk                                                        | Mitigation                                              |
| ----------------------------------------------------------- | ------------------------------------------------------- |
| Battery-drain reviews kill app rating                       | Adaptive sampling, documented power profile, settings   |
| Mapbox MAU cost spikes                                      | Offline tiles, aggressive caching, OSRM fallback at 10k |
| LiveKit self-hosting complexity                             | Use LiveKit Cloud free tier for v1                      |
| Phone-OTP fraud / spam                                      | MSG91 rate-limits + per-IP throttle                     |
| iOS background location approval                            | Clear usage description, trip-scoped only               |

## 11. Open questions

- Apple Watch companion for PTT — v1 or v2?
- Should waypoints support arrival windows ("by 3 pm")?

---

See `ARCHITECTURE.md` for technical design.
