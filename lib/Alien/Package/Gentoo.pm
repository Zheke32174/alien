#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Gentoo - an object that represents a Gentoo binary package (.tbz2 / .gpkg.tar)

=cut

package Alien::Package::Gentoo;
use strict;
use base qw(Alien::Package);
use File::Temp qw(tempdir);

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
	my $file=$this->filename;

	if ($this->_is_gpkg_tar($file)) {
		$this->_scan_gpkg_tar($file);
	}
	else {
		$this->_scan_tbz2($file);
	}

	$this->origformat('gentoo');
	$this->distribution('Gentoo');

	return 1;
}

=item _is_gpkg_tar

Detect whether a file is a modern .gpkg.tar (GLEP 78) package.
Uses filename extension or checks first tar member name.

=cut

sub _is_gpkg_tar {
	my $this=shift;
	my $file=shift;

	return 1 if $file =~ /\.gpkg\.tar$/i;

	my $first=$this->runpipe(1, "tar -tf '$file' 2>/dev/null | head -1");
	chomp $first if defined $first;
	return 1 if defined $first && $first =~ /^metadata\.tar\./;
	return 0;
}

=item _scan_gpkg_tar

Parse a modern GLEP-78 .gpkg.tar binary package.

.tpkg.tar layout:
  metadata.tar.<comp>   — compressed tar of metadata files
  image.tar.<comp>      — compressed tar of package contents
  signatures.tar.<comp> — optional GPG signatures
  Manifest              — checksums

Metadata files within metadata.tar are named after their key
(PF, CATEGORY, DESCRIPTION, CHOST, DEPEND, etc.).

=cut

sub _scan_gpkg_tar {
	my $this=shift;
	my $file=$this->filename;

	# Locate the metadata section member.
	my $metadata_member=$this->runpipe(1,
		"tar -tf '$file' 2>/dev/null | grep '^metadata\\.tar\\.' | head -1");
	chomp $metadata_member;
	die "No metadata.tar.* found in .gpkg.tar '$file'"
		unless $metadata_member;

	# Extract metadata tar into a temp directory.
	# Determine compression flag from the member name.
	my $comp_flag='';
	if    ($metadata_member =~ /\.gz$/)  { $comp_flag='z'; }
	elsif ($metadata_member =~ /\.bz2$/) { $comp_flag='j'; }
	elsif ($metadata_member =~ /\.xz$/)  { $comp_flag='J'; }
	elsif ($metadata_member =~ /\.zst$/) { $comp_flag='--zstd'; }
	elsif ($metadata_member =~ /\.lz$/)  { $comp_flag='--lzip'; }

	my $tmpdir=tempdir("alien-gpkg-XXXX", CLEANUP => 1, TMPDIR => 1);
	my $cmd="tar -xOf '$file' '$metadata_member' 2>/dev/null | " .
	        "tar -C '$tmpdir' -x${comp_flag}f - 2>/dev/null";
	system($cmd);
	die "Failed to extract metadata from '$file'"
		unless -d $tmpdir;

	# Read metadata files.
	my %meta;
	foreach my $key (qw(PF CATEGORY DESCRIPTION HOMEPAGE LICENSE CHOST
	                    DEPEND RDEPEND PROVIDE PDEPEND CONTENTS
	                    PN PV PR PVR KEYWORDS IUSE SLOT)) {
		$meta{$key}=$this->_read_meta_file("$tmpdir/$key");
	}

	# --- Map to Alien::Package fields ---

	# Name and version from PN/PV, else heuristically from PF.
	if (defined $meta{PN}) {
		$this->name($meta{PN});
	}
	elsif (defined $meta{PF}) {
		my ($name) = $this->_split_pf($meta{PF});
		$this->name($name);
	}

	if (defined $meta{PV}) {
		$this->version($meta{PV});
	}
	elsif (defined $meta{PF}) {
		my (undef, $version) = $this->_split_pf($meta{PF});
		$this->version($version) if defined $version;
	}

	if (defined $meta{PR}) {
		$this->release($meta{PR});
	}
	else {
		$this->release(1);
	}

	$this->group($meta{CATEGORY})               if defined $meta{CATEGORY};
	$this->summary($meta{DESCRIPTION})           if defined $meta{DESCRIPTION};
	$this->description($meta{DESCRIPTION})       if defined $meta{DESCRIPTION};
	$this->copyright($meta{LICENSE})             if defined $meta{LICENSE};
	$this->arch($this->_translate_chost($meta{CHOST})) if defined $meta{CHOST};

	# Dependencies: collect DEPEND + RDEPEND + PDEPEND.
	my @depends;
	push @depends, split(/\s+/, $meta{DEPEND})  if defined $meta{DEPEND};
	push @depends, split(/\s+/, $meta{RDEPEND}) if defined $meta{RDEPEND};
	push @depends, split(/\s+/, $meta{PDEPEND}) if defined $meta{PDEPEND};
	$this->depends(join(", ", @depends)) if @depends;

	$this->provides($meta{PROVIDE}) if defined $meta{PROVIDE};

	# File list from CONTENTS.
	if (defined $meta{CONTENTS}) {
		my @filelist;
		foreach my $cline (split(/\n/, $meta{CONTENTS})) {
			chomp $cline;
			# Format: "obj /path ..." or "sym /path -> target"
			if ($cline =~ /^(obj|sym)\s+(\/\S+)/) {
				push @filelist, $2;
			}
		}
		$this->filelist(\@filelist) if @filelist;
	}
}

