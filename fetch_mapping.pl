#!/usr/bin/env perl

use Modern::Perl qw/ 2013 /;

use autodie;
use autovivification;
use Const::Fast;
use Data::Printer;

use List::MoreUtils qw/ all /;
use XML::Twig;
use YAML     qw/ DumpFile /;

const  my $xml_uri      => q{http://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xml};
const  my $out_filename => 'service_mapping.yml';

const  my $CLEANER_PHRASE => quotemeta q{IANA assigned this well-formed service name as a replacement for };
const  my $CLEANER => qr{
    (?:
        [\v\h\s]+
      |
        \\n
    )*
    $CLEANER_PHRASE
    ["]
    [^"]+
    ["]
    [.]?
    [\v\h\s]*
}xmsi;

my $info_for_service;
my $twig = XML::Twig->new(
    twig_handlers => {
        record => sub {
            my $twig = $_;
            if (all {$twig->has_child( $_ )} qw/ name  protocol  number /) {
                my %info = (
                    name => $twig->first_child_text( 'name'        ),
                    desc => $twig->first_child_text( 'description' ) =~ s/$CLEANER//xmsirg,
                    note => $twig->first_child_text( 'note'        ) =~ s/$CLEANER//xmsirg,
                );

                $info_for_service
                    -> { lc $twig->first_child_text( 'name'     ) }
                    -> { lc $twig->first_child_text( 'protocol' ) }
                    -> {    $twig->first_child_text( 'number'   ) }
                        = \%info;
            }
        }
    }
);
$twig->parseurl( $xml_uri );

#p %info_for_service;

open  my $fh_out, '>:encoding(utf8)', $out_filename;
binmode $fh_out;
DumpFile $fh_out, $info_for_service;
