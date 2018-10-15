#!/usr/bin/env perl

use strict;
use warnings;
use English  qw( -no_match_vars );
use File::Basename qw[fileparse];
use Text::CSV;
use File::Spec;
use File::Copy qw[copy];

my $csv = Text::CSV->new({  binary => 1, escape_char => "\\", allow_loose_quotes => 1 } );
my $csv_out = Text::CSV->new({  binary => 1, escape_char => undef, quote_char => undef, allow_loose_quotes => 1 } );

# These describe how to parse a chiptune's header
# for example, GBS's header structure is:
# http://ocremix.org/info/GBS_Format_Specification
# Offset Size Description
#====== ==== ==========================
#  00     3  Identifier string ("GBS")
#  03     1  Version (1)
#  04     1  Number of songs (1-255)
#  05     1  First song (usually 1)
#  06     2  Load address ($400-$7fff)
#  08     2  Init address ($400-$7fff)
#  0a     2  Play address ($400-$7fff)
#  0c     2  Stack pointer
#  0e     1  Timer modulo  (see TIMING)
#  0f     1  Timer control (see TIMING)
#  10    32  Title string
#  30    32  Author string
#  50    32  Copyright string
#
# "string" field is a perl pack/unpack format string:
# https://perldoc.perl.org/functions/pack.html
# So again, with GBS as the example, I've got:
# single byte fields (ie, version 1, number of songs) => C (unsigned char)
# double byte fields (ie, load address, init address) => v (unsigned short)
# for many-byte fields (string data, like title)      => A (ASCII String, space-padded)
# The space-padded ASCII variant is better in case the field takes up the entire
# 32 bytes - there's no null padding in that case.
#
# the "title", "artist", and "copyright" attributes refer to the field
# number to use for title/artist/copyright.

my $platforms = {
  '.gbs' => {
    'length' => 112,
    'string' => 'a3 C1 C1 C1 v1 v1 v1 v1 C1 C1 A32 A32 A32',
    'title' => 10,
    'artist' => 11,
    'copyright' => 12,
  },
  '.sgc' => {
    'length' => 160,
    'string' => 'a4 C1 C1 C1 C1 v1 v1 v1 v1 v1 a14 a4 C1 C1 C1 C1 C1 a23 A32 A32 A32',
    'title' => 18,
    'artist' => 19,
    'copyright' => 20,
  },
  '.kss' => {
    'length' => 16,
    'string' => 'a4 v1 v1 v1 v1 c1 c1 c1 c1',
  }, # kss does not have any title/artist/etc metadata
};

sub time_to_ms {
    my $string = shift;

    if ( length($string) == 0 ) {
        return;
    }

    my $time = 0;
    my @time_parts = split(':',$string);
    foreach my $part (@time_parts) {
        $part =~ s/^0//;
        if(length($part) == 0) {
            $part = 0;
        }
        $time = ($time * 60) + ($part * 1000);
    }

    return $time;
}

sub ms_to_time {
    my $ms = shift;

    if(not defined($ms)) {
        return '';
    }

    if(length($ms) == 0) {
        return $ms;
    }

    my $seconds = int($ms / 1000);
    my $minutes = int($seconds / 60);
    $seconds = int($seconds - ($minutes * 60));

    return sprintf("%d:%02d",$minutes,$seconds);
}

sub process_m3u {
  my @m3u = @_;
  my @ret;
  foreach my $file (@m3u) {
    my $data;
    open(my $fh, '<', $file);
    binmode($fh);
    read($fh, $data, -s $file);
    close($fh);


    if(length($data) > 0) {
      if($csv->parse($data)) {
        my @fields = $csv->fields();
        $fields[1] = sprintf("\$%02X",$fields[1]);
        $fields[3] = ms_to_time(time_to_ms($fields[3]));
        $fields[4] = ms_to_time(time_to_ms($fields[4]));
        $fields[5] = ms_to_time(time_to_ms($fields[5]));
        push(@ret,\@fields);
      }
    }
  }

  return @ret;
}

