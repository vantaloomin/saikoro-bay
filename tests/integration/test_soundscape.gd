extends GutTest
## The ambience beds and stingers (Soundscape): every file is there and
## loops the right way, each half gets its own bed, and the stingers fire
## on the events that own them.


func after_each() -> void:
	Soundscape.play_bed("")


func test_every_stinger_loads_and_plays_once() -> void:
	for cue: String in Soundscape.STINGERS:
		var stream: AudioStreamOggVorbis = load(Soundscape.SFX_DIR + cue + ".ogg") as AudioStreamOggVorbis
		assert_not_null(stream, cue)
		if stream != null:
			assert_false(stream.loop, "%s plays once" % cue)
			assert_lt(stream.get_length(), 4.0, "%s is a stinger, not a bed" % cue)


func test_every_bed_loads_and_loops() -> void:
	for scene: String in Soundscape.BEDS:
		var bed: String = Soundscape.BEDS[scene]
		var stream: AudioStreamOggVorbis = load(Soundscape.AMBIENCE_DIR + bed + ".ogg") as AudioStreamOggVorbis
		assert_not_null(stream, bed)
		if stream != null:
			assert_true(stream.loop, "%s loops (its .import sets loop=true)" % bed)
		assert_true(Soundscape.BED_DB.has(bed), "%s has a level" % bed)


func test_each_half_has_its_own_bed() -> void:
	assert_eq(Soundscape.BEDS.get(Game.TOWN_SCENE, ""), "town_bed")
	assert_eq(Soundscape.BEDS.get(Game.DELVE_SCENE, ""), "palace_bed")


func test_a_bed_fades_out_when_the_next_starts() -> void:
	Soundscape.play_bed("town_bed")
	assert_eq(Soundscape.bed, "town_bed")
	var first: AudioStreamPlayer = Soundscape.get_node("Bed") as AudioStreamPlayer
	assert_eq(first.bus, &"SFX")
	Soundscape.play_bed("palace_bed")
	assert_eq(Soundscape.bed, "palace_bed")
	await wait_seconds(Soundscape.BED_FADE_OUT + 0.2)
	assert_false(is_instance_valid(first), "the old bed is freed once it has faded")


func test_the_tide_sounds_its_direction() -> void:
	Soundscape._on_transition_started(TideTransition.Direction.DOWN)
	assert_eq(Soundscape.played.slice(-1), ["tide_down"] as Array[String])
	Soundscape._on_transition_started(TideTransition.Direction.UP)
	assert_eq(Soundscape.played.slice(-1), ["tide_up"] as Array[String])


func test_the_barrel_takes_turns() -> void:
	assert_eq([Soundscape.barrel_for(1), Soundscape.barrel_for(2), Soundscape.barrel_for(3), Soundscape.barrel_for(4)],
		["barrel_2", "barrel_3", "barrel_1", "barrel_2"])


func test_the_vault_opens_with_koban_s_stinger() -> void:
	var data: GameData = Game.data
	var haul: Haul = Haul.new()
	var vault: Vault = Vault.create(data, "fresh", "koban", RngStreams.new(3), [] as Array[Dictionary], haul)
	var board: VaultBoard = VaultBoard.new()
	board.setup(vault, data, "Café")
	add_child_autofree(board)
	assert_eq(Soundscape.played.slice(-1), ["koban_vault"] as Array[String])
