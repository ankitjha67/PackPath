```markdown
# Design System Strategy: The Kinetic Path

## 1. Overview & Creative North Star
**Creative North Star: "Precision Utility"**

This design system rejects the "cluttered travel app" trope in favor of a high-end, editorial approach to adventure. We are building for the field—where sun glare, movement, and rapid decision-making are constant. The aesthetic moves away from standard "flat" UI toward **Precision Utility**: a style characterized by hyper-legible typography, intentional asymmetry, and a sophisticated layering of surfaces that mimics the physical depth of a topographic map. 

We break the "template" look by utilizing wide-open breathing room contrasted against dense, high-utility data clusters. This system doesn't just display information; it directs the eye with the authority of a professional guide.

---

## 2. Colors: High-Vis Sophistication
Our palette balances the ruggedness of outdoor gear with the refinement of modern software.

- **Primary (`#ab3600`):** Our "Safety Orange." Reserved strictly for path-finding actions and critical waypoints. 
- **Secondary (`#2559bd`):** "Pathfinder Blue." Used for navigation, map-specific UI, and group coordination status.
- **Surface Hierarchy:** We utilize `surface-container` tiers to build depth without clutter.
    - **The "No-Line" Rule:** 1px solid borders are strictly prohibited for sectioning. Boundaries are created through background shifts. For example, a `surface-container-low` activity feed sitting on a `surface` background provides all the definition needed.
    - **The "Glass & Gradient" Rule:** Floating map overlays must use `surface-container-lowest` with a 12px `backdrop-blur` and 85% opacity. This "Glassmorphism" ensures the map remains visible beneath the UI, maintaining spatial awareness.
    - **Signature Textures:** Main CTAs should utilize a subtle linear gradient from `primary` (#ab3600) to `primary_container` (#ff5f1f) at a 135-degree angle to give a tactile, "lit-from-within" quality.

---

## 3. Typography: The Editorial Engine
We pair the technical precision of **Space Grotesk** for high-impact displays with the unmatched legibility of **Inter** for utility.

- **Display & Headline (Space Grotesk):** Large, aggressive, and confident. Used for destination names and primary headers. The wide apertures of Space Grotesk ensure character recognition even in high-glare environments.
- **Title, Body, & Label (Inter):** The workhorse. We lean heavily on `title-md` for legibility. 
- **Hierarchy as Brand:** Use `display-lg` sparingly to create an "Editorial" feel on landing screens, contrasted against `label-sm` in all-caps for technical data (GPS coordinates, timestamps).

---

## 4. Elevation & Depth: Tonal Layering
Traditional drop shadows are too "digital" for an outdoor-ready system. We use **Tonal Layering**.

- **The Layering Principle:** Stack `surface-container-lowest` cards on `surface-container-low` sections. This creates a soft, natural lift reminiscent of stacked paper maps.
- **Ambient Shadows:** When an element must float (like a Quick-Action Button), use a highly diffused shadow: `y-8, blur-24`. The shadow color must be a tinted version of `on-surface` at 6% opacity, rather than pure grey.
- **The "Ghost Border" Fallback:** If a map element requires more definition, use the `outline-variant` token at 15% opacity. Never use 100% opaque borders.

---

## 5. Components: Rugged Precision

### Buttons & Quick-Actions
- **Primary Action:** Gradient-filled (`primary` to `primary_container`), `xl` roundedness (0.75rem). No border.
- **Quick-Action Floating Buttons:** `full` roundedness, `surface-container-lowest` with glassmorphism and a `secondary` icon. These are positioned asymmetrically to avoid blocking map centers.

### Status Badges & Chips
- **Status Badges:** High-contrast containers using `tertiary` or `error` tokens. Text must be `label-md` bold for instant recognition.
- **Filter Chips:** No borders. Use `surface-container-high` for unselected and `secondary` with `on-secondary` text for selected.

### Map Overlays & Lists
- **Map Overlays:** Grounded to the bottom or sides with a `xl` corner radius on the "inner" corner only. Use `backdrop-blur` to keep the environment visible.
- **Cards & Lists:** **Strictly forbid divider lines.** Use vertical whitespace (16px or 24px) or a subtle shift to `surface-container-lowest` to separate items. This keeps the UI feeling open and modern.

### Contextual Features (New)
- **The "Waypoint" Carousel:** A horizontally scrolling set of `surface-container-low` cards with high-contrast `display-sm` numbers to denote trip sequence.
- **Comms-HUD:** A glassmorphic top-bar for "Active Group Status," using `secondary` pulses to indicate live location sharing.

---

## 6. Do’s and Don’ts

### Do:
- **Do** use `primary` orange for "Danger" or "High-Urgency" travel updates; it is our most visible token.
- **Do** lean into asymmetry. Off-center headers or staggered card layouts feel more "adventure" and less "corporate."
- **Do** ensure all touch targets for outdoor use are a minimum of 48x48dp.

### Don't:
- **Don't** use black shadows. Always tint shadows with the surface color to maintain a premium, atmospheric feel.
- **Don't** use dividers. If the content feels messy, increase the `surface-container` contrast or the whitespace; do not add a line.
- **Don't** use `primary` for non-critical actions. It is a "Safety" color; overusing it diminishes its utility in the field.

---

## 7. Token Reference Summary

| Role | Token Value | Usage |
| :--- | :--- | :--- |
| **Action** | `primary` (#ab3600) | Primary CTAs, Waypoints |
| **Navigation** | `secondary` (#2559bd) | Map UI, Selected states |
| **Base** | `surface` (#f9f9fc) | App background |
| **Card Lift** | `surface-container-lowest` | Foreground cards / Overlays |
| **Typography** | `on-surface` (#1a1c1e) | Maximum legibility text |
| **Radius** | `xl` (0.75rem) | Standard container rounding |

*This system is designed to be felt as much as it is seen—providing a sense of security and professional-grade coordination for every journey.*```