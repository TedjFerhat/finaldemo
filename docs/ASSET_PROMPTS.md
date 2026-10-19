# 3D Asset Prompt Library — Museum Tycoon: Lost Treasures

Paste a prompt into your 3D generation or modelling tool. Every prompt assumes these **shared rules**:

- **Style:** stylised-realistic Roblox look, with strong silhouettes, bevelled edges and hand-painted wear. No photoscan noise.
- **Technical:** one mesh (or a few parts), clean pivot at the **bottom centre**, front facing **−Z**, under 4k triangles for artefacts (under 10k for architecture), one 1024² texture set (512² for small items), clean UVs, FBX/OBJ export.
- **Performance:** no floating micro-details, no internal faces, no detail smaller than ~0.1 stud at gameplay scale.
- **Avoid:** blocky "default part" looks, meaningless ornaments, noisy textures, glowing effects standing in for real detail.

**Importing:** in Studio, go to **Home → Import 3D**, import the file, then put the Model in a Folder named `ItemModels` inside **ReplicatedStorage**. The model's name must be the item id, e.g. `jg_sun_disk`. It then replaces the placeholder everywhere (displays, inventory, discovery pop-up). Scale it so it's about 2 studs tall, or use the sizes below.

---

## Jungle Temple artefacts

**Asset name:** Sun Disk of the Jaguar King (`jg_sun_disk`, Mythic)
**Concept and origin:** The temple's heart, a ceremonial gold sun hidden beneath the eagle statue in the sanctum. Its legend says that whoever holds it holds the dawn.
**Silhouette:** A round disc with 12 flame-shaped rays and a small stepped stand. It must read as "sun" from 30 studs away.
**Primary geometry:** A 2.4-stud disc, 0.3 thick, with a raised inner ring. The rays alternate long and short. A trapezoid stand sits below.
**Secondary geometry:** A carved jade jaguar face in the centre. An inner ring of 20 glyph cartouches. A rim bead border.
**Materials:** Beaten gold with darker recesses, polished jade and a weathered stone stand.
**Surface detail:** Hammer marks, worn highlights on the ray tips, green-black grime in the cartouche recesses.
**Colour palette:** Gold #F0BE3C, deep gold #A67C1E, jade #3C966E, stone #6E6A5E.
**Scale:** 3 studs tall including the stand (about half a character's height). It is displayed in a Vault.
**Presentation:** Upright and facing the viewer. It must read well as a 128 px inventory icon, so keep the jade face large.

**Asset name:** Jade Mosaic Death Mask (`jg_mosaic_mask`, Epic)
**Concept:** A burial mask for a jungle king: hundreds of jade tiles, shell eyes and obsidian pupils.
**Silhouette:** An oval face with a flat brow line and slightly protruding ears.
**Primary geometry:** A curved shell (not a flat plane) 0.5 thick, with nose and lip relief.
**Secondary geometry:** Visible tile seams (bevelled, not texture-only, on the large tiles), shell eye inlays and ear-spools.
**Materials:** Jade in three tones, white shell, obsidian and red cinnabar lips.
**Surface:** A few missing tiles, dark mortar lines, and a polish on the cheekbones.
**Palette:** Jade #2E7D5B / #3C966E / #5BB38A, shell #F0F0E6, obsidian #141418, cinnabar #963028.
**Scale:** 2.3 studs tall, displayed in a glass case or on a pedestal.

**Asset name:** Gold Serpent Pectoral (`jg_serpent_pectoral`, Legendary)
**Concept:** A chest ornament: a feathered serpent coiled around a jade heart.
**Silhouette:** A horseshoe-shaped coil with the serpent head at the top right and a diamond heart in the centre.
**Primary geometry:** A tapered tube coil, 12 scale segments and a chain loop at the top.
**Secondary geometry:** Feather crests along the head, fangs, and scale engraving.
**Materials:** Gold with a jade heart. **Palette:** #E6B43C, #28967A.
**Scale:** 2 studs wide, displayed in a glass case.

**Asset name:** Carved Jade Jaguar (`jg_jade_jaguar`, Rare)
**Concept:** A crouching jaguar carved from a single boulder.
**Silhouette:** A low crouch with a raised head, a tail curled forward and rounded ears.
**Primary geometry:** A compact body (no thin legs that would break the silhouette) on a small integrated base.
**Secondary geometry:** Rosette spots carved shallowly, plus eye and mouth grooves.
**Materials:** Translucent green jade (Glass-like). Keep it slightly matte. **Scale:** 1.8 studs long.

**Asset name:** Engraved Calendar Stone (`jg_calendar`, Rare)
**Concept:** A day-count stone with 20 glyphs circling a sun.
**Silhouette:** A thick disc on a short plinth.
**Detail:** A raised glyph band and a central sun face with a tongue. The edges are chipped.
**Materials:** Grey-green andesite with moss in the recesses. **Scale:** 2.6 studs diameter.

**Asset name:** Painted Ritual Vessel (`jg_vessel`, Uncommon)
**Concept:** A cacao vessel on three feet, painted with dancing jaguars.
**Silhouette:** A cylinder with a flared rim and three small cone feet.
**Detail:** A painted band (in the texture), a chipped rim and one hairline crack.
**Materials:** Orange fired clay with black and cream slip paint. **Scale:** 2 studs tall.

---

## Forgotten Ruins artefacts (replacements for existing items)

**Gold Sun Coin (`coin_gold_sun`):** A 1.6-stud disc with real thickness (0.2), a raised beaded rim, and a radiant-sun emblem in relief on the front. The back has a wheat stalk. Use gold with a slight patina in the recesses. It must read well from the side, so the edge is milled.

**Painted Ruin Vase (`vase_painted`):** A black-figure amphora: tall neck, two looping handles, a frieze of running figures (texture) and a key-pattern band. Fired orange and black, with wear on the handle tops. 2.5 studs tall.

**Crown of the Forgotten Queen (`crown_forgotten_queen`):** A gold band with 6 lily-shaped points. Each point holds a cabochon sapphire, plus one larger stone at the front. Show the inner band thickness. Polished gold with darker crevices. 1.8 studs wide.

**Stone Owl of Wisdom (`statue_owl`):** A seated owl with ear tufts and a feathered chest carved in layers. One eye is a polished obsidian inlay and the other is an empty socket. Weathered granite. 2.5 studs tall.

**Raptor Skull (`skull_raptor`):** A long skull with large eye sockets, serrated teeth and a lower jaw slightly open. It sits on a small museum mount, with a fossil-bone texture and matrix stone in the crevices. 2.6 studs long.

---

## Environment & museum assets

**Guardian Pillar (Jungle courtyard):** A 10-stud square stone pillar on a base. The top is a 4.4-stud carved head block with four flat faces. Each face carries a large animal relief (jaguar, serpent, eagle, monkey). Moss on the top and vines hanging down the front. The head must be a **separate part** named `GuardianHead` so the puzzle can label it.

**Security Camera (museum):** A wall arm, a rectangular housing and a recessed lens with a red LED. Make a tier-3 variant with an armoured hood. Pivot at the wall mount. The camera must face −Z (that's the direction it "sees").

**Reinforced Display Case:** A dark wood base and a 3-stud glass cube with a metal frame. Make 4 frame variants: gold, silver, gunmetal, black steel, to match glass tiers 0–3. The glass part must be named `Glass` and the top frame `Frame`.

**Jungle Tree:** A 40-stud trunk with buttress roots (5 fins), a layered umbrella canopy (2–3 leaf clusters, not a sphere) and 4 hanging vine strands. Keep it under 3k triangles and use a single material atlas.

**Stele (inscription stone):** A 4 × 6 stud standing stone with a carved border and a weathered cap stone. Leave the front face flat and smooth so SurfaceGui text stays readable.
