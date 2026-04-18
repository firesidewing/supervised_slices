```markdown
# Design System Strategy: Basil & Stone

## 1. Overview & Creative North Star
**Creative North Star: "The Digital Atelier"**

This design system is built to bridge the gap between the visceral, tactile world of artisan flour and wood-fired ovens and the precision of high-end SaaS technology. We are not building a generic "app"; we are curating a digital broadsheet for the modern pizzaiolo.

To achieve an "Atelier" feel, the system moves away from rigid bootstrap-style grids. Instead, it utilizes **Editorial Asymmetry**. This means we embrace intentional white space, high-contrast typographic scales, and elements that slightly overlap to create a sense of bespoke craftsmanship. The goal is to make every screen feel like a layout from a high-end culinary journal, where information density is balanced by sophisticated breathing room.

---

## 2. Colors: Tonal Depth & The "No-Line" Rule

The palette is rooted in organic, earthy tones—Sage, Stone, and Charcoal—interrupted by the "Artisan Red" of a ripening San Marzano tomato.

### The "No-Line" Rule
**Explicit Instruction:** Designers are prohibited from using 1px solid borders for sectioning. Boundaries must be defined solely through background color shifts.
*   *Implementation:* Use a `surface-container-low` section sitting directly on a `surface` background. If you feel the need to draw a line, you haven't used your surface tokens correctly.

### Surface Hierarchy & Nesting
Treat the UI as a series of physical layers, like stacked sheets of fine deckle-edged paper. 
*   **Base:** `surface` (#fcf9f2)
*   **Sections:** `surface-container-low` (#f6f3ec) or `surface-container` (#f0eee7)
*   **Interactive Cards:** `surface-container-lowest` (#ffffff) to create a subtle "lift" against the warm stone background.

### The Glass & Gradient Rule
To prevent the UI from feeling "flat," use **Glassmorphism** for floating menus and navigation bars.
*   *Formula:* `surface` color at 80% opacity + `backdrop-blur: 20px`.
*   *Signature Textures:* For primary CTAs, use a subtle linear gradient from `primary` (#8c161a) to `primary_container` (#ad302f) at a 135-degree angle. This adds a "fired-clay" depth that flat hex codes lack.

---

## 3. Typography: The Editorial Contrast

The soul of this system lies in the juxtaposition of a high-contrast serif and a precision-engineered sans-serif.

*   **The Voice (Noto Serif):** Used for `display` and `headline` scales. It conveys authority and heritage. Large display headers should use tight letter-spacing (-2%) to feel more like a masthead.
*   **The Engine (Plus Jakarta Sans):** Used for `title`, `body`, and `labels`. This provides the "modern technology" half of the brand. It is hyper-legible, clean, and professional.

**Hierarchy as Identity:**
*   **Display-LG (3.5rem):** Use for hero moments only.
*   **Headline-SM (1.5rem):** Use for section headers, always in Noto Serif to ground the page in the "Atelier" feel.
*   **Label-MD (0.75rem):** Always uppercase with 5-10% letter spacing when used for metadata or category tags.

---

## 4. Elevation & Depth: Tonal Layering

Traditional shadows are often a sign of lazy design. In this system, we use **Tonal Layering** first.

### The Layering Principle
Depth is achieved by "stacking" surface tiers. Place a `surface-container-lowest` card on a `surface-container-low` section. This creates a soft, natural lift that mimics paper on a stone countertop.

### Ambient Shadows
If a "floating" effect is mandatory (e.g., a modal or a floating action button):
*   **Shadow Specs:** Blur: 40px, Spread: -10px, Opacity: 6%. 
*   **Color Tint:** Never use pure black. Use a tinted version of `on-surface` (#1c1c18) to mimic natural ambient light.

### The "Ghost Border" Fallback
If a border is required for accessibility (e.g., input fields), use the **Ghost Border**:
*   *Spec:* `outline-variant` token at 20% opacity. Forbid 100% opaque borders.

---

## 5. Components: Functional Elegance

### Buttons
*   **Primary:** Artisan Red gradient. `rounded-md` (0.375rem). No border. White text.
*   **Secondary:** Sage Green (`secondary`). Ghost Border style.
*   **Tertiary:** Plus Jakarta Sans, Bold, Uppercase, 0.05em tracking. No container.

### Loading States (Required for All Interactions)

Every interactive element that triggers a server round-trip **must** show a loading state immediately on interaction. No interaction that takes longer than ~100ms can give zero feedback.

**Rules:**
- Use Phoenix LiveView's `phx-click-loading:`, `phx-submit-loading:`, and `phx-change-loading:` Tailwind variants (already defined in `app.css`). No manual boolean flags needed.
- **Text buttons:** wrap the label in `<span class="phx-*-loading:!hidden">` and add a sibling `<span class="hidden phx-*-loading:!flex ...">` containing a spinner and brief action text ("Saving...", "Sending...").
- **Icon-only buttons (material-symbols):** add `phx-click-loading:opacity-50 phx-click-loading:cursor-wait` to the button and `phx-click-loading:animate-spin` to the icon `<span>`.
- **Selects (`phx-change`):** add `phx-change-loading:opacity-50 phx-change-loading:cursor-wait` to the `<select>`.
- **Spinner:** always use `<.icon name="hero-arrow-path" class="size-N animate-spin" />`. Size guide: `size-3` for `text-[9px]`/`text-xs`, `size-4` for standard buttons, `size-5` for large full-width buttons.
- **Opacity:** `opacity-70` for primary actions, `opacity-80` for full-width primary actions, `opacity-50` for secondary/utility elements.
- Always pair opacity with `cursor-wait`.

### Input Fields
*   **Style:** Minimalist. No background color (transparent). Only a bottom stroke using the "Ghost Border" (20% `outline-variant`).
*   **States:** On focus, the bottom stroke transitions to `primary` (#8c161a) with a 2px weight.

### Cards & Lists
*   **The Card Rule:** No dividers. Separate content using `title-sm` headers and increased vertical white space (use the 24px or 32px spacing steps).
*   **List Items:** Use `surface-container-low` for hover states. Never use horizontal lines to separate list items; use tonal shifts.

### Signature Component: The "Artisan Stamp" Badge
*   A circular or high-radius `chip` using `secondary_container` (#c5e7df) with `on_secondary_container` (#496962) text. Used for status indicators (e.g., "Fermenting," "Fired," "Delivered").

---

## 6. Do’s and Don'ts

### Do:
*   **Do** allow Noto Serif headlines to "bleed" or overlap slightly into different background sections to break the grid.
*   **Do** use high-density layouts. Professional chefs and business owners prefer seeing more data at once—just ensure it is organized through clear typographic weight, not boxes.
*   **Do** use `background` (#fcf9f2) as your primary canvas; it feels warmer and more premium than pure #ffffff.

### Don’t:
*   **Don't** use 100% opaque black for text. Always use `on-surface` (#1c1c18).
*   **Don't** use "Drop Shadows" on buttons. Use tonal contrast.
*   **Don't** use standard icons. Use thin-stroke (1.5px or 1px) custom iconography to match the "Plus Jakarta Sans" weight.
*   **Don't** use rounded-full (pills) for primary buttons; stick to `rounded-md` to maintain the "Atelier" architectural structure.