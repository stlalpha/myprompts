#!/usr/bin/env python3
"""
Scale ASCII art proportionally while preserving colors and visual appearance.
Keeps text boxes intact.
"""

import re
import sys
from typing import List, Tuple

def strip_ansi_codes(text: str) -> str:
    """Remove ANSI color codes from text."""
    return re.sub(r'\$\d', '', text)

def extract_colors_and_chars(line: str) -> List[Tuple[str, str]]:
    """Extract characters with their preceding color codes."""
    result = []
    current_color = None

    tokens = re.split(r'(\$\d)', line)

    for token in tokens:
        if re.match(r'\$\d', token):
            current_color = token
        elif token:
            for char in token:
                result.append((current_color, char))

    return result

def scale_line_horizontal(line: str, scale: float) -> str:
    """Scale a line horizontally while preserving colors."""
    chars_with_colors = extract_colors_and_chars(line)

    if not chars_with_colors:
        return line

    # Sample characters at intervals
    scaled = []
    last_color = None
    char_idx = 0.0
    step = 1.0 / scale

    while int(char_idx) < len(chars_with_colors):
        color, char = chars_with_colors[int(char_idx)]

        # Only add color code if it changed
        if color and color != last_color:
            scaled.append(color)
            last_color = color

        scaled.append(char)
        char_idx += step

    return ''.join(scaled)

def is_text_box_line(line: str) -> bool:
    """Check if a line is part of the text box (contains words)."""
    stripped = strip_ansi_codes(line)
    # Check for text box indicators
    return ('Signal Mine' in stripped or
            'Sapere' in stripped or
            'Doing the needful' in stripped or
            (stripped.count('-') > 20 and ('.' in stripped or '\'' in stripped or ':' in stripped)))

def scale_ascii_art(input_file: str, output_file: str, scale: float = 0.6, keep_text_box: bool = True):
    """
    Scale ASCII art by the given factor.

    Args:
        input_file: Path to input ASCII art file
        output_file: Path to output file
        scale: Scaling factor (0.5 = half size, 0.6 = 60% size, etc.)
        keep_text_box: If True, don't scale text box lines
    """
    with open(input_file, 'r') as f:
        lines = f.readlines()

    lines = [line.rstrip('\n') for line in lines]

    # Find where text box starts
    text_box_start = None
    if keep_text_box:
        for i, line in enumerate(lines):
            if is_text_box_line(line):
                text_box_start = i
                break

    # Separate ASCII art from text box
    if text_box_start is not None:
        art_lines = lines[:text_box_start]
        text_box_lines = lines[text_box_start:]
    else:
        art_lines = lines
        text_box_lines = []

    # Scale vertically - take every Nth line from art portion
    v_step = 1.0 / scale
    scaled_art = []

    line_idx = 0.0
    while int(line_idx) < len(art_lines):
        line = art_lines[int(line_idx)]
        # Scale horizontally
        scaled_line = scale_line_horizontal(line, scale)
        scaled_art.append(scaled_line)
        line_idx += v_step

    # Combine scaled art with original text box
    result_lines = scaled_art + text_box_lines

    # Write output
    with open(output_file, 'w') as f:
        for line in result_lines:
            f.write(line + '\n')

    art_width = max(len(strip_ansi_codes(l)) for l in art_lines) if art_lines else 0
    scaled_width = max(len(strip_ansi_codes(l)) for l in scaled_art) if scaled_art else 0

    print(f"ASCII art scaled from {len(art_lines)} lines to {len(scaled_art)} lines")
    print(f"Original art width: ~{art_width} chars")
    print(f"Scaled art width: ~{scaled_width} chars")
    if text_box_lines:
        print(f"Text box preserved: {len(text_box_lines)} lines")
    print(f"Output written to: {output_file}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python scale_ascii.py <input_file> [scale_factor] [output_file]")
        print("Example: python scale_ascii.py signalmine.txt 0.6 signalmine_small.txt")
        print("Scale factor: 0.5 = half size, 0.6 = 60% size, etc.")
        sys.exit(1)

    input_file = sys.argv[1]
    scale = float(sys.argv[2]) if len(sys.argv) > 2 else 0.6
    output_file = sys.argv[3] if len(sys.argv) > 3 else input_file.replace('.txt', f'_scaled_{int(scale*100)}.txt')

    scale_ascii_art(input_file, output_file, scale)
