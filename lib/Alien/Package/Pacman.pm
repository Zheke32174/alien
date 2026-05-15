#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Pacman - an object that represents a pacman package (.pkg.tar.zst)

=cut

package Alien::Package::Pacman;
use strict;
use base qw(Alien::Package);
use File::Temp qw(tempdir);
use File::Find;
use Cwd;

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
	my $file=$this->filename;

	# Extract .PKGINFO from the tar.
	my @pkginfo=$this->runpipe(1, "tar -xOf '$file' .PKGINFO 2>/dev/null");
	die "No .PKGINFO found in '$file'; not a valid pacman package"
		if !@pkginfo;

	# Parse .PKGINFO key = value lines.
	my %fields;
	my (@depend, @conflict, @provides, @replaces);
	foreach my $line (@pkginfo) {
		chomp $line;
		next if $line =~ /^\s*#/ || $line =~ /^\s*$/;
		if ($line =~ /^\s*(\w+)\s*=\s*(.*?)\s*$/) {
			my $key = $1;
			my $value = $2;
			if ($key eq 'depend')    { push @depend,    $value; }
			elsif ($key eq 'conflict')  { push @conflict,  $value; }
			elsif ($key eq 'provides')  { push @provides,  $value; }
			elsif ($key eq 'replaces')  { push @replaces,  $value; }
			else                        { $fields{$key}    = $value; }
		}
	}

	die "Missing 'pkgname' in .PKGINFO from '$file'"
		unless exists $fields{pkgname};
	die "Missing 'pkgver' in .PKGINFO from '$file'"
		unless exists $fields{pkgver};

	# pkgver format: version-release (e.g. "2.12.1-1")
	my $pkgver = $fields{pkgver};
	if ($pkgver =~ /^(.+)-([^-]+)$/) {
		$this->version($1);
		$this->release($2);
	}
	else {
		$this->version($pkgver);
		$this->release(1);
	}

	$this->name($fields{pkgname});
	$this->arch($this->_translate_arch($fields{arch}))
		if exists $fields{arch};
	$this->summary($fields{pkgdesc})
		if exists $fields{pkgdesc};
	$this->description($fields{pkgdesc})
		if exists $fields{pkgdesc};
	$this->maintainer($fields{packager})
		if exists $fields{packager};
	$this->copyright($fields{license})
		if exists $fields{license};
	$this->group($fields{group})
		if exists $fields{group};

	$this->depends(join(", ", @depend))   if @depend;
	$this->conflicts(join(", ", @conflict))  if @conflict;
	$this->provides(join(", ", @provides))  if @provides;
	$this->replaces(join(", ", @replaces))  if @replaces;

	# Enumumerate package files: skip directories and root metadata files.
	my @tar_files = $this->runpipe(0, "tar -tf '$file' 2>/dev/null");
	chomp @tar_files;
	my @filelist;
	foreach my $f (@tar_files) {
		chomp $f;
		next if $f =~ m|/$|;                # skip directories
		next if $f =~ /^\.[^\/]/;           # skip root metadata (.PKGINFO, .INSTALL, .MTREE)
		push @filelist, "/$f";
	}
	$this->filelist(\@filelist) if @filelist;

	# Extract .INSTALL hook script if present.
	my $install_script = $this->runpipe(1,
		"tar -xOf '$file' .INSTALL 2>/dev/null");
	if (defined $install_script && length $install_script) {
		$this->_parse_install_script($install_script);
	}

	$this->origformat('pacman');
	$this->distribution('Arch Linux');

	return 1;
}

=item _translate_arch

Map pacman architecture to the Debian-internal naming used by Alien.

=cut

sub _translate_arch {
	my $this=shift;
	my $arch=shift;
	return unless defined $arch;

	my %map = (
		x86_64  => 'amd64',
		i386    => 'i386',
		i486    => 'i386',
		i586    => 'i386',
		i686    => 'i386',
		aarch64 => 'arm64',
		armv6h  => 'armhf',
		armv7h  => 'armhf',
		any     => 'all',
		noarch  => 'all',
	);
	return $map{$arch} if exists $map{$arch};
	return $arch; # passthrough unknown
}

=item _parse_install_script

Parse an .INSTALL shell script, extracting hook function bodies.
Transcribes as text — never executes.

Known hooks:
  post_install  -> postinst
  pre_upgrade   -> preinst
  post_upgrade  -> postinst
  pre_remove    -> prerm
  post_remove   -> postrm

=cut

