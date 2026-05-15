#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 36;
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

# Create a minimal image.tar.gz with test files.
mkdir("$tmpdir/image") unless -d "$tmpdir/image";
mkdir("$tmpdir/image/usr")     unless -d "$tmpdir/image/usr";
mkdir("$tmpdir/image/usr/bin") unless -d "$tmpdir/image/usr/bin";
open my $ifh, '>', "$tmpdir/image/usr/bin/testgentoo" or die;
print $ifh "#!/bin/sh\necho hello\n";
close $ifh;
mkdir("$tmpdir/image/etc") unless -d "$tmpdir/image/etc";
open $ifh, '>', "$tmpdir/image/etc/gentoo.conf" or die;
print $ifh "config=yes\n";
close $ifh;
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

# =========================================================================
# build() round-trip tests
# =========================================================================

# Back up the fixture before build round-trip (build() may overwrite it).
system("cp -a '$test_file' '$test_file.bak'") == 0 or die "backup failed";

{
# Build a package from synthetic object state.
my $builddir = tempdir("alien-build-XXXX", CLEANUP => 1, TMPDIR => 1);
system("mkdir -p '$builddir/usr/bin'") == 0 or die "mkdir usr/bin failed";
open my $fh2, '>', "$builddir/usr/bin/testapp" or die;
print $fh2 "#!/bin/sh\necho built\n";
close $fh2;

my $builder = Alien::Package::Gentoo->new();
$builder->name('testgentoo');
$builder->version('1.0');
$builder->arch('amd64');
$builder->summary('Round-trip test package');
$builder->description('Round-trip test package');
$builder->copyright('GPL-3');
$builder->group('app-misc');
$builder->depends('dev-libs/foo');
$builder->provides('virtual/testgentoo');
$builder->buildtree($builddir);

my $save_cwd2 = Cwd::cwd();
chdir $tmpdir;
my $built_file = $builder->build();
chdir $save_cwd2;

ok(defined $built_file, 'build() returned a filename');
ok(-f "$tmpdir/$built_file", 'built .gpkg.tar exists');
ok(-s "$tmpdir/$built_file" > 0, 'built .gpkg.tar has nonzero size');

# Re-read the built file through a fresh scan.
my $re_read = Alien::Package::Gentoo->new(filename => "$tmpdir/$built_file");
is($re_read->name,      'testgentoo',        'round-trip name');
is($re_read->version,   '1.0',               'round-trip version');
is($re_read->arch,      'amd64',             'round-trip arch');
is($re_read->summary,   'Round-trip test package',   'round-trip summary');
is($re_read->copyright, 'GPL-3',             'round-trip copyright');
is($re_read->group,     'app-misc',          'round-trip group');
}

# Restore the fixture file from backup.
system("cp -a '$test_file.bak' '$test_file'") == 0 or die "restore failed";

# =========================================================================
# Phase 4: test(), unpack(), install() smoke tests
# =========================================================================

{
# test() — container integrity + metadata sanity.
my $result = $pkg->test;
ok(defined $result, 'test() returns success');
}

{
# unpack() — extract image into buildtree.
my $unpackdir = $pkg->unpack;
ok(defined $unpackdir,     'unpack() returns a directory');
ok(-d $unpackdir,          'unpack directory exists');
ok(-f "$unpackdir/usr/bin/testgentoo",  'unpacked /usr/bin/testgentoo');
ok(-f "$unpackdir/etc/gentoo.conf",     'unpacked /etc/gentoo.conf');
}

{
# install() — mock do() to capture the command.
my $captured;
local *Alien::Package::do = sub {
	my $self = shift;
	$captured = join(' ', @_);
	return 1;
};
local *Alien::Package::Gentoo::_inpath = sub { return 1 };
my $install_pkg = Alien::Package::Gentoo->new();
$install_pkg->install($test_file);
like($captured, qr/emerge/,            'install() calls emerge');
like($captured, qr/\Q$test_file\E/,    'install() includes filename');
}
