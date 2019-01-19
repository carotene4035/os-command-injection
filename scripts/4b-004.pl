#!/usr/bin/perl
use strict;
use utf8;
use open ':utf8';

my $file='ls /sbin|'; # パラメータでわたされる値. url上からは ls+/sbin|
open (IN, $file) or die $!;
print <IN>;
close IN;
