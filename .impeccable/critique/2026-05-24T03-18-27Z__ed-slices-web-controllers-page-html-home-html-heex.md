---
target: lib/supervised_slices_web/controllers/page_html/home.html.heex
total_score: 25
p0_count: 0
p1_count: 2
p2_count: 3
timestamp: 2026-05-24T03-18-27Z
slug: ed-slices-web-controllers-page-html-home-html-heex
---
## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Nav auth state correct; no interactions to give feedback on |
| 2 | Match System / Real World | 3 | "The Rail/Studio/Counter" need their descriptions to land; "Kitchen Command" in pricing contradicts "The Rail" everywhere else |
| 3 | User Control and Freedom | 3 | Marketing page; persistent nav and logo home link cover the basics |
| 4 | Consistency and Standards | 2 | CTA copy varies three ways; product names drift between sections |
| 5 | Error Prevention | 3 | No forms present; CTA destinations are consistent |
| 6 | Recognition Rather Than Recall | 3 | Features labeled and described inline; pricing spells out inclusions clearly |
| 7 | Flexibility and Efficiency | 2 | Annual pricing is text-only with no toggle; no pricing anchor in nav |
| 8 | Aesthetic and Minimalist Design | 2 | Identical pain cards; repeated uppercase kickers on every section; placeholder footer links add noise |
| 9 | Error Recovery | 3 | No error states applicable; anchor links resolve correctly |
| 10 | Help and Documentation | 1 | FAQ covers pre-sales questions but no support path, contact, or docs link |
| **Total** | | **25/40** | **Acceptable** |

## Anti-Patterns Verdict

**LLM assessment**: Yes, partially. The skeleton gives it away. Hero → pain cards → three feature columns → asymmetric collage → pricing → FAQ → final CTA block. This is the modal SaaS landing page shape. Four identical icon-heading-body pain cards are the "Identical card grids" ban. Repeated uppercase kicker above every section is explicitly called out as AI scaffolding in the brand bans.

**Deterministic scan**: detect.mjs entrypoint not found — unavailable.

**Visual overlays**: No browser automation available.

## Overall Impression

The bones are solid and the copy knows what it's doing. The asymmetric collage section is the one place the page escapes template gravity. The pain section is the emotional heart and the most generic block. The footer has href="#" placeholder links that will break trust at the moment closest to conversion.

## What's Working

1. **Asymmetric collage section (lines 204-293).** The 7/12 + 5/12 grid with the rotated "Zero Commission" callout card breaks the grid with a real POV.
2. **Final CTA math.** "$2,250 walking out the door. Chitline is a flat $79/month." Specific numbers beat abstract value claims.
3. **Pricing honesty.** Two tiers, concrete comparisons to Slice and Owner.com, "no card required" in FAQ.

## Priority Issues

**[P1] Pain section is an identical card grid**
- Four identical icon-heading-body cards in a 2x2 grid. No hierarchy between problems.
- Fix: Break the grid. Lead-stat format, alternating-row editorial layout. Remove the icons.
- Command: /impeccable layout

**[P1] Repeated uppercase kicker above every section heading**
- "Built for pizza shops" / "The Reality" / "Before You Sign Up" — same format on every section.
- Fix: Retire as section grammar. Use it once on the hero. Let H2s carry weight alone.
- Command: /impeccable clarify

**[P2] Product name drift in pricing**
- "The Rail" everywhere → "Kitchen Command ('The Rail')" in pricing checklist (line 333).
- Fix: Use "The Rail" everywhere. Change line 333 to "The Rail (Kitchen Queue)".
- Command: /impeccable clarify

**[P2] Footer placeholder links destroy trust**
- "Sustainability," "Sourcing," "Blog" all href="#". Broken nav signals unreadiness to skeptical operators.
- Fix: Remove Sustainability and Sourcing. Ship Blog or remove it. Keep only resolving links.
- Command: /impeccable clarify

**[P2] No social proof on a trust-dependent conversion page**
- No testimonials, customer counts, or shop names. Stats block (34 orders, $1,840 revenue) looks fabricated.
- Fix: Add a testimonials strip or single pull-quote. If real customers exist, use them.
- Command: /impeccable craft testimonials section

## Persona Red Flags

**Jordan (First-Timer)**: "No card required" is buried in the FAQ four screens down — needs to be under the primary CTA button. The three product names ("The Rail," etc.) read as jargon before the descriptions explain them.

**Marco (Project-specific: independent operator)**: "Multiple Locations" in Pro tier raises the question of whether Starter covers 2 locations. No answer on the page. May incorrectly assume they need Pro ($149) when they don't.

**Casey (Mobile)**: The asymmetric collage is `hidden md:grid` — on mobile, the entire imagery column disappears. The most visually striking section becomes a plain text block on the device most likely used by a shop owner checking this during a slow period.

## Minor Observations

- Nav links use text-xs — likely under 44px touch target on mobile.
- Hero subhead first sentence restates the headline claim without adding information.
- "The Rail / Studio / Counter" badges appear in the hero before they're defined.
- No #pricing anchor in the nav.
- Annual billing text-only with no toggle.

## Questions to Consider

- What if the pain section led with a number instead of an icon?
- Does The Rail/Studio/Counter naming resonate with operators or require decoding?
- What if the fabricated stats block used a real operator's numbers with attribution?
