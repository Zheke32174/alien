#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Pacman - an object that represents a pacman package (.pkg.tar.zst)

=cut

package Alien::Package::Pacman;
use strict;
use base qw(Alien::Package);

=head1 DESCRIPTION

This is an object class that represents a pacman package (.pkg.tar.zst / .pkg.tar.xz / .pkg.tar.gz).
It is derived from Alien::Package.

Pacman binary packages are tar archives (compressed with zstd, xz, or gzip) containing:

  - .PKGINFO     — metadata in key=value format
  - .INSTALL     — optional install/upgrade/remove hook script
  - .MTREE       — optional mtree-formatted file checksums
  - /            — package files laid out at the root of the tar

=cut

=head1 METHODS

=over 4

=item checkfile

Detect pacman package files by their extension.

=cut

sub checkfile {
	my $this=shift;
	my $file=shift;

	return $file =~ m/.*\.pkg\.tar\.(zst|xz|gz|bz2)$/;
}

=item install

Install a pacman package with pacman -U. Pass in the filename of the
package to install.

=cut

sub install {
	my $this=shift;
	my $file=shift;

	die "TODO: Alien::Package::Pacman::install not yet implemented; see nlspec/alien-rewrite.md";
}

=item test

Test a pacman package. Pass in the filename of the package to test.

=cut

sub test {
	my $this=shift;
	my $file=shift;

	die "TODO: Alien::Package::Pacman::test not yet implemented; see nlspec/alien-rewrite.md";
}

=item scan

Implement the scan method to read a pacman package file. Parses .PKGINFO
from inside the tar and populates the alien internal field representation.

=cut

sub scan {
	my $this=shift;
	$this->SUPER::scan(@_);

	die "TODO: Alien::Package::Pacman::scan not yet implemented; see nlspec/alien-rewrite.md";
}

=item unpack

Unpack a pacman package into a temporary directory.

=cut

sub unpack {
	my $this=shift;
	$this->SUPER::unpack(@_);

	die "TODO: Alien::Package::Pacman::unpack not yet implemented; see nlspec/alien-rewrite.md";
}

=item prep

Prepare for building by generating any needed metadata files inside the
unpacked tree.

=cut

sub prep {
	my $this=shift;

	die "TODO: Alien::Package::Pacman::prep not yet implemented; see nlspec/alien-rewrite.md";
}

=item build

Build a pacman package from the prepped tree.

=cut

sub build {
	my $this=shift;

	die "TODO: Alien::Package::Pacman::build not yet implemented; see nlspec/alien-rewrite.md";
}

=item cleantree

Clean the unpacked tree of any effects the prep and build methods may have
had on it.

=cut

sub cleantree {
	my $this=shift;

	die "TODO: Alien::Package::Pacman::cleantree not yet implemented; see nlspec/alien-rewrite.md";
}

=back

=head1 NOTES

=head2 Format reference

Pacman binary packages use the following conventions:

  - File extension: .pkg.tar.zst (most common), .pkg.tar.xz, .pkg.tar.gz
  - Container: tar archive compressed with zstd (default), xz, gzip, or bzip2
  - Metadata: .PKGINFO file at the root of the tar (key=value format)
  - Hooks: .INSTALL script at the root (optional, contains post_install/pre_remove etc. functions)
  - Checksums: .MTREE file at the root (optional, mtree format)
  - No separate control archive — metadata lives directly in the tar

=head2 Key .PKGINFO fields

    pkgname = <name>
    pkgver = <epoch>:<pkgrel>-<pkgver>
    pkgdesc = <description>
    url = <url>
    builddate = <unix_timestamp>
    packager = <name> <email>
    size = <installed_size_bytes>
    arch = <architecture>
    license = <license>
    depend = <dependency>
    optdepend = <optional_dependency>:<description>
    conflict = <conflict>
    provides = <provides>
    backup = <config_file_path>

=head2 Hooks (.INSTALL)

The .INSTALL file is a shell script that may define any of:

    post_install()
    pre_upgrade()
    post_upgrade()
    pre_remove()
    post_remove()

Alien transcribes these as-is (never executes them).

=head1 AUTHOR

Underhall contributors <https://github.com/Zheke32174/underhall>

=cut

1;
