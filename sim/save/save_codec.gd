class_name SaveCodec
extends RefCounted
## Turns a save payload (a plain Dictionary) into file text and back.
##
## File layout, two lines:
##   1. Header JSON: {"format": "saikoro-bay-save", "version": N, "seq": S, "sha256": "..."}
##   2. Payload JSON, exactly as hashed.
##
## `seq` goes up by one with every write to a slot, so when a slot has
## several good copies (save, .tmp, .bak) the newest one is easy to find.
##
## The hash covers the version, the sequence number and the payload line's
## raw text, so a truncated or edited file (header included) is caught
## before it is trusted. Saves from a newer version of the
## game are refused, never "upgraded" downwards. Older saves step through
## MIGRATIONS one version at a time.
##
## JSON gives every number back as a float. Payload readers should use
## read_int() so a whole number comes back as an int and anything else is
## rejected.

const FORMAT: String = "saikoro-bay-save"
const CURRENT_VERSION: int = 1

## Largest integer a JSON number (a double) holds exactly. Bigger values,
## like RNG states, must be saved as strings.
const MAX_SAFE_INT: int = 9007199254740991

enum Status {
	OK,
	EMPTY,          ## No text at all.
	BAD_HEADER,     ## Header line missing or not ours.
	BAD_CHECKSUM,   ## Payload doesn't match its hash (truncated or edited).
	BAD_PAYLOAD,    ## Payload isn't a JSON object.
	TOO_NEW,        ## Written by a newer game version. Never overwrite it.
	BAD_VERSION,    ## Version is missing, invalid, or has no migration path.
}

## Version N -> N + 1 upgrades. Each takes and returns a payload Dictionary.
## Example for when version 2 arrives:
##   2: func(p: Dictionary) -> Dictionary: ...   (upgrades a v1 payload to v2)
## Keyed by the version they produce.
static var MIGRATIONS: Dictionary[int, Callable] = {}


class DecodeResult:
	extends RefCounted
	var status: Status = Status.OK
	var version: int = 0
	var seq: int = 0
	var payload: Dictionary = {}

	func is_ok() -> bool:
		return status == Status.OK


static func encode(payload: Dictionary, seq: int = 0) -> String:
	var body: String = JSON.stringify(payload, "", true, true)
	var header: Dictionary = {
		"format": FORMAT,
		"version": CURRENT_VERSION,
		"seq": seq,
		"sha256": digest(CURRENT_VERSION, seq, body),
	}
	return JSON.stringify(header, "", true) + "\n" + body + "\n"


## `target_version` is for tests of the migration path; the game always
## decodes to CURRENT_VERSION.
static func decode(text: String, target_version: int = CURRENT_VERSION) -> DecodeResult:
	var result: DecodeResult = DecodeResult.new()
	if text.strip_edges().is_empty():
		result.status = Status.EMPTY
		return result

	var split_at: int = text.find("\n")
	if split_at < 0:
		result.status = Status.BAD_HEADER
		return result
	var header_value: Variant = _parse(text.substr(0, split_at))
	if not header_value is Dictionary:
		result.status = Status.BAD_HEADER
		return result
	var header: Dictionary = header_value
	if header.get("format") != FORMAT:
		result.status = Status.BAD_HEADER
		return result

	var version: int = read_int(header, "version", -1)
	if version < 1:
		result.status = Status.BAD_VERSION
		return result
	result.version = version
	result.seq = maxi(read_int(header, "seq", 0), 0)
	if version > target_version:
		result.status = Status.TOO_NEW
		return result

	var body: String = text.substr(split_at + 1).trim_suffix("\n")
	if digest(version, result.seq, body) != str(header.get("sha256", "")):
		result.status = Status.BAD_CHECKSUM
		return result
	var payload_value: Variant = _parse(body)
	if not payload_value is Dictionary:
		result.status = Status.BAD_PAYLOAD
		return result

	var payload: Dictionary = payload_value
	for next_version: int in range(version + 1, target_version + 1):
		if not MIGRATIONS.has(next_version):
			result.status = Status.BAD_VERSION
			return result
		var migrated: Variant = MIGRATIONS[next_version].call(payload)
		if not migrated is Dictionary:
			result.status = Status.BAD_VERSION
			return result
		payload = migrated
	result.version = target_version
	result.payload = payload
	return result


## The integrity hash for a file's header numbers and payload line.
static func digest(version: int, seq: int, body: String) -> String:
	return ("%d\n%d\n%s" % [version, seq, body]).sha256_text()


## Parses JSON quietly: bad text gives null instead of an engine error.
static func _parse(text: String) -> Variant:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


## Reads a whole number from parsed JSON. Accepts an int, a float with no
## fractional part inside the safe range, or a numeric string. Anything else
## (missing, 1.5, "abc", true) gives `fallback`.
static func read_int(data: Dictionary, key: String, fallback: int = 0) -> int:
	var value: Variant = data.get(key)
	return to_int_or(value, fallback)


## The same rule as read_int(), for values already pulled out of a payload.
static func to_int_or(value: Variant, fallback: int) -> int:
	match typeof(value):
		TYPE_INT:
			return value as int
		TYPE_FLOAT:
			var f: float = value as float
			if is_finite(f) and f == floorf(f) and absf(f) <= float(MAX_SAFE_INT):
				return int(f)
		TYPE_STRING:
			var s: String = value as String
			if s.is_valid_int():
				return s.to_int()
	return fallback


static func is_int_like(value: Variant) -> bool:
	# Two different fallbacks only agree when the value really is a whole number.
	return to_int_or(value, 0) == to_int_or(value, 1)
