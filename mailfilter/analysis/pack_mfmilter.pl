#!/usr/bin/perl

my $mfdir = "/var/spool/mfmilter";
my $od = "$mfdir/output";
my $divider = "--==--\n";

opendir(DIR, $od) || die "Can't opendir $od: $!\n";
@mffiles = grep { /[0-9]/ && -f "$od/$_" } readdir(DIR);
print "There are " . $#mffiles . " files\n";

sub bynum {
  $a <=> $b;
}
@mfs = sort bynum @mffiles;

my $firstfile = $mfs[0];
my $lastfile = $mfs[-1];

print "Now there are $#mfs ..  $firstfile - $lastfile\n";
my $archdir = "$mfdir/$firstfile-$lastfile";
mkdir($archdir);
open(OUT, ">$mfdir/archived/$firstfile-$lastfile");

foreach my $file (@mfs) {
  open(IN, "$od/$file");
  print OUT "MAIL $file\n";
  while (<IN>) { print OUT; }
  close(IN);
  print OUT $divider;
  rename("$od/$file", "$archdir/$file");
}

system("cd $mfdir && tar -czf $mfdir/tarballs/$firstfile-$lastfile.tar.gz $firstfile-$lastfile && rm -rf $firstfile-$lastfile");


close(OUT);
