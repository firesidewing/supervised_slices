# Design System Strategy: The Artisan Editorial

## 1. Overview & Creative North Star
**Creative North Star: "The Modern Trattoria Canvas"**
This design system rejects the "fast-food" template in favor of a high-end editorial experience. We are not building a generic ordering app; we are creating a digital storefront that feels like a floured marble countertop. By utilizing intentional asymmetry, overlapping high-quality food photography, and a sophisticated "No-Line" philosophy, we move the user through an energetic, tactile journey. The experience should feel as fresh as a basil leaf and as warm as a wood-fired oven.

### Breaking the Grid
To avoid a "boxed-in" look, use **surface-container-lowest** elements that bleed off the edge of the screen or overlap across different background tiers. Large-scale typography should occasionally "tuck" behind isolated food PNGs to create 3D depth.

---

## 2. Colors & Surface Philosophy
The palette is a celebration of ingredients: Warm Whites (Flour/Dough), Tomato Red (Acid/Energy), and Basil Green (Freshness).

### The "No-Line" Rule
**Explicit Instruction:** 1px solid borders are strictly prohibited for sectioning. Structural boundaries must be defined solely through background color shifts. 
- A hero section using `surface` (`#faf9f6`) should transition into a featured menu section using `surface-container-low` (`#f4f3f1`). 
- This creates a seamless, premium feel that mimics natural light falling on different surfaces.

### Surface Hierarchy & Nesting
Treat the UI as a physical stack of parchment and marble:
1.  **Base Layer:** `surface` (`#faf9f6`) or `background` (`#faf9f6`).
2.  **Sectioning:** `surface-container-low` (`#f4f3f1`) for large content blocks.
3.  **Interactive Elements:** Use `surface-container-lowest` (`#ffffff`) for cards to make them "pop" against the warmer background.

### The "Glass & Gradient" Rule
To add "soul" to the interface:
- **Signature Gradients:** For primary CTAs and hero backgrounds, use a subtle linear gradient from `primary` (`#b90027`) to `primary_container` (`#e31837`). This mimics the natural color variation of a ripening tomato.
- **Glassmorphism:** Use semi-transparent `surface_container_lowest` with a `backdrop-blur` of 12px-20px for floating navigation bars or "Add to Cart" modals.

---

## 3. Typography
We pair the geometric precision of **Plus Jakarta Sans** for headlines with the approachable, high-readability of **Be Vietnam Pro** for body copy.

*   **Display (Plus Jakarta Sans):** These are your "shouting ingredients." Use `display-lg` (3.5rem) for hero statements with tight letter spacing (-0.02em).
*   **Headlines (Plus Jakarta Sans):** Energetic and playful. Use `headline-md` (1.75rem) for menu categories.
*   **Body (Be Vietnam Pro):** Clean and functional. `body-lg` (1rem) is your workhorse for descriptions. Ensure a line height of at least 1.6 for that airy, editorial feel.
*   **Labels (Be Vietnam Pro):** Use `label-md` (0.75rem) for metadata like "Spicy" or "Vegetarian," always in uppercase with +0.05em tracking for a "stamped" aesthetic.

---

## 4. Elevation & Depth
Depth in this system is achieved through **Tonal Layering**, not structural lines.

### The Layering Principle
Avoid traditional shadows where possible. Instead, place a `surface_container_lowest` card on top of a `surface_container` background. The slight shift in hex value creates a "Soft Lift" that feels modern and clean.

### Ambient Shadows
When an element must float (e.g., a "Floating Action Button" for the cart):
- **Shadow Value:** 0px 12px 32px rgba(93, 63, 62, 0.08). 
- **The Tint Rule:** Never use pure black for shadows. Use a diluted version of `on_surface_variant` (`#5d3f3e`) to mimic the warm, ambient light of a kitchen.

### The "Ghost Border" Fallback
If accessibility requires a container edge (e.g., input fields), use the **Ghost Border**: `outline_variant` (`#e6bdbb`) at **20% opacity**. It should be felt, not seen.

---

## 5. Components

### Buttons & Interaction
- **Primary Button:** Uses the Tomato Gradient (`primary` to `primary_container`). Shape: `lg` (2rem) rounded corners. 
- **Secondary Button:** `surface_container_highest` background with `on_surface` text. No border.
- **Micro-interactions:** On hover, buttons should scale slightly (1.02) and deepen their ambient shadow.

### Cards & Lists
- **Forbid Dividers:** Do not use lines to separate menu items. Use `3.5rem` (Spacing 10) of vertical whitespace or a subtle background toggle between `surface` and `surface_container_low`.
- **Imagery:** Cards must feature high-quality, "hero" photography. Top-down "flat lay" angles work best for the editorial look. Use `xl` (3rem) corner radius for image containers.

### Inputs & Selection
- **Inputs:** Use `surface_container_low` with a `md` (1.5rem) corner radius. The label should sit in `label-md` (Be Vietnam Pro) above the field, never inside as placeholder text.
- **Chips:** For toppings or dietary filters, use `full` (9999px) rounding. Unselected: `surface_container`. Selected: `secondary` (Basil Green) with `on_secondary` (White).

### Custom Component: The "Ingredient Float"
A decorative component where isolated PNGs of ingredients (a basil leaf, a peppercorn) are positioned using absolute coordinates to overlap containers, breaking the "box" and adding organic texture.

---

## 6. Do’s and Don’ts

### Do:
- **Do** use large, bold imagery that breaks the container edges.
- **Do** use `xl` (3rem) corner radius for main feature cards.
- **Do** lean into the warm white (`#faf9f6`) to create a "breathable" layout.
- **Do** use Basil Green (`#3a6843`) sparingly as a "freshness" accent (e.g., "Available Now" or "Organic" badges).

### Don’t:
- **Don’t** use dark mode. This system is designed for the "Golden Hour" of dinner service.
- **Don’t** use 1px dividers. If you feel the need for a line, add more whitespace instead.
- **Don’t** use sharp corners. Everything should feel hand-tossed and organic.
- **Don’t** use high-contrast shadows. If the shadow looks like a "drop shadow," it's too dark.