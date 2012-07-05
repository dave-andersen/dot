#!/usr/bin/perl

use strict;
use warnings;

my @bws = ("clear", "100mbps");#, "100mbps.66ms", "20mbps.33ms", "10mbps.33ms");#, "5mbps.66ms");
my @tests = ("gcp", "wget", "scp");
my $num_runs = 6;

if(!defined($ARGV[0])) {
  die "Usage ./gcp_perf.pl <filename>";
}

my $filename = $ARGV[0];
my $FROM = "fuchsia.aura.cs.cmu.edu";
my $TO = "claret.aura.cs.cmu.edu";
my $ROUTER = "carmine.aura.cs.cmu.edu";
my $input;

my $bw;
my %res = ();
my $test;

foreach $bw (@bws) {
    $res{$bw} = ();
  foreach $test (@tests) {
    $res{$bw}{$test} = [];
  }
}

my $sum;
my $avg;
my $stddev;
my $tmp;
open(RES, "> results.txt");

foreach $bw (@bws) {
  print "Bandwidth - $bw\n";
  system("ssh $ROUTER -l root './dot-netem-scripts/confnet.$bw'");

  $tmp = $bw;
  $tmp =~ s/clear/LineRate/g;
  print RES "Bandwidth - $tmp\n";
  print RES "   \t";
  for(my $i = 1; $i < $num_runs; $i++) {
    print RES "# $i\t";
  }
  print RES "Avg.\n";

  $test = "gcp";

  for(my $i = 0; $i < $num_runs; $i++) {
    system("ssh $FROM -f 'killall -9 gtcd && sleep 0.2 && killall -9 sleep'");
    system("ssh $TO -f 'killall -9 gtcd && sleep 0.2 && killall -9 sleep && rm -f /tmp/foo'");

    system("ssh $FROM -f \"src/dot/gtcd/gtcd || sleep 24d\"");
    system("ssh $TO -f \"src/dot/gtcd/gtcd || sleep 24d\"");

    sleep(2);
    system("ssh $FROM 'cat ./$filename >& /dev/null'");

    open (FD, "ssh $FROM '/usr/bin/time -p src/dot/gcp/gcp ./$filename $TO:/tmp/foo |& grep -i real ' | ")
      or die("Input Failed");
    my @num;
    while (defined($input=<FD>)) {
      chomp($input);
      @num = split(' ', $input);
      $res{$test}{$bw}[$i] = $num[1];
      print("$num[1], \n");
    }
    close(FD);
  }
  print_res($test, $bw);

  # Clean up
  system("ssh $FROM -f 'killall -9 gtcd && sleep 0.2 && killall -9 sleep'");
  system("ssh $TO -f 'killall -9 gtcd && sleep 0.2 && killall -9 sleep && rm -f /tmp/foo'");

  $test = "scp";

  for(my $i = 0; $i < $num_runs; $i++) {
    system("ssh $FROM 'cat ./$filename >& /dev/null'");

    open (FD, "ssh $FROM '/usr/bin/time -p scp ./$filename $TO:/tmp/foo |& grep -i real ' | ")
      or die("Input Failed");
    my @num;
    while (defined($input=<FD>)) {
      chomp($input);
      @num = split(' ', $input);
      $res{$test}{$bw}[$i] = $num[1];
      print("$num[1], \n");
    }
    close(FD);
  }
  print_res($test, $bw);

  $test = "wget";

  for(my $i = 0; $i < $num_runs; $i++) {
    system("ssh $FROM 'cat /home/ntolia/src/jakarta-tomcat-5.0.28/webapps/rubbos/$filename >& /dev/null'");
    system("ssh $TO 'rm -f $filename'");
    # Notice switch of $FROM $TO
    open (FD, "ssh $TO '/usr/bin/time -p wget http://$FROM:8080/rubbos/$filename |& grep -i real ' | ")
      or die("Input Failed");
    my @num;
    while (defined($input=<FD>)) {
      chomp($input);
      @num = split(' ', $input);
      $res{$test}{$bw}[$i] = $num[1];
      print("$num[1], \n");
    }
    close(FD);
  }
  print_res($test, $bw);

  print RES "\n\n";
}

close(RES);

sub print_res {
  my ($t, $b) = @_;

  print RES "$test\t";
  $sum = 0;
  for(my $i = 1; $i < $num_runs; $i++) {
    $sum += $res{$t}{$b}[$i];
    print RES "$res{$t}{$b}[$i]\t";
  }
  $avg = $sum/($num_runs-1);
  print RES "$avg\n";
}
