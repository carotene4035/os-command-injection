#!/usr/bin/perl
open FL, '/bin/pwd|' or die $!;
print <FL>;
close FL;
