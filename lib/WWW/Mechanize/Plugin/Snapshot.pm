package WWW::Mechanize::Plugin::Snapshot;

our $VERSION = '0.03';

use warnings;
use strict;
use Carp;

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw(_suffix snapshot_comment));

use File::Path;
use Text::Template;
use Data::Dumper;

my %template = (
  frame =><<EOS,
<html>
    
<head><title>Page snapshot: [\$formatted_date]</title>
</head>
<frameset cols="36%,64%">
<frame src="debug[\$suffix].html">
<frame src="content[\$suffix].html">
</frameset>

</html>
EOS

  content=><<EOS,
[\$content]
EOS

 debug=><<EOS,
<html>
<head>
<title>Page snapshot: debug info</title>
<STYLE TYPE="text/css">
<!--
H1 { color: white; background: violet; font-size: 110%; font-family: impact, sans-serif }
pre { font-family: courier font-size:50%}
-->
</STYLE>
</head>
<body>
<h1>Description</h1><div class="comment">[\$comment]</div>
<h1>Original URL</h1><div class="url">[\$url]</div>
<h1>HTTP request</h1><div class="request"><pre>[\$req]</pre></div>
<h1>HTTP response</h1><div class="response"><pre>[\$res]</pre></div>
<h1>Cookie jar</h1><div class="jar"><pre>[\$jar]</pre></div>
</body>
</html>
EOS

);

sub init {
  no strict 'refs';
  *{caller() . "::snapshots_to"}     = \&snapshots_to;
  *{caller() . "::snapshot"}         = \&snapshot;
  *{caller() . "::_suffix"}          = \&_suffix;
  *{caller() . "::snapshot_comment"} = \&snapshot_comment;
  *{caller() . "::_mk_name"}         = \&_mk_name;
  *{caller() . "::_build_file"}      = \&_build_file;
  *{caller() . "::_template"}        = \&_template;
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
  my ($pluggable, $comment, $suffix) = @_;
  local $_;
  my @template_text;

  $suffix = $pluggable->_suffix($suffix||time);

  my $frame_file = 
    $pluggable->_build_file(name=>'frame',
                            hash=>{suffix => $suffix},
                          );

  # We need to nuke stuff out of the response, but we don't want to
  # damage the original. Clone it, and then discard stuff from the 
  # clone.
  my %res = %{$pluggable->mech->{res}};
  delete $res{'_content'};
  delete $res{'_request'};
  
  $pluggable->_build_file(name=>'debug',
                          hash=>{url     => $pluggable->base,
                                 comment => ($comment || 
                                             $pluggable->snapshot_comment || 
                                             "No comment specified"),
                                 content => $pluggable->content(base_href=>$pluggable->base),
                                 req     => Dumper($pluggable->mech->{req}),
                                 res     => Dumper(\%res),
                                 jar     => Dumper($pluggable->cookie_jar),
                                }
                         ); 

  $pluggable->_build_file(name=>'content',
                          hash=>{content => $pluggable->content},
                          );

  return $frame_file;
}

sub _build_file {
  my ($pluggable, %args) = @_;

  die "No HTML output file name supplied" 
    unless defined $args{name};
  die "No customization hash supplied"
    unless $args{hash};
  my $template;

  if (!($template = $pluggable->_template($args{name}))) {
    # Done this way so we don't have to rebuild the templates
    # every time through. Also avoids annoying Inline::Files
    # behavior that makes it hard to reuse the template files.
    die "Nonexistent template $args{name}\n" 
      unless $template{$args{name}}; 

    $template = Text::Template->new(TYPE=>'ARRAY', 
                                    DELIMITERS=>['[',']'],
                                    SOURCE=>[$template{$args{name}}]);

    $pluggable->_template($args{name}, $template);
  }
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

sub _template {
  my ($pluggable, $template_name, $template) = @_;

  die "Can't access undefined template!" unless defined $template_name;

  if (defined $template_name and defined $template) {
    $pluggable->{SnapTemplates}->{$template_name} = $template;
  }
  return $pluggable->{SnapTemplates}->{$template_name};
}

1; # Magic true value required at end of module
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
    # Create timestamped snapshot
    $snapshot_file_name = $mech->snapshot("Accessing problematic.org");

    # Create user-named snapshot
    $foo_file = $mech->snapshot("Special file", "foo");

    # Preset the comment:
    $mech->snapshot_comment("Failed during test set 1");

    # Resulting file uses the comment preset before the 
    # snapshot call.
    $standard_name = $mech->snapshot();

    # Use a different filename. keeping the preset comment:
    $foo_file = $mech->snapshot(undef, "foo");
   

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

The output is displayed in a frame, with the debug ingormation on the left
and the actual page HTML as fetched at the time of the snapshot on the right.

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