=item _scan_tbz2

Parse a legacy .tbz2 package with XPAK metadata trailer.

The last 8 bytes of the file are a footer:
  [4 bytes: uint32 BE offset from end to XPAK start]
  [4 bytes: 'STOP' magic]

The XPAK header at that offset:
  'XPAKPACK' magic (8 bytes)
  index_len (uint32 BE)
  data_len (uint32 BE)
  [index section: index_len bytes of {name_len uint32 BE, name, data_offset uint32 BE, data_len uint32 BE}]
  [data section: data_len bytes of concatenated values]
  'XPAKSTOP' magic (8 bytes)

Control files inside XPAK use filenames like 'CONTROL' (key=value metadata)
and 'CONTENTS' (file listing).

=cut

sub _scan_tbz2 {
	my $this=shift;
	my $file=$this->filename;

	my %xpak = $this->_extract_xpak($file);
	die "No XPAK metadata found in '$file' (not a valid .tbz2)"
		unless %xpak;

	# Parse CONTROL section.
	my %meta;
	if (defined $xpak{CONTROL}) {
		foreach my $line (split(/\n/, $xpak{CONTROL})) {
			chomp $line;
			next if $line =~ /^\s*$/;
			if ($line =~ /^(\w+)=(.*)$/) {
				$meta{$1} = $2;
			}
		}
	}

	# Map CONTROL fields.
	if (defined $meta{PF}) {
		my ($name, $version) = $this->_split_pf($meta{PF});
		$this->name($name);
		$this->version($version) if defined $version;
	}
	$this->group($meta{CATEGORY})               if defined $meta{CATEGORY};
	$this->summary($meta{DESCRIPTION})           if defined $meta{DESCRIPTION};
	$this->description($meta{DESCRIPTION})       if defined $meta{DESCRIPTION};
	$this->copyright($meta{LICENSE})             if defined $meta{LICENSE};
	$this->arch($this->_translate_chost($meta{CHOST})) if defined $meta{CHOST};

	my @depends;
	push @depends, split(/\s+/, $meta{DEPEND})  if defined $meta{DEPEND};
	push @depends, split(/\s+/, $meta{RDEPEND}) if defined $meta{RDEPEND};
	$this->depends(join(", ", @depends)) if @depends;
	$this->provides($meta{PROVIDE}) if defined $meta{PROVIDE};

	# Fallback if no split succeeded.
	$this->name($meta{PF})  if !$this->name && defined $meta{PF};
	$this->release(1)       if !$this->release;

	# File list from CONTENTS section.
	if (defined $xpak{CONTENTS}) {
		my @filelist;
		foreach my $cline (split(/\n/, $xpak{CONTENTS})) {
			chomp $cline;
			if ($cline =~ /^(obj|sym)\s+(\/\S+)/) {
				push @filelist, $2;
			}
		}
		$this->filelist(\@filelist) if @filelist;
	}
}

=item _extract_xpak

Extract all named blobs from a .tbz2 XPAK trailer using pure Perl
pack/unpack (big-endian integers).

