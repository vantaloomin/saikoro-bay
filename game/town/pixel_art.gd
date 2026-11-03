class_name PixelArt
extends RefCounted
## Placeholder pixel sprites for the town, drawn into images in code so the
## greybox needs no art files: an 18 × 32 villager (the production size), a
## 14 × 14 mood bubble and a padlock. Real sprite sheets replace these at the
## art pass.

## The tallest villager's sprite, in pixels (Mara's pick from the size
## mock, Nov 3); everyone else stands a few rows shorter.
const VILLAGER_PIXELS: Vector2i = Vector2i(18, 32)
const OUTLINE: Color = Color(0.16, 0.12, 0.12)
const SKIN: Color = Color(0.97, 0.82, 0.68)
## [clothes, hair, accent] per villager, so each reads apart at a glance.
const LOOKS: Dictionary[String, Array] = {
	"pearl_diver": [Color(0.2, 0.55, 0.6), Color(0.15, 0.12, 0.1), Color(0.95, 0.95, 0.9)],
	"shipwright": [Color(0.5, 0.35, 0.2), Color(0.35, 0.33, 0.3), Color(0.8, 0.7, 0.5)],
	"onsen_keeper": [Color(0.85, 0.5, 0.6), Color(0.25, 0.15, 0.12), Color(0.98, 0.85, 0.6)],
	"shrine_keeper": [Color(0.97, 0.96, 0.93), Color(0.9, 0.6, 0.3), Color(0.82, 0.22, 0.18)],
}
const DEFAULT_LOOK: Array = [Color(0.5, 0.5, 0.55), Color(0.2, 0.2, 0.2), Color(0.9, 0.9, 0.9)]


## Rows each villager stands below the tallest (characters.md section 7,
## Mara's pick from the size mock, Nov 3): Genzo 182 cm > Akane 174 >
## Natsu 168 > Chiyo 162, a 4 px ladder from top to bottom.
const HEIGHT_LADDER: Dictionary[String, int] = {"shipwright": 0, "shrine_keeper": 2, "pearl_diver": 3, "onsen_keeper": 4}
## Akane's fox ears, on top of her height and no taller than a third of her head.
const EAR_ROWS: int = 2


## How many pixel rows tall a villager's sprite is, ears included.
static func villager_rows(id: String) -> int:
	return VILLAGER_PIXELS.y - int(HEIGHT_LADDER.get(id, 2)) + (EAR_ROWS if id == "shrine_keeper" else 0)


## A villager, 3 heads tall and VILLAGER_PIXELS.x wide: hair, face, a
## sashed body and legs, in their own colors.
static func villager(id: String) -> Image:
	var look: Array = LOOKS.get(id, DEFAULT_LOOK)
	var clothes: Color = look[0]
	var hair: Color = look[1]
	var accent: Color = look[2]
	var w: int = VILLAGER_PIXELS.x
	var ears: int = EAR_ROWS if id == "shrine_keeper" else 0
	var h: int = villager_rows(id) - ears
	var image: Image = Image.create(w, h + ears, false, Image.FORMAT_RGBA8)
	var head: int = roundi(h / 3.0)
	var face_w: int = roundi(w * 0.55)
	var fx: int = (w - face_w) / 2
	image.fill_rect(Rect2i(fx, ears + 1, face_w, head - 1), SKIN)  # face
	image.fill_rect(Rect2i(fx - 1, ears, face_w + 2, maxi(head / 3, 2)), hair)
	image.fill_rect(Rect2i(fx - 1, ears + 2, 1, head / 2), hair)
	image.fill_rect(Rect2i(fx + face_w, ears + 2, 1, head / 2), hair)
	image.fill_rect(Rect2i(fx + face_w / 4, ears + head / 2, 1, 2), OUTLINE)  # eyes
	image.fill_rect(Rect2i(fx + face_w - 1 - face_w / 4, ears + head / 2, 1, 2), OUTLINE)
	var body_top: int = ears + head
	var legs: int = roundi(h * 0.28)
	var body: int = h - head - legs
	image.fill_rect(Rect2i(2, body_top, w - 4, body), clothes)  # body
	image.fill_rect(Rect2i(2, body_top + body / 2, w - 4, 1), accent)  # sash
	image.fill_rect(Rect2i(1, body_top + 1, 1, body - 2), clothes)  # arms
	image.fill_rect(Rect2i(w - 2, body_top + 1, 1, body - 2), clothes)
	image.fill_rect(Rect2i(1, body_top + body - 1, 1, 1), SKIN)
	image.fill_rect(Rect2i(w - 2, body_top + body - 1, 1, 1), SKIN)
	var leg_w: int = maxi(w / 5, 2)
	image.fill_rect(Rect2i(w / 2 - leg_w - 1, ears + h - legs, leg_w, legs - 1), OUTLINE.lightened(0.2))  # legs
	image.fill_rect(Rect2i(w / 2 + 1, ears + h - legs, leg_w, legs - 1), OUTLINE.lightened(0.2))
	if id == "shrine_keeper":
		image.fill_rect(Rect2i(fx, 0, 2, ears + 1), hair)  # fox ears
		image.fill_rect(Rect2i(fx + face_w - 2, 0, 2, ears + 1), hair)
		image.fill_rect(Rect2i(2, ears + h - legs, w - 4, legs / 2 + 1), accent)  # red hakama
	outline(image)
	return image


