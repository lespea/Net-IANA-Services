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
use Data::Traverse      qw/ traverse /;
use File::Path          qw/ make_path  remove_tree /;
use File::Spec;
use Regexp::Assemble;
use YAML::XS            qw/ LoadFile /;


#  Subroutine declaration
sub escape_curly_quote;
sub gen_imports;
sub gen_hash_ref;
sub gen_hash_refs;
sub gen_module;
sub gen_module_text;
sub gen_regex;
sub gen_regexes;
sub gen_subroutine;
sub gen_subroutines;
sub indent_paragraph;
sub make_const_name;
sub make_sub_name;
sub populate_globals;


#  Constants
#
#  Used to parse the yml files
const  my $IN_FILENAME      => 'service_mapping.yml';
const  my $INFO_FOR_SERVICE => LoadFile $IN_FILENAME;

#  Used to build the globals
const  my $GEN_ASSEMBLER => sub {return Regexp::Assemble->new( flags => q{i} )};

#  General
const  my $ALL          => q{all};
const  my $NOT_YET_IMPL => q{#This feature is not yet implemented!};

#  Strings for the generated module
const  my $LIB_DIR                  => q{lib};
const  my @OUTPUT_MODULE_NAMESPACES => qw/ Net  IANA /;
const  my $OUTPUT_MODULE_NAME       => q{Services};
const  my $OUTPUT_MODULE_PATH       => File::Spec->catdir( $LIB_DIR, @OUTPUT_MODULE_NAMESPACES );
const  my $OUTPUT_MODULE_FILENAME   => $OUTPUT_MODULE_NAME . q{.pm};
const  my $OUTPUT_MODULE_FULLPATH   => File::Spec->catfile( $OUTPUT_MODULE_PATH, $OUTPUT_MODULE_FILENAME );
const  my $PACKAGE_NAME             => join q{::}, @OUTPUT_MODULE_NAMESPACES, $OUTPUT_MODULE_NAME;



#  Globals
my (%all_ports, %all_protocols);
my %all_services = map {$_ => 1} keys %$INFO_FOR_SERVICE;
my %assembler_for = (
    $ALL => {
        service => $GEN_ASSEMBLER->(),
        port    => $GEN_ASSEMBLER->(),
    },
);
my %name_for = (
    'hash' => {
        'service'     => make_const_name(qw/ IANA  hash  services     /),
        'ports'       => make_const_name(qw/ IANA  hash  ports        /),
        'ports_proto' => make_const_name(qw/ IANA  hash  ports  proto /),
    },
    'regex' => {
        $ALL => {
            'service' => make_const_name(qw/ IANA  regex  services /),
            'port'    => make_const_name(qw/ IANA  regex  ports    /),
        },
    },
    'sub' => {
        'has' => {
            'service' => make_sub_name(qw/ IANA  has  service /),
            'port'    => make_sub_name(qw/ IANA  has  port    /),
        },
        'has' => {
            'service' => make_sub_name(qw/ IANA  info  for  service /),
            'port'    => make_sub_name(qw/ IANA  info  for  port    /),
        },
    },
);



sub gen_imports {
    my (@hashes, @regexes, @subs);

    traverse { push @hashes,  $b} $name_for{ 'hash'  };
    traverse { push @regexes, $b} $name_for{ 'regex' };
    traverse { push @subs,    $b} $name_for{ 'sub'   };

    my $TAG_INDENT  = q{ } x 8;
    my $ITEM_INDENT = q{ } x 12;

    my @sprintf_args =
        map { sprintf( "qw(\n$ITEM_INDENT%s\n$TAG_INDENT)", join qq{\n$ITEM_INDENT}, @$_ )}
        [sort @hashes],
        [sort @regexes],
        [sort @subs],
    ;

    die unless @hashes;
    die unless @regexes;
    die unless @subs;

    return sprintf <<'__END_SPRINTF', @sprintf_args;
use Exporter::Easy (
    TAGS => [
        hashes => [%1$s],

        regexes => [%2$s],

        subs => [%3$s],

        all => [qw/ :hashes  :regexes  :subs /],
    ],
    VARS => 1,
);
__END_SPRINTF
}



sub gen_regex {
    my ($name, $regex_obj, $documentation) = @_;
    my $regex_def = sprintf <<'__END_SPRINTF', uc $name, scalar( Dumper( $regex_obj ) ) =~ s/\v+//xmsgr, $documentation;
=const %1$s

%3$s

=cut

our %1$s = %2$s;  ## no critic(RegularExpressions)
__END_SPRINTF

    return $regex_def;
}
sub gen_regexes {
    my @regex_defs;
    for  my $sub_name  (sort qw/ service  port /) {
        for  my $protocol  (sort keys %all_protocols) {
            my $regex = $assembler_for{ $protocol }{ $sub_name };
            my $name  = $name_for{ regex }{ $protocol }{ $sub_name };

            push @regex_defs, gen_regex $name, $regex, <<"__END_SPRINTF" =~ s/\v+\z//xmsgr;
Regular expression to match any $sub_name that is known to work over $protocol.

While this is a highly optimized regex, you should consider using the hashes or subroutines instead
as they are much better.  This is merely for your convenience.

Case is ignored and the protocol must match on a word boundary!
__END_SPRINTF
        }
    }

    return join qq{\n\n\n}, @regex_defs;
}



sub gen_hash_ref {
    my ($name, $hash_ref, $documentation) = @_;
    my $hash_def = sprintf <<'__END_SPRINTF', uc $name, scalar( Dumper( $hash_ref ) ), $documentation;
=const %1$s

%3$s

=cut

our %1$s = %2$s;
__END_SPRINTF

    return $hash_def;
}
sub gen_hash_refs {
    return $NOT_YET_IMPL;
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
sub gen_subroutines {
    return $NOT_YET_IMPL;
}



sub gen_module {
    my $txt = gen_module_text;

    remove_tree $LIB_DIR;
    make_path   $OUTPUT_MODULE_PATH;

    open  my $fh, '>:encoding(utf8)', $OUTPUT_MODULE_FULLPATH;
    $fh->say( $txt );
}



sub gen_module_text {
    return sprintf <<'__END_SPRINTF', $PACKAGE_NAME, gen_imports, gen_regexes, gen_hash_refs, gen_subroutines;
use strict;
use warnings;
use utf8;

package %1$s;

#ABSTRACT:  Makes working with named ip services easier

%2$s


=encoding utf8

=for Pod::Coverage

=head1 SYNOPSIS

    #  Load the module
    use Net::IANA::Services (
        #  Import the regular expressions to test for services/ports
        ':regexes',

        #  Import the hashes to test for services/ports or get info for a service/protocol
        ':hashes',

        #  Import the subroutines to test for services/ports or get info for a service/protocol
        ':subs',

        #  Alternatively this loads everything
        #  ':all',
    );


    #  Declare some strings to test
    my $service = 'https',
    my $port    = 22,


    #  How the regexes work
    $service =~ $IANA_REGEX_SERVICES;       # 1
    $service =~ $IANA_REGEX_SERVICES_TCP;   # 1
    $port    =~ $IANA_REGEX_PORTS;          # 1
    $port    =~ $IANA_REGEX_PORTS_TCP;      # 1


    #  Demonstration of the service hashes
    $IANA_HASH_SERVICES->{ $service }{ tcp };   # { name => 'HTTPS', desc => 'https description', note => 'note about https' }

    #  Demonstration  of the port hashes
    $IANA_HASH_PORTS{ $port };                  # [qw/ ssh /]         --  List of all the services that use that port
    $IANA_HASH_PORTS_PROTO{ $port };            # {tcp => qw/ ssh /}  --  Hash of all the protocol/services that use that port


    #  Demonstration of the service/port checker subroutines
    iana_has_service( $service        );    # 1
    iana_has_service( $service, 'tcp' );    # 1
    iana_has_service( $service, 'bla' );    # 0
    iana_has_port   ( $port           );    # 1

    #  Demonstration of the service/port info subroutines
    iana_info_for_service( $service        );   #  Returns a hash of the different protocol definitions
    iana_info_for_service( $service, 'tcp' );   #  Returns a hash of the info for https over tcp
    iana_info_for_port   ( $port           );   #  Returns a list all services that go over that port (regardless of the protocol)
    iana_info_for_port   ( $port, 'tcp'    );   #  Returns a list all services that go over that port on tcp

=head1 DESCRIPTION

Working with named services can be a pain when you want to go back and forth between the port and
its real name.  This module helps alleviate some of those pain points by defining some helping
hashes, functions, and regular expressions.

=cut




#####################
#  Regex constants  #
#####################


%3$s




####################
#  Hash constants  #
####################


%4$s




##########################
#  Subroutine constants  #
##########################


%5$s




#  Happy ending
1;
__END_SPRINTF
}



#  Pull in the info from the yaml file and put it into the global hashes
sub populate_globals {
    for  my $name_lookup  (sort keys %$INFO_FOR_SERVICE) {
        my $n = quotemeta $name_lookup;
        $assembler_for{ all }{ service }->add( quotemeta $n );

        my $protocol_ref = $INFO_FOR_SERVICE->{ $name_lookup };
        for  my $protocol  (keys %$protocol_ref) {
            for  my $sub_name  (qw/ service  port /) {
                $assembler_for{ $protocol }{ $sub_name }      //= $GEN_ASSEMBLER->();
                $name_for{ regex  }{ $protocol }{ $sub_name } //= make_const_name qw/ IANA  regex  /, "${sub_name}s", $protocol;
                $name_for{ hashes }{ $protocol }{ $sub_name } //= make_const_name qw/ IANA  hash   /, "${sub_name}s", $protocol;
            }

            $all_protocols{ $protocol } = 1;

            my $port_ref = $protocol_ref->{ $protocol };
            for  my $port  (keys $port_ref) {
                my $p = quotemeta $port;
                $all_ports{ $p } = 1;

                $assembler_for{ $ALL      }{ port    }->add( $p );
                $assembler_for{ $protocol }{ port    }->add( $p );
                $assembler_for{ $protocol }{ service }->add( $n );
            }
        }
    }

    for  my $assembler_name  (keys %assembler_for) {
        for  my $type  (keys %{ $assembler_for{ $assembler_name } }) {
            $assembler_for{ $assembler_name }{ $type } =
                $assembler_for{ $assembler_name }{ $type }->anchor_word( 1 )->re;
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



#  Make a name for a sub/regex/etc (simple for now; may change)
sub make_const_name {
    my (@parts) = @_;
    return sprintf '$%s', uc join q{_}, @parts;
}



#  Make a name for a sub/regex/etc (simple for now; may change)
sub make_sub_name {
    my (@parts) = @_;
    return lc join q{_}, @parts;
}



sub go {
    populate_globals;
    gen_module;
}
go;