Returns a hash of name => content.

=cut

sub _extract_xpak {
	my $this=shift;
	my $file=shift;

	open my $fh, '<:raw', $file or die "Cannot open '$file': $!";
	my %xpak;

	# Read footer: last 8 bytes = uint32 BE offset + 'STOP'.
	seek $fh, -8, 2;
	my $footer;
	read $fh, $footer, 8;
	my ($offset, $stop) = unpack('N A4', $footer);
	die "Invalid XPAK: missing STOP magic" unless $stop eq 'STOP';

	my $filesize = -s $file;
	my $xpak_start = $filesize - $offset;
	die "Invalid XPAK offset ($offset > $filesize)"
		if $xpak_start < 0;

	# Seek to XPAK and verify magic.
	seek $fh, $xpak_start, 0;
	my $magic;
	read $fh, $magic, 8;
	die "Invalid XPAK: missing XPAKPACK magic"
		unless $magic eq 'XPAKPACK';

	# Read index and data lengths.
	my $len_buf;
	read $fh, $len_buf, 8;
	my ($index_len, $data_len) = unpack('N N', $len_buf);

	# Read index section.
	my $index_data;
	read $fh, $index_data, $index_len;

	# Parse index entries.
	my @index;
	my $pos = 0;
	while ($pos < $index_len) {
		my ($name_len) = unpack('N', substr($index_data, $pos, 4));
		$pos += 4;
		last if $name_len == 0 || $pos + $name_len > $index_len;
		my $name = substr($index_data, $pos, $name_len);
		$pos += $name_len;
		my ($data_off, $data_sz) = unpack('N N', substr($index_data, $pos, 8));
		$pos += 8;
		push @index, { name => $name, offset => $data_off, length => $data_sz };
	}

	# Read data section.
	my $data_section;
	read $fh, $data_section, $data_len;

	# Verify end magic.
	my $end_magic;
	read $fh, $end_magic, 8;
	die "Invalid XPAK: missing XPAKSTOP magic"
		unless $end_magic eq 'XPAKSTOP';

	# Extract values.
	foreach my $entry (@index) {
		my $val = substr($data_section, $entry->{offset}, $entry->{length});
		$val =~ s/\0+$//;  # strip trailing nulls
		$xpak{$entry->{name}} = $val;
	}

	close $fh;
	return %xpak;
}

=item _read_meta_file

Read a single-line (or multi-line) text file from the metadata directory.
Returns the content with trailing whitespace stripped, or undef if missing.

=cut

sub _read_meta_file {
	my $this=shift;
	my $path=shift;
	return undef unless defined $path && -f $path;
	open my $fh, '<', $path or return undef;
	my $content = do { local $/; <$fh> };
	close $fh;
	$content =~ s/^\s+|\s+$//g;
	return $content;
}

=item _split_pf

Split a Gentoo PF string (e.g. "hello-2.12.1-r1") into name and version.
Uses heuristic: version starts after the last hyphen preceding a digit.

Returns (name, version). Version may be undef if PF is malformed.

=cut

sub _split_pf {
	my $this=shift;
	my $pf=shift;
	return (undef, undef) unless defined $pf;

	if ($pf =~ /^(.+?)-(\d.*)$/) {
		return ($1, $2);
	}
	return ($pf, undef);
}

=item _translate_chost

Translate Gentoo CHOST triplet (e.g. "x86_64-pc-linux-gnu") to Debian-
internal architecture naming.

=cut

sub _translate_chost {
	my $this=shift;
	my $chost=shift;
	return undef unless defined $chost;

	my ($arch) = split(/-/, $chost);
	my %map = (
		x86_64    => 'amd64',
		i386      => 'i386',
		i486      => 'i386',
		i586      => 'i386',
		i686      => 'i386',
		aarch64   => 'arm64',
		armv6     => 'armhf',
		armv7a    => 'armhf',
		armv7l    => 'armhf',
		powerpc   => 'powerpc',
		ppc64     => 'ppc64',
		ppc64le   => 'ppc64el',
		sparc     => 'sparc',
		alpha     => 'alpha',
		ia64      => 'ia64',
		s390      => 's390',
		s390x     => 's390x',
	);
	return exists $map{$arch} ? $map{$arch} : $arch;
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
