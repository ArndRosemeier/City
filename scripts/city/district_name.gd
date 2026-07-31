## Proper name for a city tile: an invented stem worn in the theme's naming pattern.
##
## Signposts have to name the tile next door, and that name must survive a world reload,
## a district unload, or a hop from the other side of the map. So it is derived from the
## same `DistrictCoord.district_seed` that already picks the theme — never from load order,
## a counter, or anything the streamer does at runtime. Same world seed + same coord always
## yields the same name.
##
## The stem is syllable-built ("Anoha", "Tervin"), and `DistrictTheme.name_pattern` decides
## whether the theme word reads as a suffix ("Anoha-Hill") or a prefix ("Lake Anoha").
class_name DistrictName
extends RefCounted

## Salt for the name RNG so this stream never walks in step with the theme pick or a cell RNG.
const NAME_FEATURE_ID := 0x4E414D

## Syllable tables, all lowercase — the stem is capitalised once at the end. The first
## syllable may open on a bare vowel (the blank entries), which is what gives names like
## "Anoha" instead of everything starting on a consonant.
const FIRST_ONSETS: Array[String] = [
	"", "", "",
	"b", "d", "f", "g", "h", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z",
	"br", "dr", "gl", "kr", "sh", "th", "tr",
]
## Interior onsets lean on single consonants: stacking clusters syllable after syllable turns a
## name into a tongue-twister ("Tithoadriark") rather than a place.
const ONSETS: Array[String] = [
	"b", "d", "f", "g", "h", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z",
	"b", "d", "k", "l", "m", "n", "r", "s", "t",
	"ll", "nd", "rr", "th",
]
const VOWELS: Array[String] = ["a", "e", "i", "o", "u"]
## At most one syllable per name draws from here, for the same reason.
const VOWELS_LONG: Array[String] = ["ae", "ei", "ia", "oa", "ou"]
## Mostly empty: an open final syllable ("Anoha") should be the common case.
const CODAS: Array[String] = [
	"", "", "", "", "n", "r", "l", "s", "m", "th", "nd", "rk",
]

## Three syllables read as a place more often than two, so weight them that way.
const THREE_SYLLABLE_CHANCE := 0.6
const LONG_VOWEL_CHANCE := 0.35


## The bare invented word, no theme wording, e.g. "Anoha".
static func stem(district_seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = DistrictCoord.feature_seed(district_seed_value, NAME_FEATURE_ID)
	var syllables := 3 if rng.randf() < THREE_SYLLABLE_CHANCE else 2
	var first_onset := _pick(rng, FIRST_ONSETS)
	var long_at := -1
	if rng.randf() < LONG_VOWEL_CHANCE:
		## A digraph straight after a bare-vowel opening reads as noise ("Iamaebra"), so when
		## the name starts on a vowel the long syllable has to be one of the later ones.
		var earliest := 1 if first_onset.is_empty() else 0
		if earliest < syllables:
			long_at = rng.randi_range(earliest, syllables - 1)
	var out := ""
	for i in syllables:
		out += first_onset if i == 0 else _pick(rng, ONSETS)
		out += _pick(rng, VOWELS_LONG) if i == long_at else _pick(rng, VOWELS)
	## Coda on the last syllable only: every onset is then preceded by a vowel, so no
	## consonant cluster can form across a syllable seam.
	out += _pick(rng, CODAS)
	return out.substr(0, 1).to_upper() + out.substr(1)


## Full label for a tile, e.g. "Anoha-Hill" or "Port Tervin".
static func for_district(world_seed: int, coord: Vector2i) -> String:
	var theme := DistrictTheme.for_district(world_seed, coord)
	return apply_pattern(theme, stem(DistrictCoord.district_seed(world_seed, coord)))


static func apply_pattern(theme: DistrictTheme, stem_name: String) -> String:
	if theme.name_pattern.count("%s") != 1:
		push_error(
			"DistrictName: theme '%s' has name_pattern '%s' — needs exactly one %%s"
			% [theme.display_name, theme.name_pattern]
		)
		return stem_name
	return theme.name_pattern % stem_name


static func _pick(rng: RandomNumberGenerator, pool: Array[String]) -> String:
	return pool[rng.randi_range(0, pool.size() - 1)]
