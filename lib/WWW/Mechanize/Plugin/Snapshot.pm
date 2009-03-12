package WWW::Mechanize::Plugin::Snapshot;

our $VERSION = '0.12';

use warnings;
use strict;
use Carp;

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw(_suffix snapshot_comment sub snap_prefix _run_tag _snap_count));

use File::Path;
use File::Spec;
use Text::Template;
use Data::Dumper;

my %template = (
  frame =><<EOS,
<html>
    
<head><title>Page snapshot: [\$formatted_date]</title>
</head>
<frameset cols="36%,64%">
<frame src="debug_[\$suffix]-[\$snap_count].html">
<frame src="content_[\$suffix]-[\$snap_count].html">
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
H1 { color: black; background: #eeeeee; font-size: 110%; font-family: impact, sans-serif }
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
  *{caller() . "::_mk_short_name"}   = \&_mk_short_name;
  *{caller() . "::_build_file"}      = \&_build_file;
  *{caller() . "::_template"}        = \&_template;
  *{caller() . "::snap_prefix"}      = \&snap_prefix;
  *{caller() . "::_run_tag"}         = \&_run_tag;
  *{caller() . "::_snapped"}         = \&_snapped;
  *{caller() . "::_snap_count"}      = \&_snap_count;
}

sub _snapped {
  my ($pluggable) = @_;
  $pluggable->_snap_count($pluggable->_snap_count()+1);
}

sub snapshots_to {
  my ($pluggable, $snap_dir) = @_;

  my $now = _pretty_time();
  $pluggable->_suffix(_pretty_time()) 
    unless $pluggable->_suffix();
  $pluggable->_run_tag("run_".$pluggable->_suffix)
    unless $pluggable->_run_tag;
  $pluggable->_snap_count(0)
    unless defined $pluggable->_snap_count();

  if (!defined $snap_dir) {
    # No argument, grap existing or create from
    # defaults if possible
    if (!defined $pluggable->{SnapDirectory}) {
      $snap_dir = 
         $ENV{TMPDIR} || $ENV{TEMP}||
          die "No TMPDIR/TEMP defined on this system!\n";

      $snap_dir =
        File::Spec->catfile($snap_dir, $pluggable->_run_tag());
    }
    else {
      # use the existing value
      $snap_dir = $pluggable->{SnapDirectory};
    }
  }
  else {
    # Arg supplied, add on the timestamp
    $snap_dir = File::Spec->catfile($snap_dir, $pluggable->_run_tag());
  }

  if (!-e $snap_dir) {
    eval { mkpath $snap_dir };
    if ($@) {
      die "Couldn't create directory $snap_dir: $@\n";
    }
  }
  else {
    die "$snap_dir is not a directory\n" 
      unless -d $snap_dir;
  }

  $pluggable->{SnapDirectory} = $snap_dir;
  return $snap_dir;
}

sub snapshot {
  my ($pluggable, $comment, $suffix) = @_;
  local $_;
  my @template_text;
  $pluggable->_snapped;

  # Use passed-in suffix if available, and 
  # set it as the default suffix. If not,
  # continue using the one set up in snapshots_to.
  if (defined $suffix) {
    $pluggable->_suffix($suffix);
  }
  else {
    $suffix = $pluggable->_suffix();
  }

  my $frame_file = 
    $pluggable->_build_file(name=>'frame',
                            version => $pluggable->_snap_count,
                            hash=>{suffix => $suffix,
                                   snap_count  => $pluggable->_snap_count()},
                          );

  # We need to nuke stuff out of the response, but we don't want to
  # damage the original. Clone it, and then discard stuff from the 
  # clone.
  my %res = %{$pluggable->mech->{res}};
  delete $res{'_content'};
  delete $res{'_request'};
  
  $pluggable->_build_file(name=>'debug',
                          version => $pluggable->_snap_count,
                          hash=>{url        => $pluggable->base,
                                 comment    => ($comment || 
                                                $pluggable->snapshot_comment || 
                                                "No comment specified"),
                                 content    => $pluggable->content(base_href=>$pluggable->base),
                                 req        => Dumper($pluggable->mech->{req}),
                                 res        => Dumper(\%res),
                                 jar        => Dumper($pluggable->cookie_jar),
                                 suffix     => $suffix,
                                }
                         ); 

  $pluggable->_build_file(name=>'content',
                          version => $pluggable->_snap_count,
                          hash=>{content    => $pluggable->content,
                                 suffix     => $suffix,
                                },
                          );

  my $prefix = $pluggable->snap_prefix();
   
  if (defined $prefix) {
    $frame_file = $prefix . "/" . $pluggable->_run_tag . "/" . 
                  $pluggable->_mk_short_name(name=>"frame",
                                             version=>$pluggable->_snap_count);
  }
  else {
    $frame_file = $pluggable->_mk_name(name=>"frame",
                                       version=>$pluggable->_snap_count);
  }
  $frame_file =~ s{(?<!http:)//}{/}gsm;
  return $frame_file;
}

sub _pretty_time {
  my @t = split(/\s+|:/,scalar localtime);
  return sprintf("%s-%s-%02d-%02d-%02d-%02d-%04d",@t);
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
  my $filename = $pluggable->_mk_name(%args);
  my $fh;
  open $fh, ">$filename" 
    or die "Can't write to $args{name} file $filename: $!";
  print $fh  $template->fill_in(HASH=>$args{hash});
  close $fh;
 
  return $filename;
}
  

sub _mk_name {
  my ($pluggable, %args) = @_;
  return File::Spec->catfile($pluggable->snapshots_to(), 
                             $pluggable->_mk_short_name(%args));
}

sub _mk_short_name {
  my ($pluggable, %args) = @_;
  return $args{name} . "_" . $pluggable->_suffix . 
         ($args{version} ? "-" . $args{version} . ".html"
                         : ".html");
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

The output is displayed in a frame, with the debug information on the left
and the actual page HTML as fetched at the time of the snapshot on the right.

=head1 INTERFACE 

=head2 init

Standard importation of methods into C<WWW::Mechanize::Pluggable>.

=head2 snapshots_to($dir)

Requires a directory to which the snapshots will be taken. 
To separate different runs, a subdirectory of this directory
will be created, using a human-readable form of the current
time as part of the name.

If this method is not called prior to the use of C<snapshot>,
the system default temporary file directory is used. If no
such directory is defined in the TMP or TMPDIR environment
variables, C<snapshots_to> dies.

=head2 snapshot

Takes a snapshot of the current state of the C<WWW::Mechanize> object
contained in the C<WWW::Mechanize::Pluggable> object.

=head1 DIAGNOSTICS

=over

=item C<< No TMPDIR/TEMP defined on this system! >>

You called C<snapshots_to> without a temporary directory,
but no system temporary directory name was available to the
program. Either call C<snapshots_to> with a writeable 
directory name, or set the TMP or TMPDIR environment 
variable to reflect the desired name.

=item C<< Couldn't create directory %s: %s >>

The program couldn't create the directory you
specified. A diagnostic follows the colon to 
help you find out why not.

=item C<< %s is not a directory >>

The argument you supplied to C<snapshots_to>
is not a directory.

=item C<< No HTML output file name supplied >>

Internal error: C<_build_file> wasn't given a 
file into which output is to be saved. Please
contact the author.

=item C<< No customization hash supplied >>

Internal error: C<_build_file> was not supplied
with the information to fill out the template.
Please contact the author.

=item C<< Nonexistent template %s >>

Internal error: C<_build_file> was supplied
with a bad file template. Please contact the
author.

=item C<< Can't write to %s file %s: $! >>

We attempted to take a snapshot, but we couldn't write the file to
the selected temporary directory. The contents of C<$!> are appended
to try to diagnose the error further.

=back

=head1 CONFIGURATION AND ENVIRONMENT

WWW::Mechanize::Plugin::Snapshot requires no configuration files.

It needs the C<TMP> or C<TMPDIR> environment variable to select the
system temporary directory if no argument is supplied to C<snapshots_to>.

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
