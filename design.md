# Design System Specification: The Architectural Curator

 

## 1. Overview & Creative North Star

The "Architectural Curator" transcends the traditional e-commerce grid, evolving from a standard retail interface into a high-end editorial "Explore" experience. While inspired by the functional density of global marketplaces, this design system rejects the "cluttered warehouse" aesthetic in favor of **Intentional Density.**

 

**Creative North Star: The Digital Concierge**

The system treats information as a curated exhibition. By utilizing a sophisticated navy-to-ochre palette and deep tonal layering, we move away from flat boxes to an interface that feels like a physical architectural space. We break the template look through **Asymmetric Rhythm**: using varied card heights and staggered content modules to guide the eye, ensuring the "Explore" feed feels discovered rather than programmed.

 

---

 

## 2. Colors & Surface Philosophy

The palette balances the authority of `primary` (#291400 / Navy-Deep Brown) with the kinetic energy of `on_primary_container` (#d88100 / Signature Orange).

 

### The "No-Line" Rule

**Borders are prohibited for sectioning.** To create a premium feel, boundaries must be defined solely through background shifts. A section should transition from `surface` (#f7fafa) to `surface_container_low` (#f1f4f4) to denote a change in context. 1px solid lines are considered "visual noise" and must be avoided.

 

### Surface Hierarchy & Nesting

Treat the UI as a series of stacked architectural materials:

*   **Base Layer:** `surface` (#f7fafa) for the global background.

*   **The Sidebar:** `surface_container_low` (#f1f4f4) to provide a soft, recessed anchor for navigation.

*   **Content Cards:** `surface_container_lowest` (#ffffff) to provide maximum "pop" and perceived elevation against the gray base.

*   **Header:** `primary` (#291400) provides a heavy, authoritative anchor at the top of the visual hierarchy.

 

### The "Glass & Gradient" Rule

To prevent the orange CTAs from feeling "cheap," use subtle radial gradients. A CTA should transition from `on_primary_container` (#d88100) at the bottom-right to a slightly lighter tint at the top-left. For floating navigation elements or category overlays, use **Glassmorphism**: `surface_container_lowest` at 80% opacity with a `24px` backdrop blur.

 

---

 

## 3. Typography

The system utilizes a dual-font strategy to balance editorial flair with high-density utility.

 

*   **The Voice (Plus Jakarta Sans):** Used for `display` and `headline` roles. This typeface provides a modern, geometric clarity that feels premium and intentional. Large `display-lg` (3.5rem) headers should be used sparingly to break the feed’s density.

*   **The Engine (Inter):** Used for `title`, `body`, and `label` roles. Inter’s high x-height and legibility make it perfect for the high-density product information required in an Explore feed.

 

**Editorial Hierarchy:**

*   **Category Briefings:** Use `headline-sm` (Plus Jakarta Sans, 1.5rem) to introduce new sections.

*   **Product Names:** Use `title-md` (Inter, 1.125rem) with a tighter tracking (-0.01em) to maintain a crisp, sophisticated look.

*   **Metadata (Price/Deals):** Use `label-md` (Inter, 0.75rem) in `secondary` (#535f70) to keep the layout clean.

 

---

 

## 4. Elevation & Depth

Depth in this system is a result of **Tonal Layering** rather than structural artifice.

 

*   **The Layering Principle:** Place a `surface_container_lowest` (#ffffff) card on a `surface_container_low` (#f1f4f4) background. This creates a "Natural Lift" that mimics fine stationery layered on a desk.

*   **Ambient Shadows:** For "Featured" or "Deal" cards that require a floating effect, use an ultra-diffused shadow: `0px 12px 32px rgba(24, 28, 29, 0.06)`. The shadow color is a tinted version of `on_surface` to ensure it feels like natural light, not digital ink.

*   **The "Ghost Border" Fallback:** If high-key imagery bleeds into the background, use the `outline_variant` (#c5c6cc) at **15% opacity**. This "Ghost Border" provides just enough containment without breaking the No-Line Rule.

 

---

 

## 5. Components

 

### Navigation Sidebar (The Briefing Rail)

*   **Background:** `surface_container_low`.

*   **Active State:** Use a "pill" shape (`roundedness.full`) in `primary_fixed` (#ffdcbd) with `on_primary_fixed` (#2c1600) text. No vertical lines; the background pill is the only indicator of selection.

 

### Explore Cards (Product & Content)

*   **Container:** `surface_container_lowest` with `roundedness.lg` (0.5rem).

*   **Spacing:** Use a strict 16px (1rem) internal padding.

*   **Dividers:** **Strictly Forbidden.** Use 8px or 12px of vertical white space to separate the product title from the description.

 

### Signature CTA (The Action Button)

*   **Primary:** Background `on_primary_container` (#d88100), Text `on_primary` (#ffffff), `roundedness.md` (0.375rem).

*   **Interaction:** On hover, shift background to `on_primary_fixed_variant` (#693c00).

 

### Categories & Filter Chips

*   **Action Chips:** `surface_container_high` (#e6e9e9) with no border. On selection, transition to `primary` (#291400) with `on_primary` (#ffffff) text.

 

---

 

## 6. Do’s and Don’ts

 

### Do:

*   **DO** use asymmetric card widths (e.g., a 2-column wide "Featured" card next to two 1-column "Standard" cards) to create an editorial rhythm.

*   **DO** use `surface_bright` (#f7fafa) for empty states to keep the interface feeling airy.

*   **DO** leverage `surface_tint` (#8a5100) at 5% opacity as an overlay on images to subtly pull them into the brand's color story.

 

### Don’t:

*   **DON'T** use pure black (#000000) for text. Always use `on_surface` (#181c1d) to maintain tonal softness.

*   **DON'T** use standard 1px borders to separate the sidebar from the main feed; use the shift from `surface_container_low` to `surface`.

*   **DON'T** use "Drop Shadows" on text. If text is over an image, use a subtle `primary` (#291400) gradient overlay at 30% opacity behind the text for legibility.