#!/usr/bin/perl
# Dim . , ( ) % in fastfetch's value column to dark grey.
# fastfetch formats can colour a whole placeholder but not characters inside
# one (26.5, 192.168.6.189, 75%), so this recolours them after rendering. Only text
# after a " :  <Key>" label is touched; the logo's dots are left alone.
# boxfetch.sh pipes its output through this. For plain fastfetch:
#   fastfetch --pipe false | perl ~/.local/share/myprompts/fastfetch/dimdots.pl
use strict;
use warnings;

# A label is " :  " then its letters, each run of letters led by a colour code
# (the keys fade white -> cyan -> grey letter by letter).
my $key = qr/ :  (?:\e\[[0-9;]*m)*(?:\e\[[0-9;]*m[A-Za-z]+)+/;

while (my $line = <STDIN>) {
    if ($line =~ /^(.*?$key)(.*)$/s) {
        my ($head, $val) = ($1, $2);
        my $cur = '0';
        my $out = '';
        for my $tok (split /(\e\[[0-9;]*m)/, $val) {
            if ($tok =~ /^\e\[([0-9;]*)m$/) {
                $cur = $1;
            } else {
                $tok =~ s/([.,()%])/\e[90m$1\e[${cur}m/g;
            }
            $out .= $tok;
        }
        $line = $head . $out;
    }
    print $line;
}
