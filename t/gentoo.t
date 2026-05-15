#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 20;
use File::Temp qw(tempdir);
use Cwd;

use lib 'lib';

use_ok('Alien::Package::Gentoo');
isa_ok(Alien::Package::Gentoo->new(), 'Alien::Package');

# Create a synthetic .gpkg.tar fixture (GLEP 78 modern format).
my $tmpdir = tempdir("alien-test-XXXX", CLEANUP => 1, TMPDIR => 1);
my $metadir = "$tmpdir/metadata";
mkdir($metadir) or die "mkdir $metadir: $!";

# Write metadata files.
open my $fh, '>', "$metadir/PF" or die;        print $fh "testgentoo-1.0\n";         close $fh;
open $fh, '>', "$metadir/CATEGORY" or die;     print $fh "app-misc\n";               close $fh;
open $fh, '>', "$metadir/DESCRIPTION" or die;  print $fh "A test gentoo package\n";  close $fh;
open $fh, '>', "$metadir/HOMEPAGE" or die;     print $fh "http://example.com\n";     close $fh;
open $fh, '>', "$metadir/LICENSE" or die;      print $fh "GPL-3\n";                  close $fh;
open $fh, '>', "$metadir/CHOST" or die;        print $fh "x86_64-pc-linux-gnu\n";    close $fh;
open $fh, '>', "$metadir/DEPEND" or die;       print $fh "dev-libs/foo sys-libs/bar\n"; close $fh;
open $fh, '>', "$metadir/RDEPEND" or die;      print $fh "dev-libs/foo\n";           close $fh;
open $fh, '>', "$metadir/PROVIDE" or die;      print $fh "virtual/testgentoo\n";     close $fh;
open $fh, '>', "$metadir/CONTENTS" or die;
print $fh "obj /usr/bin/testgentoo abcd1234\n";
print $fh "dir /etc/testgentoo\n";
print $fh "obj /etc/testgentoo/config 5678efab\n";
close $fh;

# Create metadata.tar.gz.
my $cwd = getcwd();
chdir $tmpdir;
my $ret = system("tar -czf metadata.tar.gz -C '$metadir' . 2>/dev/null");
ok($ret == 0, "metadata.tar.gz created");

# Create a minimal image.tar.gz.
mkdir("$tmpdir/image") unless -d "$tmpdir/image";
$ret = system("tar -czf image.tar.gz -C '$tmpdir/image' . 2>/dev/null");
ok($ret == 0, "image.tar.gz created");

# Build the outer .gpkg.tar.
my $test_file = "$tmpdir/testgentoo-1.0.gpkg.tar";
$ret = system("tar -cf '$test_file' metadata.tar.gz image.tar.gz 2>/dev/null");
chdir $cwd;
ok($ret == 0 && -f $test_file, "Test .gpkg.tar fixture created");

# Instantiate and read.
my $pkg = Alien::Package::Gentoo->new(filename => $test_file);
isa_ok($pkg, 'Alien::Package::Gentoo');

is($pkg->name,              'testgentoo',                     'name');
is($pkg->version,           '1.0',                            'version');
is($pkg->release,           1,                                'release');
is($pkg->arch,              'amd64',                          'arch (from CHOST x86_64)');
is($pkg->summary,           'A test gentoo package',          'summary');
is($pkg->description,       'A test gentoo package',          'description');
is($pkg->copyright,         'GPL-3',                          'copyright');
is($pkg->group,             'app-misc',                       'group');
is($pkg->depends,           'dev-libs/foo, sys-libs/bar, dev-libs/foo',
                                                              'depends (DEPEND + RDEPEND)');
is($pkg->provides,          'virtual/testgentoo',             'provides');
is($pkg->origformat,        'gentoo',                         'origformat');

my $files = $pkg->filelist;
is(scalar @{$files}, 2,  'file count (2 obj entries in CONTENTS)');
ok((grep { m|/usr/bin/testgentoo$| } @{$files}),
   'filelist includes /usr/bin/testgentoo');
ok((grep { m|/etc/testgentoo/config$| } @{$files}),
   'filelist includes /etc/testgentoo/config');
