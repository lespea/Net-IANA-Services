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
use YAML::XS            qw/ DumpFile  LoadFile /;


#  Subroutine declaration
sub escape_curly_quote;
sub gen_exports;
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

#  Control how our module works
const  my $ZIP_YAML => 0;

#  Used to parse the yml files
const  my $IN_FILENAME      => 'service_mapping.yml';
const  my $INFO_FOR_SERVICE => LoadFile $IN_FILENAME;

#  Used to build the globals
const  my $GEN_ASSEMBLER => sub {return Regexp::Assemble->new( flags => q{i} )};

#  General
const  my $ALL           => q{all};
const  my $NOT_YET_IMPL  => q{#This feature is not yet implemented!};
const  my $DUMP_REF_NAME => q{_HASHES_REF};

#  Folders we use
const  my $DOC_DIR   => q{.};
const  my $LIB_DIR   => q{lib};
const  my $SHARE_DIR => q{share};

#  Extra documentation
const  my $DOC_SERVICES_FILENAME => q{Service_Descriptions.pod};
const  my $DOC_SERVICES_FULLNAME => File::Spec->catfile( $DOC_DIR, $DOC_SERVICES_FILENAME );

#  YAML filenames
const  my $HASHES_YAML_FILENAME_YML => q{services_hashes_dump.yml};
const  my $HASHES_YAML_FILENAME_ZIP => $HASHES_YAML_FILENAME_YML . q{.zip};
const  my $HASHES_YAML_FILENAME     => $ZIP_YAML ? $HASHES_YAML_FILENAME_ZIP : $HASHES_YAML_FILENAME_YML;

#  YAML file paths
const  my $HASHES_YAML_FULLNAME_YML => File::Spec->catfile( $SHARE_DIR, $HASHES_YAML_FILENAME_YML );
const  my $HASHES_YAML_FULLNAME_ZIP => File::Spec->catfile( $SHARE_DIR, $HASHES_YAML_FILENAME_ZIP );
const  my $HASHES_YAML_FULLNAME     => $ZIP_YAML ? $HASHES_YAML_FULLNAME_ZIP : $HASHES_YAML_FULLNAME_YML;

#  Name info
const  my @OUTPUT_MODULE_NAMESPACES => qw/ Net  IANA /;
const  my $OUTPUT_MODULE_NAME       => q{Services};
const  my $PACKAGE_NAME             => join q{::}, @OUTPUT_MODULE_NAMESPACES, $OUTPUT_MODULE_NAME;
const  my $DIST_NAME                => join q{-},  @OUTPUT_MODULE_NAMESPACES, $OUTPUT_MODULE_NAME;

#  Module path/name
const  my $OUTPUT_MODULE_PATH     => File::Spec->catdir( $LIB_DIR, @OUTPUT_MODULE_NAMESPACES );
const  my $OUTPUT_MODULE_FILENAME => $OUTPUT_MODULE_NAME . q{.pm};
const  my $OUTPUT_MODULE_FULLPATH => File::Spec->catfile( $OUTPUT_MODULE_PATH, $OUTPUT_MODULE_FILENAME );



#  Globals
my (%all_ports, %all_protocols);
my (%ports_for_service, %ports_for_service_proto, %services_for_port, %services_for_port_proto );
my %all_services = map {$_ => 1} keys %$INFO_FOR_SERVICE;
my %assembler_for = (
    $ALL => {
        service => $GEN_ASSEMBLER->(),
        port    => $GEN_ASSEMBLER->(),
    },
);
my %name_for = (
    'hash' => {
        'service_info'  => make_const_name(qw/ IANA  hash  info  for  service /),

        'ports'         => make_const_name(qw/ IANA  hash  services  for  port        /),
        'ports_proto'   => make_const_name(qw/ IANA  hash  services  for  port  proto /),

        'service'       => make_const_name(qw/ IANA  hash  ports  for  service        /),
        'service_proto' => make_const_name(qw/ IANA  hash  ports  for  service  proto /),
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
        'info' => {
            'service' => make_sub_name(qw/ IANA  info  for  service /),
            'port'    => make_sub_name(qw/ IANA  info  for  port    /),
        },
    },
);
my @info_for_hash_type = (
    [
        'service_info',
        $INFO_FOR_SERVICE,
        <<'__END_SPRINTF'
This maps a service and a protocol to the information provided to us by IANA.

For example, C<$IANA_HASH_INFO_FOR_SERVICE->{ ssh }{ tcp }>  will give you the name, description, and note for
the ssh service over tcp.  The format of the information is a hash ref having the keys I<name>,
I<desc>, and I<note>.
__END_SPRINTF
    ],

    [
        'ports',
        \%services_for_port,
        <<'__END_SPRINTF'
This lists all of the services for the given port, irregardless of the protocol.

For example, C<$IANA_HASH_SERVICES_FOR_PORT->{ 22 }> will return C<['ssh']>.
__END_SPRINTF
    ],

    [
        'ports_proto',
        \%services_for_port_proto,
        <<'__END_SPRINTF'
This lists all of the services for the given port and protocol.

For example, C<$IANA_HASH_SERVICES_FOR_PORT_PROTO->{ 22 }{ 'tcp' }> will return C<['ssh']>.
__END_SPRINTF
    ],

    [
        'service',
        \%ports_for_service,
        <<'__END_SPRINTF'
This lists all of the ports for the given service, irregardless of the protocol.

For example, C<$IANA_HASH_PORT_FOR_SERVICES->{ 'ssh' }> will return C<[22]>.
__END_SPRINTF
    ],

    [
        'service_proto',
        \%ports_for_service_proto,
        <<'__END_SPRINTF'
This lists all of the ports for the given service, irregardless of the protocol.

For example, C<$IANA_HASH_PORT_FOR_SERVICES_PROTO->{ 'ssh' }{ 'tcp' }> will return C<[22]>.
__END_SPRINTF
    ],
);



#  Pull in the info from the yaml file and put it into the global hashes
sub populate_globals {
    my @services_doc_text = (
        q{#ABSTRACT:  Documents the services defined by IANA},
        q{},
        q{=encoding utf8},
        q{},
        q{=head1 Services},
        q{},
    );

    for  my $name_lookup  (sort keys %$INFO_FOR_SERVICE) {
        my $n = quotemeta $name_lookup;
        $assembler_for{ all }{ service }->add( quotemeta $n );

        push @services_doc_text, qq{=head2 $name_lookup\n};

        my $protocol_ref = $INFO_FOR_SERVICE->{ $name_lookup };
        for  my $protocol  (keys %$protocol_ref) {
            for  my $sub_name  (qw/ service  port /) {
                $assembler_for{ $protocol }{ $sub_name }      //= $GEN_ASSEMBLER->();
                $name_for{ regex  }{ $protocol }{ $sub_name } //= make_const_name qw/ IANA  regex  /, "${sub_name}s", $protocol;
                $name_for{ hashes }{ $protocol }{ $sub_name } //= make_const_name qw/ IANA  hash   /, "${sub_name}s", $protocol;
            }

            $all_protocols{ $protocol } = 1;
            push @services_doc_text, (
                qq{=head3 $protocol},
                q{},
                q{=over 4},
                q{},
            );

            my $port_ref = $protocol_ref->{ $protocol };
            my $i = 1;
            for  my $port  (keys $port_ref) {
                my $p = quotemeta $port;
                $all_ports{ $p } = 1;

                my $info_ref = $port_ref->{ $port };
                push @services_doc_text, (
                    qq{=item $i},
                    q{},
                    $port,
                    q{},
                    q{=over 4},
                    q{},
                    q{=item Name},
                    q{},
                    $info_ref->{name} // q{},
                    q{},
                    q{=item Description},
                    q{},
                    $info_ref->{desc} // q{},
                    q{},
                    q{=item Note},
                    q{},
                    $info_ref->{note} // q{},
                    q{},
                    q{=back},
                    q{},
                );
                $i++;

                $ports_for_service_proto{ $name_lookup }{ $protocol }{ $port        } = 1;
                $services_for_port_proto{ $port        }{ $protocol }{ $name_lookup } = 1;

                $assembler_for{ $ALL      }{ port    }->add( $p );
                $assembler_for{ $protocol }{ port    }->add( $p );
                $assembler_for{ $protocol }{ service }->add( $n );
            }

            push @services_doc_text, qq{=back\n};
        }
    }


    for  my $assembler_name  (keys %assembler_for) {
        for  my $type  (keys %{ $assembler_for{ $assembler_name } }) {
            $assembler_for{ $assembler_name }{ $type } =
                $assembler_for{ $assembler_name }{ $type }->anchor_word( 1 )->re;
        }
    }


    for  my $name  (keys %ports_for_service_proto) {
        my %ports;
        for  my $ports_ref  (values %{ $ports_for_service_proto{ $name } }) {
            $ports{ $_ } = 1  for  keys %$ports_ref;
        }
        $ports_for_service{ $name } = [sort keys %ports];
    }
    for  my $port  (keys %services_for_port_proto) {
        my %names;
        for  my $ports_ref  (values %{ $services_for_port_proto{ $port } }) {
            $names{ $_ } = 1  for  keys %$ports_ref;
        }
        $services_for_port{ $port } = [sort keys %names];
    }


    open  my $fh_doc, '>:encoding(utf8)', $DOC_SERVICES_FULLNAME;
    $fh_doc->say( join qq{\n}, @services_doc_text);
}



sub gen_exports {
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
        my $regex = $assembler_for{ $ALL }{ $sub_name };
        my $name  = $name_for{ regex }{ $ALL }{ $sub_name };

        push @regex_defs, gen_regex $name, $regex, <<"__END_SPRINTF" =~ s/\v+\z//xmsgr;
Regular expression to match any ${sub_name}, irregardless of which protocol it goes over.

While this is a highly optimized regex, you should consider using the hashes or subroutines instead
as they are much better.  This is merely for your convenience.

Case is ignored and the protocol must match on a word boundary!
__END_SPRINTF
    }


    for  my $sub_name  (sort qw/ service  port /) {
        for  my $protocol  (sort keys %all_protocols) {
            my $regex = $assembler_for{ $protocol }{ $sub_name };
            my $name  = $name_for{ regex }{ $protocol }{ $sub_name };

            push @regex_defs, gen_regex $name, $regex, <<"__END_SPRINTF" =~ s/\v+\z//xmsgr;
Regular expression to match any ${sub_name} that is known to work over ${protocol}.

While this is a highly optimized regex, you should consider using the hashes or subroutines instead
as they are much better.  This is merely for your convenience.

Case is ignored and the protocol must match on a word boundary!
__END_SPRINTF
        }
    }

    return join qq{\n\n\n}, @regex_defs;
}



sub gen_hash_ref {
    my ($name, $hash_name, $documentation) = @_;
    #my $hash_txt = Dumper( $hash_ref );
    #$hash_txt =~ s/\v+\z//xmsg;
    my $hash_def = sprintf <<'__END_SPRINTF', uc $name, $DUMP_REF_NAME, $hash_name, $documentation =~ s/\v+\z//xmsgr;
=const %1$s

%4$s

=cut

our %1$s = $%2$s->{ q{%3$s} };
__END_SPRINTF

    return $hash_def;
}



sub gen_hash_refs {
    my @hash_defs;
    my %hash_dump;

    for  my $info_ref  (@info_for_hash_type) {
        my ($name_ref, $hash, $documentation) = @$info_ref;
        my $name = $name_for{ hash }{ $name_ref };
        push @hash_defs, gen_hash_ref $name, $name_ref, $documentation;
        $hash_dump{ $name_ref } = $hash;
    }

    remove_tree $SHARE_DIR;
    make_path  $SHARE_DIR;

    open  my $fh_out, '>:encoding(utf8)', $HASHES_YAML_FULLNAME;
    DumpFile $fh_out, \%hash_dump;

    return join qq{\n\n\n}, @hash_defs;
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



sub gen_consts {
    return "my \$$DUMP_REF_NAME = LoadFile dist_file q{$DIST_NAME}, q{$HASHES_YAML_FILENAME};";
}



sub gen_module_text {
    return sprintf <<'__END_SPRINTF', $PACKAGE_NAME, gen_exports, gen_consts, gen_regexes, gen_hash_refs, gen_subroutines;
use strict;
use warnings;
use utf8;

package %1$s;

#ABSTRACT:  Makes working with named ip services easier


#  Import needed modules
use YAML::Any qw/ LoadFile /;
use File::ShareDir qw/ dist_file /;


#  Export our vars/subs
%2$s


#  Constants
%3$s


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
    my $service = 'https';
    my $port    = 22;


    #  How the regexes work
    $service =~ $IANA_REGEX_SERVICES;      # 1
    $service =~ $IANA_REGEX_SERVICES_UDP;  # 1
    $port    =~ $IANA_REGEX_PORTS;         # 1
    $port    =~ $IANA_REGEX_PORTS_TCP;     # 1


    #  Demonstration of the service hashes
    $IANA_HASH_INFO_FOR_SERVICE->{ $service }{ tcp }; # { name => 'HTTPS', desc => 'https description', note => 'note about https' }

    $IANA_HASH_PORTS_FOR_SERVICE      ->{ $service }; # [qw/ 443 /]              --  List of all the services that use that port
    $IANA_HASH_PORTS_FOR_SERVICE_PROTO->{ $service }; # {tcp => qw/ 443 /, etc}  --  Hash of all the protocol/services that use that port

    #  Demonstration  of the port hashes
    $IANA_HASH_SERVICES_FOR_PORT      ->{ $port };    # [qw/ ssh /]         --  List of all the services that use that port
    $IANA_HASH_SERVICES_FOR_PORT_PROTO->{ $port };    # {tcp => qw/ ssh /}  --  Hash of all the protocol/services that use that port


    #  Demonstration of the service/port checker subroutines
    iana_has_service( $service        );  # 1
    iana_has_service( $service, 'tcp' );  # 1
    iana_has_service( $service, 'bla' );  # 0
    iana_has_port   ( $port           );  # 1

    #  Demonstration of the service/port info subroutines
    iana_info_for_service( $service        );  # Returns a hash of the different protocol definitions
    iana_info_for_service( $service, 'tcp' );  # Returns a hash of the info for https over tcp
    iana_info_for_port   ( $port           );  # Returns a list all services that go over that port (regardless of the protocol)
    iana_info_for_port   ( $port, 'tcp'    );  # Returns a list all services that go over that port on tcp

=head1 DESCRIPTION

Working with named services can be a pain when you want to go back and forth between the port and
its real name.  This module helps alleviate some of those pain points by defining some helping
hashes, functions, and regular expressions.

=cut




#####################
#  Regex constants  #
#####################


%4$s




####################
#  Hash constants  #
####################


%5$s




##########################
#  Subroutine constants  #
##########################


%6$s




#  Happy ending
1;
__END_SPRINTF
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
