#!/usr/bin/env perl
# build_snapshot.pl
# Membangun data/snapshot.js dari file titik panas harian BMKG CEWS.
#
# Sumber : https://cews.bmkg.go.id/tempatirk/HOTSPOT/YYYYMMDD/hotspot_YYYYMMDD.txt
# Pakai  : perl tools/build_snapshot.pl /tmp/hs_*.txt
use strict;
use warnings;
use JSON::PP;

my @files = @ARGV;
die "Tidak ada file input\n" unless @files;

my @days;    # urut tanggal menaik
my %latest;  # dedup titik hari terakhir
my ($latest_date, $latest_raw, $latest_dedup);

for my $f (@files) {
    open my $fh, '<:encoding(UTF-8)', $f or die "Gagal buka $f: $!";
    my $header = <$fh>;
    my (%seen, $raw, $file_date);
    while (my $line = <$fh>) {
        chomp $line;
        next unless length $line;
        my @c = split /\t/, $line, -1;
        next if @c < 10;
        my ($lon, $lat, $conf, $region, $prov, $kab, $kec, $sat, $date, $time) = @c[0..9];
        next unless $lon =~ /^-?\d+(\.\d+)?$/ && $lat =~ /^-?\d+(\.\d+)?$/;
        $file_date = $date if defined $date && $date ne ''
            && (!defined $file_date || $date gt $file_date);
        $raw++;
        my $key = sprintf('%.2f,%.2f', $lon, $lat);
        my $keep = {
            lon => $lon + 0, lat => $lat + 0,
            conf => ($conf =~ /^\d+$/ ? $conf + 0 : 0),
            region => $region, prov => $prov, kab => $kab, kec => $kec,
            sat => $sat, date => $date, time => $time,
        };
        if (!$seen{$key}
            || $keep->{conf} > $seen{$key}{conf}
            || ($keep->{conf} == $seen{$key}{conf} && $keep->{time} gt $seen{$key}{time})) {
            $seen{$key} = $keep;
        }
    }
    close $fh;

    my $dedup = scalar keys %seen;
    my $date_lbl = $file_date // '0000-00-00';
    push @days, { date => $date_lbl, raw => $raw, dedup => $dedup };
    print sprintf("%-60s raw=%-6d dedup=%d\n", $f, $raw, $dedup);

    if (!defined $latest_date || $date_lbl gt $latest_date) {
        $latest_date = $date_lbl;
        $latest_raw  = $raw;
        $latest_dedup = $dedup;
        %latest = %seen;
    }
}
@days = sort { $a->{date} cmp $b->{date} } @days;

# ---- kamus & titik terkompresi ----
my (%prov_i, %kab_i, %kec_i, %sat_i);
my (@prov, @kab, @kec, @sat);
my @pts;
my %prov_stat;

for my $p (sort { $latest{$b}{conf} <=> $latest{$a}{conf} || $a cmp $b } keys %latest) {
    my $h = $latest{$p};
    $prov_i{$h->{prov}} //= do { push @prov, $h->{prov}; $#prov };
    $kab_i{$h->{kab}}   //= do { push @kab,  $h->{kab};   $#kab };
    $kec_i{$h->{kec}}   //= do { push @kec,  $h->{kec};   $#kec };
    $sat_i{$h->{sat}}   //= do { push @sat,  $h->{sat};   $#sat };

    my $s = $prov_stat{$h->{prov}} ||= { n => 0, hi => 0, mid => 0, low => 0 };
    $s->{n}++;
    if    ($h->{conf} >= 9) { $s->{hi}++ }
    elsif ($h->{conf} >= 8) { $s->{mid}++ }
    else                    { $s->{low}++ }

    push @pts, [
        0 + sprintf('%.4f', $h->{lon}),
        0 + sprintf('%.4f', $h->{lat}),
        $h->{conf},
        $prov_i{$h->{prov}},
        $kab_i{$h->{kab}},
        $kec_i{$h->{kec}},
        $sat_i{$h->{sat}},
        $h->{time},
    ];
}

my @prov_counts = map { { name => $_, %{ $prov_stat{$_} } } }
    sort { $prov_stat{$b}{n} <=> $prov_stat{$a}{n} } keys %prov_stat;

my $snapshot = {
    source      => 'BMKG CEWS (satelit VIIRS/MODIS: NOAA-20, SNPP, Terra, Aqua)',
    source_url  => 'https://cews.bmkg.go.id/tempatirk/HOTSPOT/',
    date        => $latest_date,
    generated   => sprintf('%s', scalar gmtime() . ' UTC'),
    raw_total   => $latest_raw,
    dedup_total => $latest_dedup,
    trend       => [ map { { date => $_->{date}, n => $_->{dedup}, raw => $_->{raw} } } @days ],
    prov_counts => \@prov_counts,
    prov        => \@prov,
    kab         => \@kab,
    kec         => \@kec,
    sat         => \@sat,
    pts         => \@pts,
};

mkdir 'data' unless -d 'data';
open my $out, '>:encoding(UTF-8)', 'data/snapshot.js' or die $!;
print {$out} "window.SNAPSHOT = ", JSON::PP->new->canonical(0)->encode($snapshot), ";\n";
close $out;

my $size = -s 'data/snapshot.js';
printf "\nTulis data/snapshot.js (%d byte): tanggal=%s titik=%d provinsi=%d kabupaten=%d\n",
    $size, $latest_date, scalar(@pts), scalar(@prov), scalar(@kab);
