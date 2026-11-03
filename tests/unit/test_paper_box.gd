extends GutTest
## The town's hand-drawn panels (M3 PR 5c): the edge wobbles the same way
## every time, stays close to the true rect, and a tab is open at the
## bottom so it can join the sheet under it.

const RECT: Rect2 = Rect2(10, 20, 300, 120)


func test_the_edge_wobbles_the_same_way_every_time() -> void:
	var box: PaperBox = PaperBox.make(PaperBox.Kind.PAPER)
	assert_eq(box._rounded(RECT, 14.0, false), box._rounded(RECT, 14.0, false))
	box.grain = 3
	var other: PaperBox = PaperBox.make(PaperBox.Kind.PAPER)
	assert_ne(box._rounded(RECT, 14.0, false), other._rounded(RECT, 14.0, false), "grain picks the wobble")


func test_the_edge_stays_on_the_rect() -> void:
	var box: PaperBox = PaperBox.make(PaperBox.Kind.PAPER)
	for point: Vector2 in box._rounded(RECT, 14.0, false):
		assert_true(RECT.grow(PaperBox.WOBBLE + 0.01).has_point(point), "%s is on the rect" % point)


func test_a_tab_is_open_at_the_bottom() -> void:
	var box: PaperBox = PaperBox.make(PaperBox.Kind.TAB)
	var points: PackedVector2Array = box._rounded(RECT, 12.0, true)
	assert_eq(points[0], Vector2(RECT.position.x, RECT.end.y), "it starts at the bottom left")
	assert_eq(points[points.size() - 1], RECT.end, "and ends at the bottom right")
	assert_false(box.shadow, "a tab casts no shadow onto its sheet")


func test_the_furniture_makes_room_for_its_frame() -> void:
	var ledger: PaperBox = PaperBox.make(PaperBox.Kind.LEDGER, 18.0)
	assert_eq(ledger.content_margin_left, 18.0 + PaperBox.SPINE, "text clears the ledger's spine")
	var board: PaperBox = PaperBox.make(PaperBox.Kind.BOARD, 18.0)
	assert_eq(board.content_margin_top, 18.0 + PaperBox.RIM, "notes sit inside the driftwood rim")
	assert_eq(board.fill, TownStyle.DRIFTWOOD)
