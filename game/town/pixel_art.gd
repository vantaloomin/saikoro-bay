class_name PixelArt
extends RefCounted
## Placeholder pixel sprites for the town, drawn into images in code so the
## greybox needs no art files: a 16 × 24 villager and a 14 × 14 mood bubble.
## Real sprite sheets replace these at the art pass.

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


static func villager(id: String) -> Image:
	var look: Array = LOOKS.get(id, DEFAULT_LOOK)
	var clothes: Color = look[0]
	var hair: Color = look[1]
	var accent: Color = look[2]
	var image: Image = Image.create(16, 24, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(5, 3, 6, 6), SKIN)  # face
	image.fill_rect(Rect2i(4, 1, 8, 3), hair)
	image.fill_rect(Rect2i(4, 4, 1, 4), hair)
	image.fill_rect(Rect2i(11, 4, 1, 4), hair)
	image.fill_rect(Rect2i(6, 6, 1, 1), OUTLINE)  # eyes
	image.fill_rect(Rect2i(9, 6, 1, 1), OUTLINE)
	image.fill_rect(Rect2i(4, 9, 8, 9), clothes)  # body
	image.fill_rect(Rect2i(4, 13, 8, 1), accent)  # sash
	image.fill_rect(Rect2i(3, 10, 1, 6), clothes)  # arms
	image.fill_rect(Rect2i(12, 10, 1, 6), clothes)
	image.fill_rect(Rect2i(3, 16, 1, 1), SKIN)
	image.fill_rect(Rect2i(12, 16, 1, 1), SKIN)
	image.fill_rect(Rect2i(5, 18, 2, 4), OUTLINE.lightened(0.2))  # legs
	image.fill_rect(Rect2i(9, 18, 2, 4), OUTLINE.lightened(0.2))
	if id == "shrine_keeper":
		image.fill_rect(Rect2i(4, 0, 2, 2), hair)  # fox ears
		image.fill_rect(Rect2i(10, 0, 2, 2), hair)
		image.fill_rect(Rect2i(4, 18, 8, 3), accent)  # red hakama
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
