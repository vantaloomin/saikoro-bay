class_name Portrait
extends Control
## A villager's portrait on the date screen. Until the art exports land
## (art direction, portrait pipeline section 5) it draws the placeholder
## the pipeline describes: a flat silhouette in the character's hue with
## the expression id written on it. The hue comes from the character's
## portrait.json when it exists, so real manifests take over without code
## changes.
##
## Faces swap with an 80 ms cross-fade of the face only; under reduce motion
## they cut.

const MANIFEST: String = "res://content/sfw/portraits/%s/portrait.json"
## Fallback hues from the art direction spec, used until a manifest exists.
const HUES: Dictionary[String, Color] = {
	"pearl_diver": Color("1f5a8a"),
	"shipwright": Color("805933"),
	"onsen_keeper": Color("d9809a"),
	"shrine_keeper": Color("e69a4d"),
	"koban": Color("e0b84a"),
}
const FACE_FADE: float = 0.08

var character: String = ""
var face: String = "neutral"
var hue: Color = TownStyle.STONE
## 0 to 1: how far the face text has faded in after a swap.
var _face_alpha: float = 1.0


## Shows `who` with `expression`. A blank expression keeps the last one.
func show_face(who: String, expression: String) -> void:
	if who != character:
		character = who
		hue = hue_of(who)
		face = "neutral"
	var next: String = expression if DialogueCheck.FACES.has(expression) else face
	if next != face:
		face = next
		if not Settings.reduce_motion and is_inside_tree():
			_face_alpha = 0.0
			create_tween().tween_property(self, "_face_alpha", 1.0, FACE_FADE).finished.connect(queue_redraw)
	queue_redraw()


## The character's hue: portrait.json's "hue" if it has one, else the
## spec's fallback, else stone.
static func hue_of(who: String) -> Color:
	var path: String = MANIFEST % who
	if FileAccess.file_exists(path):
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if manifest is Dictionary and str((manifest as Dictionary).get("hue", "")).is_valid_html_color():
			return Color(str((manifest as Dictionary)["hue"]))
	return HUES.get(who, TownStyle.STONE)


func _process(_delta: float) -> void:
	if _face_alpha < 1.0:
		queue_redraw()


func _draw() -> void:
	if character.is_empty():
		return
	var w: float = size.x
	var h: float = size.y
	var outline: Color = hue.darkened(0.35)
	# Shoulders and body: a rounded block rising from the bottom edge.
	var body: Rect2 = Rect2(w * 0.12, h * 0.52, w * 0.76, h * 0.48)
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = hue
	box.border_color = outline
	box.set_border_width_all(4)
	box.corner_radius_top_left = int(w * 0.3)
	box.corner_radius_top_right = int(w * 0.3)
	draw_style_box(box, body)
	# Head.
	var head: Vector2 = Vector2(w * 0.5, h * 0.33)
	var radius: float = minf(w, h) * 0.2
	draw_circle(head, radius + 4.0, outline)
	draw_circle(head, radius, hue.lightened(0.12))
	# The expression id, where the face would be.
	var font: Font = TownStyle.strong_font()
	var text_color: Color = Color.WHITE if hue.get_luminance() < 0.55 else TownStyle.INK
	text_color.a = _face_alpha
	draw_string(font, head + Vector2(-radius, 10.0), face, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0,
		TownStyle.SMALL, text_color)
