#!/usr/bin/perl

print "This is sample.pl\n";
print "ARGV = ", join(" ", @ARGV), "\n";

print "Script path \$0 = $0\n";
print "Exe path \$^X = $^X\n";
print "Perl verison \$] = $]\n";

print "\@INC=\n", join("\n", @INC), "\n";
sleep (1);