## Mood over a villager's head, told by shape as well as color (SA-5): a
## smiling bubble when happy, a rain cloud when not, and a little house
## with a gap in its roof when they have nowhere to live.
static func mood(value: Town.Mood) -> Image:
	var image: Image = Image.create(14, 14, false, Image.FORMAT_RGBA8)
	match value:
		Town.Mood.HAPPY:
			var teal: Color = TownStyle.HAPPY
			image.fill_rect(Rect2i(2, 1, 10, 10), teal)
			image.fill_rect(Rect2i(1, 2, 12, 8), teal)
			image.fill_rect(Rect2i(4, 4, 1, 2), Color.WHITE)
			image.fill_rect(Rect2i(9, 4, 1, 2), Color.WHITE)
			image.fill_rect(Rect2i(4, 7, 6, 1), Color.WHITE)
			image.fill_rect(Rect2i(3, 6, 1, 1), Color.WHITE)
			image.fill_rect(Rect2i(10, 6, 1, 1), Color.WHITE)
			image.fill_rect(Rect2i(5, 11, 3, 2), teal)
		Town.Mood.UNHAPPY:
			var plum: Color = TownStyle.UNHAPPY
			var rain: Color = Color(0.55, 0.7, 0.95)
			image.fill_rect(Rect2i(1, 4, 12, 4), plum)
			image.fill_rect(Rect2i(3, 2, 5, 3), plum)
			image.fill_rect(Rect2i(7, 1, 4, 4), plum)
			for drop: int in [3, 7, 11]:
				image.fill_rect(Rect2i(drop, 9, 1, 2), rain)
				image.fill_rect(Rect2i(drop - 1, 11, 1, 2), rain)
		Town.Mood.HOMELESS:
			var wall: Color = TownStyle.WASHI
			image.fill_rect(Rect2i(3, 6, 8, 6), wall)
			image.fill_rect(Rect2i(6, 9, 2, 3), OUTLINE.lightened(0.3))
			for step: int in 4:
				# A roof with its middle missing.
				image.fill_rect(Rect2i(2 + step, 5 - step, 1, 1), TownStyle.VERMILION)
				image.fill_rect(Rect2i(11 - step, 5 - step, 1, 1), TownStyle.VERMILION)
	outline(image)
	return image


## A 10 × 12 padlock for a building that isn't unlocked yet: a shape, so
## "locked" never rests on dimming alone.
static func padlock() -> Image:
	var image: Image = Image.create(10, 12, false, Image.FORMAT_RGBA8)
	var shackle: Color = TownStyle.DIM
	image.fill_rect(Rect2i(2, 1, 6, 1), shackle)
	image.fill_rect(Rect2i(2, 1, 1, 5), shackle)
	image.fill_rect(Rect2i(7, 1, 1, 5), shackle)
	image.fill_rect(Rect2i(1, 5, 8, 6), TownStyle.SAND.darkened(0.15))
	image.fill_rect(Rect2i(4, 7, 2, 2), OUTLINE)
	outline(image)
	return image


## A one-pixel dark outline around everything opaque, like a sprite sheet.
static func outline(image: Image) -> void:
	var source: Image = image.duplicate() as Image
	var steps: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y: int in image.get_height():
		for x: int in image.get_width():
			if source.get_pixel(x, y).a > 0.0:
				continue
			for step: Vector2i in steps:
				var near: Vector2i = Vector2i(x, y) + step
				if near.x >= 0 and near.y >= 0 and near.x < image.get_width() and near.y < image.get_height() \
						and source.get_pixelv(near).a > 0.0:
					image.set_pixel(x, y, OUTLINE)
					break
