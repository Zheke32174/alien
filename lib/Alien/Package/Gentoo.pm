#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Gentoo - an object that represents a Gentoo binary package (.tbz2 / .gpkg.tar)

=cut

package Alien::Package::Gentoo;
use strict;
use base qw(Alien::Package);

=head1 DESCRIPTION

This is an object class that represents a Gentoo binary package (.tbz2 or
.gpkg.tar). It is derived from Alien::Package.

Gentoo binary packages come in two formats:

  - Legacy .tbz2: a bzip2-compressed tar with an appended XPAK metadata trailer.
  - Modern .gpkg.tar: a GLEP 78 sectioned tar (uncompressed), with named sections
    for metadata, image, and signatures.

=cut

=head1 METHODS

=over 4

=item checkfile

Detect Gentoo binary package files by their extension.

=cut

sub checkfile {
	my $this=shift;
	my $file=shift;

	return $file =~ m/.*\.(tbz2|gpkg\.tar)$/;
}

=item install

Install a Gentoo binary package with emerge. Pass in the filename.

=cut

sub install {
	my $this=shift;
	my $file=shift;

	die "TODO: Alien::Package::Gentoo::install not yet implemented; see nlspec/alien-rewrite.md";
}

=item test

Test a Gentoo binary package. Pass in the filename.

=cut

sub test {
	my $this=shift;
	my $file=shift;

	die "TODO: Alien::Package::Gentoo::test not yet implemented; see nlspec/alien-rewrite.md";
}

=item scan

Implement the scan method to read a Gentoo binary package. Handles both
.tbz2 (XPAK trailer) and .gpkg.tar (GLEP 78 sectioned tar) formats.

=cut

sub scan {
	my $this=shift;
	$this->SUPER::scan(@_);

	die "TODO: Alien::Package::Gentoo::scan not yet implemented; see nlspec/alien-rewrite.md";
}

=item unpack

Unpack a Gentoo binary package into a temporary directory.

=cut

sub unpack {
	my $this=shift;
	$this->SUPER::unpack(@_);

	die "TODO: Alien::Package::Gentoo::unpack not yet implemented; see nlspec/alien-rewrite.md";
}

=item prep

Prepare for building by generating any needed metadata files inside the
unpacked tree.

=cut

sub prep {
	my $this=shift;

	die "TODO: Alien::Package::Gentoo::prep not yet implemented; see nlspec/alien-rewrite.md";
}

=item build

Build a Gentoo binary package from the prepped tree.

Emits .gpkg.tar (GLEP 78 modern format) by default; .tbz2 legacy output
may be supported in a later phase.

=cut

sub build {
	my $this=shift;

	die "TODO: Alien::Package::Gentoo::build not yet implemented; see nlspec/alien-rewrite.md";
}

=item cleantree

Clean the unpacked tree of any effects the prep and build methods may have
had on it.

=cut

sub cleantree {
	my $this=shift;

	die "TODO: Alien::Package::Gentoo::cleantree not yet implemented; see nlspec/alien-rewrite.md";
}

=back

=head1 NOTES

=head2 Format reference

=head3 Legacy .tbz2 (XPAK)

  - File extension: .tbz2
  - Container: bzip2-compressed tar
  - Metadata: XPAK trailer appended after the tar stream
  - XPAK offset: stored in the last 8 bytes of the file (big-endian integer)
  - XPAK format: tar-like structure with CONTROL and CONTENTS members
  - CONTROL file: key=value records (DESCRIPTION, HOMEPAGE, SLOT, KEYWORDS,
    IUSE, DEPEND, RDEPEND, PDEPEND, etc.)
  - CONTENTS file: file listing with type, path, permissions, owner, group,
    checksum, and modification time per entry

=head3 Modern .gpkg.tar (GLEP 78)

  - File extension: .gpkg.tar
  - Container: uncompressed tar with named section members
  - Sections:
    - metadata.tar.<comp> — compressed tar of metadata files
    - image.tar.<comp> — compressed tar of package files
    - signatures.tar.<comp> — compressed tar of GPG signatures (optional)
    - Manifest — checksums of the above
  - Metadata files within metadata.tar: same shape as binary package metadata
    (KEYWORDS, DEPEND, etc. — key=value format)

=head2 Installation hooks

Gentoo may include pkg_{pre,post}_{inst,rm,upgrade} functions. Alien
transcribes these as-is (never executes them).

=head1 AUTHOR

Underhall contributors <https://github.com/Zheke32174/underhall>

=cut

1;