sub findlcs {
    my $substr = $_[0];
    my $len = length $_[0];
    my $off = 0;

    while ($substr) {
        my @matches = grep /\Q$substr/, @_;

        last if @matches == @_;

        $off++;
        $len-- and $off=0 if $off+$len > length $_[0];

        $substr = substr $_[0], $off, $len;
    }

    return $substr;
}

sub grab_headers {
  my $platform = shift;
  my $filename = shift;

  my $header;

  open(my $fh, '<', $filename) or croak $OS_ERROR;
  binmode($fh);
  read($fh,$header,$platforms->{$platform}->{'length'});
  close($fh);

  my @fields = unpack($platforms->{$platform}->{'string'},$header);

  my $meta = {};

  foreach my $field (qw[title artist copyright]) {
      if(exists $platforms->{$platform}->{$field}) {
          $meta->{$field} = $fields[$platforms->{$platform}->{$field}];
      }
  }

  return $meta;

}

sub usage {
  print("Usage: fixup-m3u.pl /path/to/folder\n");
  exit(0);
}

sub trim {
  my $string = shift;
  $string =~ s/^\s+//;
  $string =~ s/\s+$//;
  return $string;
}

sub split_files {
  my @files = @_;

  my @m3u = sort grep { m/\.m3u$/ } @files;
  my @chiptunes = grep { ! m/\.m3u$/ } @files;

  if($#chiptunes > 1) {
    print("Error - too many non-m3u files\n");
    exit(1);
  }

  return $chiptunes[0], @m3u;

}


sub process_folder {
  my $folder = shift;

  chdir $folder;
  opendir(my $dirh, '.');
  my @files = grep { $_ !~ /^\./ } readdir($dirh);
  closedir($dirh);

  my ($chiptune, @m3u) = split_files(@files);
  my ($name,$path,$ext) = fileparse($chiptune,qr"\..[^.]*$");

  if(not exists($platforms->{$ext})) {
      print "Sorry, I'm not sure how to parse a $ext file\n";
      exit(1);
  }

  my $meta = grab_headers($ext,$chiptune);

  foreach my $field (qw[title artist]) {
    if(exists($meta->{$field})) {
      print "Detected game $field: " . $meta->{$field}."\n";
      print "Hit return to use this $field, or type a new one: ";
    } else {
      print "Unable to detect $field\n";
      print "Please enter one, or hit return to leave empty: ";
    }
    my $resp = <STDIN>;
    $resp = trim($resp);
    if(length($resp) > 0) {
      print "Setting $field to: $resp\n";
      $meta->{$field} = $resp;
    }
  }

  @m3u = process_m3u(@m3u);

  my @titles;
  foreach my $m (@m3u) {
    push(@titles,$m->[2]);
  }

  my $lcs = quotemeta findlcs(@titles);

  foreach my $i (0..$#titles) {
    $titles[$i] =~ s/$lcs//;
    $m3u[$i]->[2] = $titles[$i];
  }

  my $m3u_data = '';
  foreach my $field (qw[title artist]) {
    if(exists($meta->{$field})) {
      if($field eq 'title') {
          $m3u_data .= "# " . $meta->{$field} . "\n";
      } elsif($field eq 'artist') {
          $m3u_data .= "# Composer: " . $meta->{$field} . "\n";
      }
    }
  }

  foreach my $m (@m3u) {
    my @fields = map { local $_ = $_; $_ =~ s/,/\\,/g; $_ } @$m;
    $csv_out->combine(@fields);
    $m3u_data .= $csv_out->string()."\n";
  }

  my $m3u_dest = "${name}.m3u";

  print "Writing out playlist file $m3u_dest\n";
  open(my $m3u_fh, '>', $m3u_dest);
  print $m3u_fh $m3u_data;
  close($m3u_fh);

}

if(@ARGV < 1) {
  usage();
}

process_folder($ARGV[0]);