sub _parse_install_script {
	my $this=shift;
	my $script=shift;
	return unless defined $script && length $script;

	my %hooks;
	my %hook_map = (
		post_install  => 'postinst',
		pre_upgrade   => 'preinst',
		post_upgrade  => 'postinst',
		pre_remove    => 'prerm',
		post_remove   => 'postrm',
	);

	foreach my $hook_name (keys %hook_map) {
		if ($script =~ /^\s*\Q$hook_name\E\s*\(\s*\)\s*\{/m) {
			# Locate the opening brace.
			my $brace = index($script, '{', $-[0]);
			# Find the matching closing brace.
			my $depth = 1;
			my $pos   = $brace + 1;
			while ($depth > 0 && $pos < length($script)) {
				my $ch = substr($script, $pos, 1);
				$depth++ if $ch eq '{';
				$depth-- if $ch eq '}';
				$pos++;
			}
			my $body = substr($script, $brace + 1, $pos - $brace - 2);
			$body =~ s/^\s+|\s+$//g;
			$hooks{$hook_name} = $body if length $body;
		}
	}

	# Concatenate hooks that map to the same alien field.
	foreach my $hook_name (keys %hooks) {
		my $field    = $hook_map{$hook_name};
		my $existing = $this->$field() || '';
		if (length $existing) {
			$this->$field($existing . "\n\n" . $hooks{$hook_name});
		}
		else {
			$this->$field($hooks{$hook_name});
		}
	}
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

=item _reverse_translate_arch

Map Debian-internal architecture naming back to Pacman's arch naming.
Inverse of _translate_arch.

=cut

sub _reverse_translate_arch {
	my $this=shift;
	my $arch=shift;
	return unless defined $arch;

	my %map = (
		amd64   => 'x86_64',
		i386    => 'i386',
		arm64   => 'aarch64',
		armhf   => 'armv7h',
		armel   => 'armv7h',
		all     => 'any',
	);
	return exists $map{$arch} ? $map{$arch} : $arch;
}

=item build

Build a pacman package from the prepped tree.

Populates .PKGINFO from the Alien::Package fields and assembles
a .pkg.tar.zst from the buildtree file tree. Optionally emits
.INSTALL if hook scripts are present.

Returns the filename of the generated package.

=cut

sub build {
	my $this=shift;

	my $buildtree=$this->buildtree;
	die "buildtree not set" unless defined $buildtree && -d $buildtree;

	my $name    = $this->name;
	my $version = $this->version;
	my $release = $this->release || 1;
	my $arch    = $this->_reverse_translate_arch($this->arch);

	defined $name    or die "name is required";
	defined $version or die "version is required";

	my $output = "${name}-${version}-${release}-${arch}.pkg.tar.zst";

	my $staging = tempdir("alien-pacman-XXXX", CLEANUP => 1, TMPDIR => 1);

	# --- Write .PKGINFO ---
	open my $fh, '>', "$staging/.PKGINFO" or die "$staging/.PKGINFO: $!";
	print $fh "# Generated by Alien\n";
	print $fh "pkgname = $name\n";
	print $fh "pkgver = ${version}-${release}\n";

	my $desc = $this->summary || $this->description;
	print $fh "pkgdesc = $desc\n" if defined $desc;
	print $fh "arch = $arch\n" if defined $arch;

	my $packager = $this->maintainer;
	print $fh "packager = $packager\n" if defined $packager;
	my $license = $this->copyright;
	print $fh "license = $license\n" if defined $license;
	my $group = $this->group;
	print $fh "group = $group\n" if defined $group;
	print $fh "builddate = " . time() . "\n";

	# Installed size: sum of regular-file sizes in buildtree
	my $size = 0;
	find(sub { $size += -s _ if -f _ }, $buildtree);
	print $fh "size = $size\n";

	# Multi-value fields (comma-separated in internal representation)
	foreach my $field_spec (
		['depends',   'depend'],
		['conflicts', 'conflict'],
		['provides',  'provides'],
		['replaces',  'replaces'],
	) {
		my ($int_field, $pkginfo_field) = @$field_spec;
		my $val = $this->$int_field();
		if (defined $val) {
			foreach my $v (split(/, /, $val)) {
				print $fh "${pkginfo_field} = $v\n";
			}
		}
	}
	close $fh;

	# --- Write .INSTALL (if hook scripts present) ---
	my %pacman_hooks = (
		postinst => 'post_install',
		preinst  => 'pre_install',
		postrm   => 'post_remove',
		prerm    => 'pre_remove',
	);

	my @install_bodies;
	foreach my $alien_hook (sort keys %pacman_hooks) {
		my $body = $this->$alien_hook();
		if (defined $body && length $body) {
			push @install_bodies,
				$pacman_hooks{$alien_hook} . "() {\n" . $body . "\n}";
		}
	}

	if (@install_bodies) {
		open $fh, '>', "$staging/.INSTALL"
			or die "$staging/.INSTALL: $!";
		print $fh "#!/bin/bash\n\n";
		print $fh join("\n\n", @install_bodies) . "\n";
		close $fh;
	}

	# --- Copy file tree from buildtree (skip metadata files) ---
	opendir(my $dh, $buildtree) or die "opendir $buildtree: $!";
	my @entries = grep { !/^\.\.?$/ } readdir($dh);
	closedir $dh;

	foreach my $entry (@entries) {
		next if $entry eq '.PKGINFO' || $entry eq '.INSTALL'
			|| $entry eq '.MTREE';
		system("cp -a '$buildtree/$entry' '$staging/$entry'");
		die "Failed to copy $entry: $!" if $? != 0;
	}

	# --- Build package tar with zstd compression ---
	opendir($dh, $staging) or die "opendir $staging: $!";
	my @tar_entries = sort grep { !/^\.\.?$/ } readdir($dh);
	closedir $dh;

	my $tar_cwd = Cwd::abs_path();
	my $tar_ok  = $this->do("tar", "--zstd", "-cf",
		Cwd::abs_path($output), "-C", $staging, @tar_entries);
	die "Failed to create package: tar returned $?" unless $tar_ok;

	# Validate output
	die "Package file '$output' was not created" unless -f $output;
	die "Package file '$output' has zero size"    unless -s $output;

	return $output;
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
