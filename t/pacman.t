#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 2;

use lib 'lib';

use_ok('Alien::Package::Pacman');
isa_ok(Alien::Package::Pacman->new(), 'Alien::Package');
