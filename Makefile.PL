use 5.008;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'WWW::Mechanize::Plugin::Snapshot',
    AUTHOR              => 'Joe McMahon <mcmahon@yahoo-inc.com >',
    VERSION_FROM        => 'lib/WWW/Mechanize/Plugin/Snapshot.pm',
    ABSTRACT_FROM       => 'lib/WWW/Mechanize/Plugin/Snapshot.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'Data::Dumper' => 0,
        'Text::Template' => 0,
        'File::Path' => 0,
        'WWW::Mechanize::Pluggable'    => 0.09,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'WWW-Mechanize-Plugin-Snapshot-*' },
);
