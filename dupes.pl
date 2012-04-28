#!/usr/bin/perl -w

######################################################################
#
#  Perl Duplicate File Finder
#  Copyright (C) 2001-2012 Doug Mitchell
#
#  This module is free software.  You can redistribute it and/or
#  modify it under the terms of the Artistic License 2.0.
#
#  This program is distributed in the hope that it will be useful,
#  but without any warranty; without even the implied warranty of
#  merchantability or fitness for a particular purpose.
#
######################################################################

use strict;
use warnings;
use File::Find;
use Digest::MD5;

# minimum size files to look at
my $min_size = 65536;


######################################################################
#
#  get_md5_hashes
#
#  Returns array of MD5 hashes for provided array of filenames
#
######################################################################

sub get_md5_hashes {
    my @filenames = @_;
    my @hashvals;

    foreach my $filename (@filenames) {

        open( FILE, $filename ) or warn "Can't open '$filename': $!";
        my $hashval = Digest::MD5->new->addfile(*FILE)->hexdigest;
        close(FILE);

        if ( defined $hashval && $hashval ne '' ) {
            push @hashvals, ( $hashval . " " . $filename );
        }

    }

    return @hashvals;
}


######################################################################
#
#  main
#
#  finds files with matching sizes and compares MD5 hashes
#  to determine which files are exact duplicates
#
######################################################################

{

    my $items_scanned       = 0;
    my $regular_files_found = 0;

    my %filesizes;
    my %size_inode;

    die "provide starting directories on command line"
      if ( !defined $ARGV[0] );

    if ( $ARGV[0] eq '-s' ) {
        my $junk = shift;
        $min_size = shift;
    }

    sub wanted {

        my (
            $dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
            $size, $atime, $mtime, $ctime, $blksize, $blocks
        ) = lstat($_);

        if ( $dev == $File::Find::topdev && $_ ne '.svn' ) {
            $items_scanned++;
            if ( -f _ && ( $size >= $min_size ) ) {
                $filesizes{$size}{$File::Find::name} = "";
                $size_inode{$size}{$ino}             = 0;
                $regular_files_found++;
            }
        }
        else {
            $File::Find::prune = 1;
        }
    }

    # Traverse desired filesystems
    foreach (@ARGV) {
        File::Find::find( \&wanted, $_ );
    }

    print "scanned $items_scanned filesystem items\n";
    print "found $regular_files_found regular files\n";

    # Remove non-duplicate sizes from filesize hash
    my $same_size_files = 0;
    foreach my $size ( sort { $a <=> $b } keys %filesizes ) {
        my @inodes = keys %{ $size_inode{$size} };
        if ( $size < $min_size || ( scalar @inodes <= 1 ) ) {
            delete $filesizes{$size};
            delete $size_inode{$size};
        }
        else {
            my @filenames = keys %{ $filesizes{$size} };
            $same_size_files += scalar @filenames;
        }
    }

    print "found $same_size_files files sharing "
      . scalar( keys %filesizes )
      . " sizes\n";

    my $total_dupe_bytes = 0;
    my $total_dupe_count = 0;

    foreach my $size ( sort { $a <=> $b } keys %filesizes ) {
        my @filenames = keys %{ $filesizes{$size} };
        my @inodes    = keys %{ $size_inode{$size} };

        my %fingerprints = ();
        my @hashvals     = get_md5_hashes(@filenames);

        # index filenames by hash value
        foreach (@hashvals) {
            my ( $md5, $filename ) = split( ' ', $_, 2 );
            push @{ $fingerprints{$md5} }, $filename;
        }

        # print out hash values with multiple filenames
        foreach my $md5 ( keys %fingerprints ) {
            my $filecount = scalar @{ $fingerprints{$md5} };
            if ( $filecount > 1 ) {
                print "\nmd5 $md5 / $size bytes:\n";
                foreach ( @{ $fingerprints{$md5} } ) {
                    my (
                        $dev,   $ino,     $mode, $nlink, $uid,
                        $gid,   $rdev,    $size, $atime, $mtime,
                        $ctime, $blksize, $blocks
                    ) = lstat($_);
                    printf "    %-9d  %s\n", $ino, $_;

                }

                $total_dupe_count += ( $filecount - 1 );
                $total_dupe_bytes += ( $size * ( $filecount - 1 ) );
            }
        }

    }

    print "\n$total_dupe_bytes bytes in $total_dupe_count duplicate files\n";
}

# vim: set autoindent expandtab tabstop=4 shiftwidth=4 shiftround:
