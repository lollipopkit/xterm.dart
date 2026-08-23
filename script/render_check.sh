#!/bin/sh
# Prints a page that makes a rendering defect visible in one screenshot.
#
#   sh script/render_check.sh
#
# The paint path is covered by tests, twice over: `flutter test` compares the
# two paths pixel for pixel on the host, and
#
#   cd example
#   flutter test integration_test/render_parity_test.dart -d macos
#
# makes the same comparison on the device's own rasteriser, which on macOS and
# iOS is Impeller rather than the Skia the host tests use.
#
# This page is for what neither covers: how it looks to a person, over a whole
# screen, in a font the tests do not have. Run it when something is reported
# that the parity test does not reproduce.
#
# The page is self-comparing, and does not need a build from before the change
# to compare against. A terminal draws a cell one of two ways, decided by
# whether it can join its neighbours in a run: a stretch of one colour is laid
# out as a paragraph, a cell whose neighbours differ is a sprite out of the
# glyph atlas. Each block below therefore prints the same characters twice, once
# each way, and the two rows should be indistinguishable.
#
# Non-ASCII is written as octal UTF-8 rather than literally, because a combining
# mark in a source file is invisible: one that got mangled in an edit would read
# as a page that passes while testing nothing.

esc=$(printf '\033')
r="${esc}[0m"

# U+0301 COMBINING ACUTE, U+0308 COMBINING DIAERESIS, U+030A COMBINING RING.
acute=$(printf '\314\201')
diaeresis=$(printf '\314\210')
ring=$(printf '\314\212')

# U+200D ZERO WIDTH JOINER, U+FE0F VARIATION SELECTOR-16.
zwj=$(printf '\342\200\215')
vs16=$(printf '\357\270\217')

# U+1F468 MAN, U+1F469 WOMAN, U+1F467 GIRL, U+1F44D THUMBS UP,
# U+1F3FD MEDIUM SKIN TONE, U+1F600 GRINNING FACE, U+1F6A7 CONSTRUCTION.
man=$(printf '\360\237\221\250')
woman=$(printf '\360\237\221\251')
girl=$(printf '\360\237\221\247')
thumb=$(printf '\360\237\221\215')
skin=$(printf '\360\237\217\275')
grin=$(printf '\360\237\230\200')
works=$(printf '\360\237\232\247')

# U+2764 HEAVY BLACK HEART, which is colour only with a variation selector.
heart=$(printf '\342\235\244')

# THAI CHARACTER KO KAI, MAI HAN AKAT, MAI THO, NO NU, SARA AM.
th_ko=$(printf '\340\270\201')
th_han=$(printf '\340\270\261')
th_tho=$(printf '\340\271\211')
th_no=$(printf '\340\270\231')
th_am=$(printf '\340\270\263')

heading() {
	printf '\n%s[1;36m%s%s\n' "$esc" "$1" "$r"
}

# The same text twice: once in a single colour, which coalesces into a run, and
# once with a colour change per cell, which cannot coalesce and so goes through
# the atlas a sprite at a time. The three colours are neighbouring greys, close
# enough to read as one, so anything that shows is the path and not the palette.
#
# $1 is the text, ASCII only: the per-cell loop indexes by character. $2 is an
# optional SGR to apply to both rows.
pair() {
	printf '  run    %s[38;5;250m%s%s%s\n' "$esc" "$2" "$1" "$r"

	printf '  atlas  %s' "$2"
	i=0
	while [ "$i" -lt "${#1}" ]; do
		printf '%s[38;5;%dm%s' "$esc" $((250 + i % 3)) \
			"$(printf '%s' "$1" | cut -c $((i + 1)))"
		i=$((i + 1))
	done
	printf '%s\n' "$r"
}

heading 'Weight and position: the two rows must look the same'
pair 'The quick brown fox jumps over the lazy dog 0123456789'
pair 'iiiillll11ooooOO00 mmmmwwww MMMMWWWW ..,,;;::'

heading 'Bold and italic take the atlas too'
pair 'Bold: handgloves ffi fjord' "${esc}[1m"
pair 'Italic: handgloves ffi fjord' "${esc}[3m"

heading 'Box drawing must join up between rows, with no gaps'
printf '  %s[38;5;250m%s\n' "$esc" '┌────────┬────────┐'
printf '  │ solid  │ colour │\n'
printf '  ├────────┼────────┤\n'
printf '  │ %s[38;5;251m│%s[38;5;250m      │ %s[38;5;252m│%s[38;5;250m      │\n' \
	"$esc" "$esc" "$esc" "$esc"
printf '  %s%s\n' '└────────┴────────┘' "$r"
printf '  A vertical broken into dashes at the row boundaries is a slot\n'
printf '  clipping its glyph. The right column is the atlas path.\n'

heading 'Underlines must be continuous across a colour change'
printf '  %s[4m%s[38;5;250mabcdef%s[38;5;110mghijkl%s\n' "$esc" "$esc" "$esc" "$r"
printf '  %s[9m%s[38;5;250mstrikethrough %s[38;5;110macross a colour change%s\n' \
	"$esc" "$esc" "$esc" "$r"

heading 'Colour emoji must stay in colour, not become silhouettes'
printf '  emoji presentation:   %s %s %s\n' "$grin" "$thumb" "$works"
printf '  text presentation:    %s %s%s\n' "$heart" "$heart" "$vs16"
printf '  The first of that pair is monochrome by default and the second is\n'
printf '  not. A solid single-coloured blob anywhere here is a colour glyph\n'
printf '  that reached the atlas and was tinted.\n'

heading 'Grapheme clusters: marks on the right base, one cell each'
printf '  latin:  e%s o%s a%s n%s%s\n' "$acute" "$diaeresis" "$ring" "$acute" "$diaeresis"
printf '  thai:   %s%s%s %s%s%s\n' "$th_ko" "$th_han" "$th_tho" "$th_no" "$th_tho" "$th_am"
printf '  zwj:    %s%s%s%s%s   skin tone: %s%s\n' \
	"$man" "$zwj" "$woman" "$zwj" "$girl" "$thumb" "$skin"
printf '  The family is one glyph in two columns, not three side by side.\n'
printf '  Then select this block and copy it: the marks must come along.\n'

heading 'Wide characters occupy exactly two columns'
printf '  %s[38;5;250m1234567890%s\n' "$esc" "$r"
printf '  中文中文中文\n'
printf '  The CJK row must end level with the digits above it.\n'

printf '\n'
