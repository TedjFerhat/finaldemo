# Art Direction: Museum exterior and entrance (milestone 1)

## What the first Studio inspection showed (Play mode, Plot 1)
1. **Overexposed lighting:** the ivory walls rendered pure white, and the trim couldn't be told apart from the walls, so the mouldings disappeared.
2. **Clutter in front of the entrance:** the navy plot sign stood in front of the steps, floating price labels hung in the yard, and the cyan neon pads were bright.
3. **Prototype-looking blockers:** raw wooden "LOCKED" boards showed through the front door and on the side wall.
4. **UI problems:** a red debug banner was the loudest thing on screen, and the ✕ / ☰ glyphs showed as empty boxes.
5. **Bare grounds:** a flat lawn with no landscaping.
6. **Real bugs in Output:** `TradeService.Start FAILED` (two remotes with the same name), and `swoosh.wav` was blocked.

## Palette and materials
| Role | Colour | Material |
|---|---|---|
| Walls | ivory 214,198,166 | Plaster |
| Carved trim | 236,228,208 | Limestone |
| Plinths and shadowed mouldings | 184,168,140 | Limestone |
| Rustication joints | 158,142,114 | Limestone |
| Bronze (doors, lanterns, rails) | 88,64,42 / 52,40,30 | Metal |
| Navy (plaques, dome, banners) | 24,36,66 | SmoothPlastic / Metal |
| Gold (keystones, finials, ribs only) | 196,156,72 | Metal |
| Glass | 34,40,52, reflectance 0.12 | Glass |

The tones are kept mid-value on purpose, so the stone never blows out to white.

## Layout (plot space; the entrance faces −Z)
- **Building:** same footprint, doorways, desk, slots and camera spots as before.
  - Rusticated ground floor with arched windows.
  - Upper floor: pedimented French windows, with stone balconies on the front.
  - Cornice, balustrade, corner quoins and dentils.
  - A curved glass bay with four columns and the crown plaque (owner name).
  - **Dome** on a pilastered drum over the main hall, with gilt ribs and a lantern.
- **Entrance focal point:**
  - A freestanding arched **frontispiece** on the top step: rusticated piers, a gilt keystone, a navy frieze reading "MUSEUM", and bronze lanterns.
  - Behind it, the wall portal with open bronze doors and warm light from inside.
- **Grounds:**
  - Gate piers with lanterns at the street (owner plaque on the left pier).
  - A paved path with a compass-rose inlay leading to a forecourt with kerbs, benches and two lanterns.
  - **Two parterre gardens:** hedge borders, gravel, two-tone flower beds, topiary cones, a round centre bed (the Fountain upgrade puts its fountains here) and a bronze statue at the far end of each.
  - Framing trees at the corners.
- **Upgrade pads:** moved to tidy rows on the side lawns (x = ±57). They are now bronze-ringed plinths whose labels only show within 34 studs.
- **Locked doorways:** navy velvet curtains on bronze rails, with a small "Coming soon" bronze plaque.
- **Exhibit labels:** small dark plaques that only appear within 14 studs.

## Lighting (to verify in Studio)
| Setting | Value |
|---|---|
| ClockTime | 16.2 (late-afternoon side light, so columns and cornices cast shadows) |
| Brightness | 2.4 |
| ExposureCompensation | −0.5 |
| OutdoorAmbient | 96,98,110 |
| Ambient | 60,56,52 |
| EnvironmentDiffuseScale / EnvironmentSpecularScale | 0.45 / 0.5 |
| Atmosphere | density 0.32, haze 0.9, glare 0.1 |
| One colour correction | contrast 0.10, saturation 0.08, warm tint |

There is no bloom.

## Verification status
- ✅ Type-check is clean and all 19 tests pass.
- ✅ The real builder code renders correctly in the offline preview.
- ⏳ **Still needed in Studio Play mode** (Studio disconnected during the session):
  - Check the lighting values above.
  - Check how Limestone and Plaster look at gameplay distance.
  - Check glass transparency, so the interior shows through.
  - Check that labels are readable at different screen sizes.
  - Check the part count and frame rate with 8 full museums.
- **Next milestones:** interior and exhibit fixtures, then a UI pass covering typography, iconography and responsive layouts.
