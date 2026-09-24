#!/usr/bin/env bash
# Render fastfetch inside a closed box.
#
# fastfetch cannot do this itself: values are variable length and it has no
# line-padding or right-align facility (--key-width aligns keys only, and
# format strings take no width specifier), so the right-hand border cannot be
# closed from config. This runs fastfetch without its logo, measures the
# rendered width, draws the four edges to fit, then pastes the logo alongside.
# In a narrow terminal long values wrap inside the box, and the logo is
# moved above the box once it would squeeze the box below BOXFETCH_MIN_WIDTH.
#
# Extra arguments are forwarded to fastfetch.

set -euo pipefail

MP_ROOT=${MYPROMPTS_ROOT:-"$HOME/.local/share/myprompts"}
BOX_CONFIG=${BOXFETCH_CONFIG:-"$MP_ROOT/fastfetch/config-boxed.jsonc"}
BOX_LOGO=${BOXFETCH_LOGO:-"$HOME/.config/fastfetch/signalmine.txt"}
BOX_COLOR_1=${BOXFETCH_COLOR_1:-'38;5;44'}
BOX_COLOR_2=${BOXFETCH_COLOR_2:-'38;5;24'}
BOX_GAP=${BOXFETCH_GAP:-5}
# Narrowest the box may get beside the logo before the logo is dropped.
BOX_MIN_WIDTH=${BOXFETCH_MIN_WIDTH:-48}
# Width to fit inside. 0 disables the check, which is what a redirect wants.
# Read the size from the tty itself: inside $(...) tput's stdout is a pipe,
# and with stderr silenced it has no terminal to ask and reports 80.
if [[ -t 1 ]]; then
    BOX_COLUMNS=${BOXFETCH_COLUMNS:-$(stty size </dev/tty 2>/dev/null | awk '{print $2}')}
    BOX_COLUMNS=${BOX_COLUMNS:-0}
else
    BOX_COLUMNS=${BOXFETCH_COLUMNS:-0}
fi

if ! command -v fastfetch >/dev/null 2>&1; then
    printf 'boxfetch: fastfetch is not installed\n' >&2
    exit 1
fi

# fastfetch reports the shell as its parent process, which is this script's
# bash; FFTS_IGNORE_PARENT makes it skip one level up to the user's shell.
info=$(FFTS_IGNORE_PARENT=1 fastfetch --config "$BOX_CONFIG" --logo none --pipe false "$@")

# Dim . , ( ) % inside values; fastfetch cannot colour characters within a
# placeholder. Skipped when perl is absent -- the values keep their own colour.
BOX_DIMDOTS=${BOXFETCH_DIMDOTS:-"$(dirname "${BASH_SOURCE[0]}")/dimdots.pl"}
if [[ -f $BOX_DIMDOTS ]] && command -v perl >/dev/null 2>&1; then
    info=$(perl "$BOX_DIMDOTS" <<<"$info")
fi

