#!/usr/bin/env python3
"""
Scale fastfetch ASCII art proportionally while preserving colors.

The art is a density map drawn with graded glyphs (space < . < : < - < = < + < *),
so downsampling averages the ink over each source block and picks the glyph
closest to that average. Nearest-neighbour sampling drops whole strokes at 50%.

The caption box is not art -- it is regenerated at the scaled width.
"""

import re
import sys

# Glyph ink levels, lightest to darkest. Order matters for tie-breaking.
INK = [
    (' ', 0.00),
    ('.', 0.15),
    (':', 0.30),
    ('-', 0.40),
    ('=', 0.62),
    ('+', 0.80),
    ('*', 1.00),
]
INK_OF = dict(INK)

# How far each output glyph leans from the block mean toward its darkest cell.
MAX_BIAS = 0.35

TITLE_LEFT = 'Signal Mine'
TITLE_RIGHT = 'Sapere Aude'
TAGLINE_LEFT = '"Doing the needful'
TAGLINE_RIGHT = ', since 2022"'


def parse_line(line):
    """Split a line into (color, char) cells, dropping the $N color markers."""
    cells = []
    color = None
    for token in re.split(r'(\$\d)', line):
        if re.fullmatch(r'\$\d', token):
            color = token
        else:
            cells.extend((color, ch) for ch in token)
    return cells


def render_line(cells):
    """Rebuild a line from cells, emitting a colour marker only when it changes."""
    out = []
    last = None
    for color, ch in cells:
        if ch != ' ' and color and color != last:
            out.append(color)
            last = color
        out.append(ch)
    return ''.join(out).rstrip()


def is_caption(line):
    """Caption lines carry words; art lines are pure punctuation."""
    return bool(re.search(r'[A-Za-z]', line))


def glyph_for(ink):
    return min(INK, key=lambda pair: abs(pair[1] - ink))[0]


def downsample(grid, scale):
    """Box-filter the cell grid to `scale` of its size in both dimensions."""
    rows = len(grid)
    cols = max(len(r) for r in grid)
    out_rows = max(1, round(rows * scale))
    out_cols = max(1, round(cols * scale))
    result = []

    carried = None
    for r in range(out_rows):
        r0, r1 = int(r * rows / out_rows), max(int((r + 1) * rows / out_rows), int(r * rows / out_rows) + 1)
        line = []
        for c in range(out_cols):
            c0, c1 = int(c * cols / out_cols), max(int((c + 1) * cols / out_cols), int(c * cols / out_cols) + 1)
            total = 0.0
            count = 0
            best_ink = 0.0
            votes = {}
            for sr in range(r0, min(r1, rows)):
                row = grid[sr]
                for sc in range(c0, min(c1, cols)):
                    color, ch = row[sc] if sc < len(row) else (None, ' ')
                    ink = INK_OF.get(ch, 0.5)
                    total += ink
                    count += 1
                    best_ink = max(best_ink, ink)
                    if color and ink:
                        votes[color] = votes.get(color, 0.0) + ink
            # Weight the colour vote by ink so a block straddling a colour
            # boundary takes the colour of the stroke, not of one stray cell.
            best_color = max(votes, key=votes.get) if votes else carried
            carried = best_color or carried
            mean = total / count if count else 0.0
            # Pure mean erases one-glyph-wide strokes at 50%; bias toward the
            # darkest cell in the block so outlines survive the downsample.
            avg = mean * (1 - MAX_BIAS) + best_ink * MAX_BIAS
            line.append((best_color, glyph_for(avg)))
        result.append(line)
    return result


def build_caption(width):
    """Regenerate the title box and tagline at the given width."""
    title = f'{TITLE_LEFT} | {TITLE_RIGHT}'
    inner = max(width - 2, len(title) + 2)
    pad = inner - len(title)
    left_pad = pad // 2
    right_pad = pad - left_pad
    half = inner // 2

    return [
        f'$1  .{"-" * half}$2{"-" * (inner - half)}.',
        f'$1  :{" " * left_pad}$1{TITLE_LEFT} $2| $1{TITLE_RIGHT}$2{" " * right_pad}:',
        f'$1  `{"-" * half}$2{"-" * (inner - half)}\'',
        f'$1{" " * (2 + (inner + 2 - len(TAGLINE_LEFT + TAGLINE_RIGHT)) // 2)}'
        f'{TAGLINE_LEFT}$2{TAGLINE_RIGHT}',
    ]


def scale_ascii_art(input_file, output_file, scale):
    with open(input_file) as fh:
        lines = [line.rstrip('\n') for line in fh]

    caption_start = next((i for i, l in enumerate(lines) if is_caption(l)), len(lines))
    art_lines = lines[:caption_start]
    while art_lines and not art_lines[-1].strip():
        art_lines.pop()

    grid = [parse_line(l) for l in art_lines]
    scaled = downsample(grid, scale)
    art_out = [render_line(row) for row in scaled]
    width = max((len(row) for row in scaled), default=0)

    with open(output_file, 'w') as fh:
        for line in art_out:
            fh.write(line + '\n')
        fh.write('\n')
        for line in build_caption(width):
            fh.write(line + '\n')

    print(f'{input_file} -> {output_file}: '
          f'{len(art_lines)}x{max(len(r) for r in grid)} art -> {len(art_out)}x{width}')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: scale_ascii.py <input_file> [scale_factor] [output_file]')
        print('Example: scale_ascii.py signalmine.txt 0.5 signalmine_50.txt')
        sys.exit(1)

    src = sys.argv[1]
    factor = float(sys.argv[2]) if len(sys.argv) > 2 else 0.6
    dst = sys.argv[3] if len(sys.argv) > 3 else src.replace('.txt', f'_{int(factor * 100)}.txt')
    scale_ascii_art(src, dst, factor)
