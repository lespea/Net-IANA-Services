#!/usr/bin/env perl

#  This is the 21st century
use Modern::Perl qw/ 2012 /;
use utf8;


#  General modules
use autodie;
use autovivification;
use Const::Fast;
use Data::Printer;

#  Used to serialize some things
use Data::Dumper;
$Data::Dumper::Terse    = 1;
$Data::Dumper::Indent   = 3;
$Data::Dumper::Sortkeys = 1;

#  Specific modules needed by this script
use File::Spec;
use Regexp::Assemble;
use YAML::XS qw/ LoadFile /;


#  Subroutine declaration
sub escape_curly_quote;
sub gen_regex;
sub gen_subroutine;
sub indent_paragraph;
sub populate_globals;


#  Constants
#
#  Used to parse the yml files
const  my $IN_FILENAME      => 'service_mapping.yml';
const  my $INFO_FOR_SERVICE => LoadFile $IN_FILENAME;

#  Used to build the globals
const  my $GEN_ASSEMBLER => sub {return Regexp::Assemble->new( flags => q{i} )};

#  Strings for the generated module
const  my @OUTPUT_MODULE_NAMESPACES => qw/ Net  IANA /;
const  my $OUTPUT_MODULE_NAME       => q{Services};
const  my $OUTPUT_MODULE_PATH       => File::Spec->catdir( @OUTPUT_MODULE_NAMESPACES );
const  my $OUTPUT_MODULE_FILENAME   => $OUTPUT_MODULE_NAME . q{.pm};
const  my $OUTPUT_MODULE_FULEPATH   => File::Spec->catfile( $OUTPUT_MODULE_PATH, $OUTPUT_MODULE_NAME );



#  Globals
my (%all_ports, %all_protocols);
my %all_services = map {$_ => 1} keys %$INFO_FOR_SERVICE;
my %assembler_for = (
    all => {
        service => $GEN_ASSEMBLER->(),
        port    => $GEN_ASSEMBLER->(),
    },
);



sub gen_regex {
    my ($name, $regex_obj, $documentation) = @_;
    my $regex_def = sprintf <<'__END_SPRINTF', $name, scalar( Dumper( $regex_obj ) ), $documentation;
=const %1$s

%3$s

=cut

our $%1$s = %2$s;
__END_SPRINTF

    return $regex_def;
}



sub gen_hash_ref {
    my ($name, $hash_ref, $documentation) = @_;
    my $hash_def = sprintf <<'__END_SPRINTF', $name, scalar( Dumper( $hash_ref ) ), $documentation;
=const %1$s

%3$s

=cut

our $%1$s = %2$s;
__END_SPRINTF

    return $hash_def;
}



sub gen_subroutine {
    my ($name, $body, $documentation) = @_;
    my $sub_def = sprintf <<'__END_SPRINTF', $name, indent_paragraph( $body, 4 ), $documentation;
=method %1$s

%3$s

=cut

sub %1$s {
%2$s
}
__END_SPRINTF

    return $sub_def;
}



#  Pull in the info from the yaml file and put it into the global hashes
sub populate_globals {
    for  my $name_lookup  (sort keys %$INFO_FOR_SERVICE) {
        my $n = quotemeta $name_lookup;
        $assembler_for{ all }{ service }->add( quotemeta $n );

        my $protocol_ref = $INFO_FOR_SERVICE->{ $name_lookup };
        for  my $protocol  (keys %$protocol_ref) {
            $assembler_for{ $protocol }{ $_ } //= $GEN_ASSEMBLER->()  for  qw/ service  port /;
            $all_protocols{ $protocol } = 1;

            my $port_ref = $protocol_ref->{ $protocol };
            for  my $port  (keys $port_ref) {
                my $p = quotemeta $port;
                $all_ports{ $p } = 1;

                $assembler_for{ all       }{ port    }->add( $p );
                $assembler_for{ $protocol }{ port    }->add( $p );
                $assembler_for{ $protocol }{ service }->add( $n );
            }
        }
    }

    for  my $assembler_name  (keys %assembler_for) {
        for  my $type  (keys %{ $assembler_for{ $assembler_name } }) {
            $assembler_for{ $assembler_name }{ $type } = $assembler_for{ $assembler_name }{ $type }->anchor_word( 1 )->re;
        }
    }
}



#  Escape a string so we can insert it into a q{} declaration in the generated module
sub escape_curly_quote {
    my ($txt) = @_;
    return $txt =~ s/(?=[\\{}])/\\/xmsgr;
}



#  Move every line over the provided number of spaces
sub indent_paragraph {
    my ($txt, $spaces) = @_;
    my $indent_txt = q{ } x $spaces;
    return $txt =~ s/ ^ /$indent_txt/xmsgr;
}



sub go {
    populate_globals;
}
go;
