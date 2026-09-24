#!/usr/bin/env bash
# Render fastfetch inside a closed box.
#
# fastfetch cannot do this itself: values are variable length and it has no
# line-padding or right-align facility (--key-width aligns keys only, and
# format strings take no width specifier), so the right-hand border cannot be
# closed from config. This runs fastfetch without its logo, measures the
# rendered width, draws the four edges to fit, then pastes the logo alongside.
#
# Extra arguments are forwarded to fastfetch.

set -euo pipefail

MP_ROOT=${MYPROMPTS_ROOT:-"$HOME/.local/share/myprompts"}
BOX_CONFIG=${BOXFETCH_CONFIG:-"$MP_ROOT/fastfetch/config-boxed.jsonc"}
BOX_LOGO=${BOXFETCH_LOGO:-"$HOME/.config/fastfetch/signalmine.txt"}
BOX_COLOR_1=${BOXFETCH_COLOR_1:-'38;5;44'}
BOX_COLOR_2=${BOXFETCH_COLOR_2:-'38;5;24'}
BOX_GAP=${BOXFETCH_GAP:-5}
# Width to fit inside. 0 disables the check, which is what a redirect wants.
if [[ -t 1 ]]; then
    BOX_COLUMNS=${BOXFETCH_COLUMNS:-$(tput cols 2>/dev/null || echo 0)}
else
    BOX_COLUMNS=${BOXFETCH_COLUMNS:-0}
fi

if ! command -v fastfetch >/dev/null 2>&1; then
    printf 'boxfetch: fastfetch is not installed\n' >&2
    exit 1
fi

info=$(fastfetch --config "$BOX_CONFIG" --logo none --pipe false "$@")

# LC_ALL=C keeps awk byte-based so the width maths is the same under BSD awk,
# mawk and gawk; stripping UTF-8 continuation bytes turns bytes back into
# columns for the non-ASCII values fastfetch sometimes reports.
LC_ALL=C awk \
    -v c1="$BOX_COLOR_1" -v c2="$BOX_COLOR_2" -v gap="$BOX_GAP" -v offset=1 \
    -v logofile="$BOX_LOGO" -v cols="$BOX_COLUMNS" '
function vlen(s) {
    gsub(/\033\[[0-9;]*m/, "", s)
    gsub(/[\200-\277]/, "", s)
    return length(s)
}
function spaces(n,   s) { s = ""; while (n-- > 0) s = s " "; return s }
# Cut to n columns without counting or severing the escape sequences.
function clip(str, n,   out, i, ch, seen, m) {
    if (vlen(str) <= n) return str
    out = ""; seen = 0; i = 1
    while (i <= length(str) && seen < n) {
        if (substr(str, i, 1) == esc) {
            m = match(substr(str, i), /^\033\[[0-9;]*m/)
            if (m) { out = out substr(str, i, RLENGTH); i += RLENGTH; continue }
        }
        ch = substr(str, i, 1)
        out = out ch
        if (ch !~ /[\200-\277]/) seen++
        i++
    }
    return out reset
}
function dashes(n,   s) { s = ""; while (n-- > 0) s = s "-"; return s }

BEGIN {
    nlogo = 0
    logow = 0
    ni = 0

    esc = sprintf("%c", 27)
    e1 = esc "[" c1 "m"
    e2 = esc "[" c2 "m"
    reset = esc "[0m"
    # A literal apostrophe would close the single-quoted awk program.
    tick = sprintf("%c", 39)

    while ((getline line < logofile) > 0) {
        plain = line
        gsub(/\$[12]/, "", plain)
        lw = vlen(plain)
        if (lw > logow) logow = lw
        gsub(/\$1/, e1, line)
        gsub(/\$2/, e2, line)
        logo[nlogo] = line reset
        logolen[nlogo] = lw
        nlogo++
    }
    close(logofile)
}

{ info[ni] = $0; ni++ }

END {
    # Trim the blank lines fastfetch emits for the leading/trailing break.
    first = 0
    while (first < ni && vlen(info[first]) == 0) first++
    last = ni - 1
    while (last >= first && vlen(info[last]) == 0) last--

    width = 0
    for (i = first; i <= last; i++)
        if (vlen(info[i]) > width) width = vlen(info[i])

    # Keep the box inside the terminal; a box that wraps is worse than a
    # truncated value.  3 columns cover the gutter and the right rail.
    if (cols > 0) {
        avail = cols - (logow + gap) - 3
        if (avail > 20 && width > avail) width = avail
    }

    rail = width + 2
    nbox = 0
    box[nbox++] = e1 " ." dashes(rail - 2) "." reset
    for (i = first; i <= last; i++) {
        row = clip(info[i], width)
        box[nbox++] = row spaces(width - vlen(row)) "  " e1 ":" reset
    }
    box[nbox++] = e1 " `" dashes(rail - 2) tick reset

    rows = nlogo
    if (nbox + offset > rows) rows = nbox + offset

    for (i = 0; i < rows; i++) {
        left = (i < nlogo) ? logo[i] : ""
        lw = (i < nlogo) ? logolen[i] : 0
        j = i - offset
        right = (j >= 0 && j < nbox) ? box[j] : ""
        line = left spaces(logow - lw + gap) right
        sub(/[ \t]+$/, "", line)
        print line
    }
}
' <<<"$info"
