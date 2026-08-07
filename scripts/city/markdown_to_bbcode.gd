## Markdown → BBCode for text authored outside the game, currently the Help sheet.
##
## A deliberately small subset — headings, paragraphs, bullets, bold, italic, inline code — so
## that `assets/help.md` stays a file anyone can edit in the gamedata editor without learning
## BBCode, and a stray bracket in the copy cannot open a tag the renderer then eats. Every raw
## `[` is escaped before a single tag of ours is added.
##
## Soft-wrapped lines are joined back into one paragraph the way Markdown means them: the help
## file wraps at column ~95 for the editor's sake, and honouring those newlines would put hard
## breaks in the middle of sentences at every window width.
class_name MarkdownToBbcode
extends RefCounted

const H1_SIZE := 26
const H2_SIZE := 19
const H3_SIZE := 16
## Warm parchment accent, matching the district picker's title colour.
const HEADING_COLOR := "#e8c88a"

## Block kinds the line scanner produces.
enum Block { PARAGRAPH, H1, H2, H3, BULLET }


static func convert(markdown: String) -> String:
	var blocks: Array[Dictionary] = _scan_blocks(markdown)
	var out: PackedStringArray = PackedStringArray()
	var prev_kind: int = -1
	for block: Dictionary in blocks:
		var kind: int = int(block["kind"])
		var text: String = _inline(str(block["text"]))
		## Bullets in the same run stay tight; everything else gets a blank line between it
		## and what came before.
		if not out.is_empty():
			var tight := kind == Block.BULLET and prev_kind == Block.BULLET
			out.append("\n" if tight else "\n\n")
		match kind:
			Block.H1:
				out.append("[font_size=%d][color=%s][b]%s[/b][/color][/font_size]"
					% [H1_SIZE, HEADING_COLOR, text])
			Block.H2:
				out.append("[font_size=%d][color=%s][b]%s[/b][/color][/font_size]"
					% [H2_SIZE, HEADING_COLOR, text])
			Block.H3:
				out.append("[font_size=%d][b]%s[/b][/font_size]" % [H3_SIZE, text])
			Block.BULLET:
				out.append("[indent]•  %s[/indent]" % text)
			Block.PARAGRAPH:
				out.append(text)
			_:
				push_error("MarkdownToBbcode.convert: unknown block kind %d" % kind)
		prev_kind = kind
	return "".join(out)


## One dictionary per block: `kind` from `Block`, `text` still in Markdown inline syntax.
static func _scan_blocks(markdown: String) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	## Lines of the block being accumulated, joined by spaces when it closes.
	var pending: PackedStringArray = PackedStringArray()
	var pending_kind: int = -1

	for raw_line: String in markdown.replace("\r\n", "\n").split("\n"):
		var line: String = raw_line.strip_edges()
		if line.is_empty():
			_flush(blocks, pending, pending_kind)
			pending = PackedStringArray()
			pending_kind = -1
			continue

		var heading := _heading_level(line)
		if heading > 0:
			_flush(blocks, pending, pending_kind)
			pending = PackedStringArray()
			pending_kind = -1
			var kind: int = Block.H1
			if heading == 2:
				kind = Block.H2
			elif heading >= 3:
				kind = Block.H3
			blocks.append({"kind": kind, "text": line.substr(heading + 1).strip_edges()})
			continue

		if line.begins_with("- ") or line.begins_with("* "):
			_flush(blocks, pending, pending_kind)
			pending = PackedStringArray([line.substr(2).strip_edges()])
			pending_kind = Block.BULLET
			continue

		## An indented line under a bullet continues that bullet; anything else is prose.
		if pending_kind == Block.BULLET and raw_line.begins_with(" "):
			pending.append(line)
			continue

		if pending_kind != Block.PARAGRAPH:
			_flush(blocks, pending, pending_kind)
			pending = PackedStringArray()
			pending_kind = Block.PARAGRAPH
		pending.append(line)

	_flush(blocks, pending, pending_kind)
	return blocks


static func _flush(
	blocks: Array[Dictionary], pending: PackedStringArray, kind: int
) -> void:
	if kind < 0 or pending.is_empty():
		return
	blocks.append({"kind": kind, "text": " ".join(pending)})


## 1, 2 or 3+ for an ATX heading, 0 when the line is not one.
static func _heading_level(line: String) -> int:
	var hashes := 0
	while hashes < line.length() and line[hashes] == "#":
		hashes += 1
	if hashes == 0 or hashes >= line.length():
		return 0
	if line[hashes] != " ":
		return 0
	return hashes


## Inline markup on one block's text. Brackets are escaped first, so authored copy can never
## produce a tag; every tag from here on is one we put in.
static func _inline(text: String) -> String:
	var out := text.replace("[", "[lb]")
	out = _replace_pairs(out, "`", "[code]", "[/code]")
	out = _replace_pairs(out, "**", "[b]", "[/b]")
	out = _replace_pairs(out, "*", "[i]", "[/i]")
	return out


## Turn `marker`-delimited spans into `open`/`close` tags. An unpaired trailing marker is left
## as written rather than swallowed, so a lone asterisk in the copy still reads as one.
static func _replace_pairs(text: String, marker: String, open: String, close: String) -> String:
	var out := ""
	var rest := text
	while true:
		var start := rest.find(marker)
		if start < 0:
			break
		var body_at := start + marker.length()
		var stop := rest.find(marker, body_at)
		if stop < 0:
			break
		var body := rest.substr(body_at, stop - body_at)
		if body.is_empty():
			## `**` / `` `` `` with nothing between them: not a span, keep the text as-is.
			out += rest.substr(0, stop + marker.length())
			rest = rest.substr(stop + marker.length())
			continue
		out += rest.substr(0, start) + open + body + close
		rest = rest.substr(stop + marker.length())
	return out + rest