# LC_ALL=C keeps awk byte-based so the width maths is the same under BSD awk,
# mawk and gawk; stripping UTF-8 continuation bytes turns bytes back into
# columns for the non-ASCII values fastfetch sometimes reports.
LC_ALL=C awk \
    -v c1="$BOX_COLOR_1" -v c2="$BOX_COLOR_2" -v gap="$BOX_GAP" -v offset=1 \
    -v logofile="$BOX_LOGO" -v cols="$BOX_COLUMNS" -v minw="$BOX_MIN_WIDTH" '
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
# The escape sequences in s since its last reset: the colour state s leaves
# behind, appended to the state carried in from before s.
function sgrs(state, s,   sq) {
    while (match(s, /\033\[[0-9;]*m/)) {
        sq = substr(s, RSTART, RLENGTH)
        state = (sq == esc "[m" || sq == esc "[0m") ? "" : state sq
        s = substr(s, RSTART + RLENGTH)
    }
    return state
}
# Colour for a frame cell d cells from the nearest corner: white, bright
# cyan, cyan, bright blue, blue, then dark grey. The grey is 256-colour 238
# (#444444) rather than SGR 90, which themes remap -- mcbros makes it a
# blue-grey that reads as part of the blue.
function fade(d,   step) {
    split("97 96 36 94 34", step, " ")
    return esc "[" (d < 5 ? step[d + 1] : "38;5;238") "m"
}
# A horizontal edge n cells wide between the two corner glyphs.
function hedge(lc, rc, n,   p, d, ch, out) {
    out = ""
    for (p = 0; p < n; p++) {
        d = (p < n - 1 - p) ? p : n - 1 - p
        ch = (p == 0) ? lc : (p == n - 1) ? rc : "-"
        out = out fade(d) ch
    }
    return out reset
}
# Width of the " :  Key  " column, or 0 for a row without a key.
function keywidth(s) {
    gsub(/\033\[[0-9;]*m/, "", s)
    return match(s, /^ :  [A-Za-z]+  /) ? RLENGTH : 0
}
# Split s after n visible columns: the head is returned, the rest left in TAIL.
# Escapes at the cut stay with the head so the key colours close there.
function cut(s, n,   i, seen, m) {
    seen = 0; i = 1
    while (i <= length(s)) {
        if (substr(s, i, 1) == esc && match(substr(s, i), /^\033\[[0-9;]*m/)) {
            i += RLENGTH; continue
        }
        if (seen == n) break
        if (substr(s, i, 1) !~ /[\200-\277]/) seen++
        i++
    }
    TAIL = substr(s, i)
    return substr(s, 1, i - 1)
}
# Word-wrap one info row into wrapped[] at n columns. Continuation rows keep the
# left rail, indent to the value column and resume the colour in effect at
# the break, so a wrapped value reads as one value. A single word longer than
# the value column is the only case that still gets clipped.
function wrap(str, n,   kw, head, val, w, nw, k, word, wl, cur, curw, state, lead) {
    if (vlen(str) <= n) { wrapped[nwrapped++] = str; return }
    kw = keywidth(str)
    if (kw == 0 || kw > n - 12) { wrapped[nwrapped++] = clip(str, n); return }
    head = cut(str, kw); val = TAIL
    lead = e1 " :" reset spaces(kw - 2)
    nw = split(val, w, " ")
    cur = head; curw = kw; state = sgrs("", head)
    for (k = 1; k <= nw; k++) {
        word = w[k]; wl = vlen(word)
        if (curw == kw || curw + 1 + wl <= n) {
            cur = cur (curw == kw ? "" : " ") word
            curw += (curw == kw ? 0 : 1) + wl
        } else {
            wrapped[nwrapped++] = clip(cur, n) reset
            cur = lead state word
            curw = kw + wl
        }
        state = sgrs(state, word)
    }
    wrapped[nwrapped++] = clip(cur, n) reset
}

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

    # Keep the box inside the terminal. Long values wrap inside the box rather
    # than being cut off; when the space beside the logo would leave the box
    # narrower than minw, the logo moves above the box and the box takes the
    # full width. 3 columns cover the gutter and the right rail.
    stacked = 0
    if (cols > 0) {
        avail = cols - (logow + gap) - 3
        if (width > avail && avail < minw) {
            stacked = 1
            avail = cols - 3
        }
        if (width > avail) width = avail
    }

    rail = width + 2
    nrow = 0
    for (i = first; i <= last; i++) {
        nwrapped = 0
        wrap(info[i], width)
        for (k = 0; k < nwrapped; k++) {
            # Swap the " :" rail each row carries for one coloured by the fade.
            cut(wrapped[k], 2)
            inner[nrow] = TAIL spaces(width - vlen(wrapped[k]))
            nrow++
        }
    }

    # The frame glows at its corners: every edge fades from the corner
    # inwards, along the top and bottom and down/up the side rails alike.
    nbox = 0
    box[nbox++] = " " hedge(".", ".", rail)
    for (r = 0; r < nrow; r++) {
        d = r + 1
        if (nrow - r < d) d = nrow - r
        box[nbox++] = fade(d) " :" reset inner[r] "  " fade(d) ":" reset
    }
    box[nbox++] = " " hedge("`", tick, rail)

    if (stacked) {
        for (i = 0; i < nlogo; i++) print logo[i]
        if (nlogo) print ""
        for (j = 0; j < nbox; j++) print box[j]
        exit
    }

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
