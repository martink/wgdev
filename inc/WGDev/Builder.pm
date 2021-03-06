package WGDev::Builder;
use strict;
use warnings;

use 5.008008;
our $VERSION = '0.0.2';

use Module::Build ();
BEGIN { our @ISA = qw(Module::Build) }

use File::Spec ();
use File::Temp ();
##no critic (ProhibitMagicNumbers Capitalization)

sub new {
    my $class   = shift;
    my %options = @_;
    $options{test_types}{author} = ['.at'];
    my $self = $class->SUPER::new(%options);
    return $self;
}

sub ACTION_testauthor {
    return shift->generic_test( type => 'author' );
}

# we're overriding this to use Pod::Coverage::TrustPod instead of the
# default
sub ACTION_testpodcoverage {
    my $self = shift;

    $self->depends_on('docs');

    eval {
        require Test::Pod::Coverage;
        Test::Pod::Coverage->VERSION(1.0);
        require Pod::Coverage::TrustPod;
        Pod::Coverage::TrustPod->VERSION(0.092400);
    }
        or die q{The 'testpodcoverage' action requires },
        q{Test::Pod::Coverage version 1.00 and Pod::Coverage::TrustPod version 0.092400};

    local @INC = @INC;
    my $p = $self->{properties};
    unshift @INC, File::Spec->catdir( $p->{base_dir}, $self->blib, 'lib' );

    Test::Pod::Coverage::all_pod_coverage_ok(
        { coverage_class => 'Pod::Coverage::TrustPod' } );
    return;
}

# Run perltidy over all the Perl code
# Borrowed from Test::Harness
sub ACTION_tidy {
    my $self = shift;

    my %found_files = map { %{$_} } $self->find_pm_files,
        $self->_find_file_by_type( 'pm', 't' ),
        $self->_find_file_by_type( 'pm', 'inc' ),
        $self->_find_file_by_type( 't',  't' ),
        $self->_find_file_by_type( 'at', 't' ),
        { 'Build.PL' => 'Build.PL' };

    my @files = sort keys %found_files;

    require Perl::Tidy;

    print "Running perltidy on @{[ scalar @files ]} files...\n";
    for my $file (@files) {
        print "  $file\n";
        if (
            eval {
                Perl::Tidy::perltidy( argv => [ '-b', '-nst', $file ], );
                1;
            } )
        {
            unlink "$file.bak";
        }
    }
}

sub ACTION_distexec {
    my $self = shift;
    require Digest::SHA1;
    $self->depends_on('build');

    # generate temporary tar file of needed libraries
    my $temp = File::Temp::tmpnam();
    system 'tar', 'czf', $temp, '-C', $self->blib, 'lib', 'script';

    # use SHA1 hash when extracting to ensure we are using the correct libs
    my $short_sha1 = do {
        open my $archive, '<', $temp;
        my $sha1 = Digest::SHA1->new->addfile($archive);
        close $archive;
        substr $sha1->hexdigest, 0, 8;
    };

    # create perl script with tar file attached in the __DATA__ secion.
    # when run, it extracts the attached file if needed and runs the wgd
    # script.
    my $dist_script = 'wgd-' . $self->dist_version;
    unlink $dist_script;
    open my $fh, '>', $dist_script;
    syswrite $fh, sprintf <<'END_SCRIPT', $short_sha1;
#!/usr/bin/env perl
my $out_dir = ($ENV{TMPDIR} || '/tmp') . "/WGDev-%s-$ENV{USER}";
if (! -e "$out_dir/perl/script/wgd") {
    mkdir $out_dir;
    mkdir "$out_dir/perl";
    open my $fh, '|-', 'tar', 'xz', '-C', "$out_dir/perl";
    my $buffer;
    syswrite $fh, $buffer
        while sysread \*DATA, $buffer, 1024;
    close $fh;
    die "Error extracting libraries!\n"
        if $?;
}
unshift @INC, "$out_dir/perl/lib";
require "$out_dir/perl/script/wgd";
__DATA__
END_SCRIPT

    # add tar file to the end of the script
    open my $tar_fh, '<', $temp;
    while (1) {
        my $buffer;
        my $read = sysread $tar_fh, $buffer, 1000;
        last
            if !$read;
        syswrite $fh, $buffer;
    }
    close $tar_fh;
    close $fh;
    chmod oct(555), $dist_script;
}

1;

