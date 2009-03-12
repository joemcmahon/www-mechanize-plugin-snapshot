package WWW::Mechanize::Plugin::Snapshot;

our $VERSION = '0.01';

use warnings;
use strict;
use Carp;

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw(_suffix));

use File::Path;
use Inline::Files;
use Text::Template;
use Data::Dumper;

sub init {
  no strict 'refs';
  *{caller() . "::snapshots_to"} = \&snapshots_to;
  *{caller() . "::snapshot"}     = \&snapshot;
  *{caller() . "::dumpvar"}      = \&dumpvar;
  *{caller() . "::_suffix"}      = \&_suffix;
  *{caller() . "::_mk_name"}     = \&_mk_name;
  *{caller() . "::_build_file"}  = \&_build_file;
}

sub snapshots_to {
  my ($pluggable, $snap_dir) = @_;
  unless (defined $snap_dir) {
    unless (defined $pluggable->{SnapDirectory}) {
      $pluggable->{SnapDirectory} = 
         $ENV{TMPDIR} || $ENV{TEMP}||
          die "No TMPDIR/TEMP defined on this system!\n";
    }
    else {
      # we have a snap directory, do nothing
    }
  }
  else {
    die "$snap_dir is not a directory\n" 
      unless -d $snap_dir;
    $pluggable->{SnapDirectory} = $snap_dir;
  }
  $pluggable->{SnapDirectory};
}

sub snapshot {
  my ($pluggable, $comment) = @_;
  local $_;
  my @template_text;

  my $suffix = $pluggable->_suffix(time);

  my $frame_file = 
    $pluggable->_build_file(name=>'frame',
                           fh  =>*FRAME,
                           hash=>{suffix => $suffix},
                          );

  $pluggable->_build_file(name=>'url',
                         fh  =>*URL,
                         hash=>{url => $pluggable->base},
                        );

  $pluggable->_build_file(name=>'comment',
                         fh  =>*COMMENT,
                         hash=>{comment => $comment},
                        );

  $pluggable->_build_file(name=>'content',
                         fh  =>*CONTENT,
                         hash=>{content => $pluggable->content(base_href=>$pluggable->base)},
                        );

  $pluggable->_build_file(name=>"request",
                          fh=>*REQUEST,
                          hash=>{dump => Dumper($pluggable->mech->{req})}
                         ); 

  $pluggable->_build_file(name=>"jar",
                          fh=>*JAR,
                          hash=>{dump => Dumper($pluggable->cookie_jar)}
                         ); 

  # We need to nuke stuff out of the response, but we don't want to
  # damage the original. Clone it, and then discard stuff from the 
  # clone.
  my %res = %{$pluggable->mech->{res}};
  delete $res{'_content'};
  delete $res{'_request'};
  
  $pluggable->_build_file(name=>"response",
                          fh=>*RESPONSE,
                          hash=>{dump => Dumper(\%res)}
                         ); 

  
  return $frame_file;
}

sub _build_file {
  my ($pluggable, %args) = @_;

  die "No HTML output file name supplied" 
    unless defined $args{name};
  die "No template filehandle supplied" 
    unless defined $args{fh};
  die "No customization hash supplied"
    unless $args{hash};
  my $local_fh = $args{fh};

  seek $args{fh}, 0,0;
  my $template = Text::Template->new(TYPE=>'ARRAY', SOURCE=>[<$local_fh>]);
  my $filename = $pluggable->_mk_name($args{name});
  my $fh;
  open $fh, ">$filename" 
    or die "Can't open $args{name} file $filename: $!";
  print $fh  $template->fill_in(HASH=>$args{hash});
  close $fh;
 
  return $filename;
}
  

sub _mk_name {
  my ($pluggable, $name) = @_;
  return File::Spec->catfile($pluggable->snapshots_to(), 
                             "$name".$pluggable->_suffix.".html");
}

1; # Magic true value required at end of module
__FRAME__
<html>

<head><title>Page snapshot: {$formatted_date}</title>
</head>
<frameset cols="36%,64%">
<frameset rows="3%,10%,20%,42%,25%">
<frame src="url{$suffix}.html">
<frame src="comment{$suffix}.html">
<frame src="request{$suffix}.html">
<frame src="response{$suffix}.html">
<frame src="jar{$suffix}.html">
</frameset>
<frameset rows="100%">
<frame src="content{$suffix}.html">
</frameset>

</html>
__COMMENT__
<html><head><title>Page snapshot: user comment</title></head><body>{$comment}</body></html>
__URL__
<html><head><title>Page snapshot: URL</title></head><body><tt>{$url}</tt></body></html>
__REQUEST__
<html><head><title>Page snapshot: HTTP request</title></head><body><pre>{$dump}</pre></body></html>
__RESPONSE__
<html><head><title>Page snapshot: HTTP request</title></head><body><pre>{$dump}</pre></body></html>
__JAR__
<html><head><title>Page snapshot: Cookie jar</title></head><body><pre>{$dump}</pre></body></html>
__CONTENT__
{$content}
__END__

=head1 NAME

WWW::Mechanize::Plugin::Snapshot - Snapshot the Mech object's state

=head1 VERSION

This document describes WWW::Mechanize::Plugin::Snapshot version 0.01


=head1 SYNOPSIS

    use WWW::Mechanize::Pluggable;
    my $mech->new;
    $mech->snapshots_to("/some/file/path");
    $mech->get("http://problematic.org");
    $snapshot_file_name = $mech->snapshot("Accessing problematic.org");
    # $snapshot file name is the name of a HTML file showing 
    # the request and the response

=head1 DESCRIPTION

C<WWW::Mechanize::Plugin::Snapshot> is a Web debugging plugin. It allows
you to selectively dump the results of an HTTP request to files that can
be displayed in a browser, showing not only the web page at the time of 
the request, but also

=over 4

=item * Arbitrary comment information from the user (as text).

=item * The URL of the request.

=item * A formatted copy of the HTTP request

=item * A formatted HTTP response (less the actual content and the request)

=item * The current contents of the cookie jar

=item * The actual web page content

=back

The returned page is displayed as a part of a fram, allowing you to see the
entire page content and to view the source separately from the containing
frame.

=head1 INTERFACE 

=head2 init

Standard importation of methods into C<WWW::Mechanize::Pluggable>.

=head2 snapshots_to($dir)

Requires a directory to which the snapshots will be taken. 

If this method is not called prior to the use of C<snapshot>,
the system default temporary file directory is used.

=head2 snapshot

Takes a snapshot of the current state of the C<WWW::Mechanize> object
contained in the C<WWW::Mechanize::Pluggable> object.

=head1 DIAGNOSTICS

=over

=item C<< Could not write to %s directory: %s >>

We attempted to take a snapshot, but we couldn't write the files to
the selected temporary directory. The contents of C<$!> are appended
to try to diagnose the error further.

=back


=head1 CONFIGURATION AND ENVIRONMENT

WWW::Mechanize::Plugin::Snapshot requires no configuration files or environment variables.

=head1 DEPENDENCIES

Since this is a C<WWW::Mechanize::Pluggable> plugin, that module is required.


=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-www-mechanize-plugin-snapshot@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Joe McMahon  C<< <mcmahon@yahoo-inc.com > >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2005, Joe McMahon C<< <mcmahon@yahoo-inc.com > >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
