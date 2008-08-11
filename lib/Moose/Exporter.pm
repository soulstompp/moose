package Moose::Exporter;

use strict;
use warnings;

use Class::MOP;
use List::MoreUtils qw( uniq );
use Sub::Exporter;


my %EXPORT_SPEC;

sub build_import_methods {
    my $class = shift;
    my %args  = @_;

    my $exporting_package = caller();

    $EXPORT_SPEC{$exporting_package} = \%args;

    my @exports_from = $class->_follow_also( $exporting_package );

    my $exports
        = $class->_process_exports( $exporting_package, @exports_from );

    my $exporter = Sub::Exporter::build_exporter(
        {
            exports => $exports,
            groups  => { default => [':all'] }
        }
    );

    # $args{_export_to_main} exists for backwards compat, because
    # Moose::Util::TypeConstraints did export to main (unlike Moose &
    # Moose::Role).
    my $import = $class->_make_import_sub( $exporter, \@exports_from, $args{_export_to_main} );

    my $unimport = $class->_make_unimport_sub( \@exports_from, [ keys %{$exports} ] );

    no strict 'refs';
    *{ $exporting_package . '::import' }   = $import;
    *{ $exporting_package . '::unimport' } = $unimport;
}

{
    my %seen;

    sub _follow_also {
        my $class             = shift;
        my $exporting_package = shift;

        %seen = ( $exporting_package => 1 );

        return uniq( _follow_also_real($exporting_package) );
    }

    sub _follow_also_real {
        my $exporting_package = shift;

        die "Package in also ($exporting_package) does not seem to use MooseX::Exporter"
            unless exists $EXPORT_SPEC{$exporting_package};

        my $also = $EXPORT_SPEC{$exporting_package}{also};

        return unless defined $also;

        my @also = ref $also ? @{$also} : $also;

        for my $package (@also)
        {
            die "Circular reference in also parameter to MooseX::Exporter between $exporting_package and $package"
                if $seen{$package};

            $seen{$package} = 1;
        }

        return @also, map { _follow_also_real($_) } @also;
    }
}

sub _process_exports {
    my $class    = shift;
    my @packages = @_;

    my %exports;

    for my $package (@packages) {
        my $args = $EXPORT_SPEC{$package}
            or die "The $package package does not use Moose::Exporter\n";

        for my $name ( @{ $args->{with_caller} } ) {
            my $sub = do {
                no strict 'refs';
                \&{ $package . '::' . $name };
            };

            $exports{$name} = $class->_make_wrapped_sub(
                $package,
                $name,
                $sub
            );
        }

        for my $name ( @{ $args->{as_is} } ) {
            my $sub;

            if ( ref $name ) {
                $sub  = $name;
                $name = ( Class::MOP::get_code_info($name) )[1];
            }
            else {
                $sub = do {
                    no strict 'refs';
                    \&{ $package . '::' . $name };
                };
            }

            $exports{$name} = sub {$sub};
        }
    }

    return \%exports;
}

{
    # This variable gets closed over in each export _generator_. Then
    # in the generator we grab the value and close over it _again_ in
    # the real export, so it gets captured each time the generator
    # runs.
    #
    # In the meantime, we arrange for the import method we generate to
    # set this variable to the caller each time it is called.
    #
    # This is all a bit confusing, but it works.
    my $CALLER;

    sub _make_wrapped_sub {
        my $class             = shift;
        my $exporting_package = shift;
        my $name              = shift;
        my $sub               = shift;

        # We need to set the package at import time, so that when
        # package Foo imports has(), we capture "Foo" as the
        # package. This lets other packages call Foo::has() and get
        # the right package. This is done for backwards compatibility
        # with existing production code, not because this is a good
        # idea ;)
        return sub {
            my $caller = $CALLER;
            Class::MOP::subname( $exporting_package . '::'
                    . $name => sub { $sub->( $caller, @_ ) } );
        };
    }

    sub _make_import_sub {
        shift;
        my $exporter       = shift;
        my $exports_from   = shift;
        my $export_to_main = shift;

        return sub {

            # It's important to leave @_ as-is for the benefit of
            # Sub::Exporter.
            my $class = $_[0];

            $CALLER = Moose::Exporter::_get_caller(@_);

            # this works because both pragmas set $^H (see perldoc
            # perlvar) which affects the current compilation -
            # i.e. the file who use'd us - which is why we don't need
            # to do anything special to make it affect that file
            # rather than this one (which is already compiled)

            strict->import;
            warnings->import;

            # we should never export to main
            if ( $CALLER eq 'main' && ! $export_to_main ) {
                warn
                    qq{$class does not export its sugar to the 'main' package.\n};
                return;
            }

            for my $c (grep { $_->can('init_meta') } $class, @{$exports_from} ) {

                $c->init_meta( for_class => $CALLER );
            }

            goto $exporter;
        };
    }
}

sub _get_caller {
    # 1 extra level because it's called by import so there's a layer
    # of indirection
    my $offset = 1;

    return
          ( ref $_[1] && defined $_[1]->{into} ) ? $_[1]->{into}
        : ( ref $_[1] && defined $_[1]->{into_level} )
        ? caller( $offset + $_[1]->{into_level} )
        : caller($offset);
}

sub _make_unimport_sub {
    shift;
    my $sources  = shift;
    my $keywords = shift;

    return sub {
        my $class  = shift;
        my $caller = scalar caller();
        Moose::Exporter->_remove_keywords(
            $caller,
            [ $class, @{$sources} ],
            $keywords
        );
    };
}

sub _remove_keywords {
    shift;
    my $package  = shift;
    my $sources  = shift;
    my $keywords = shift;

    my %sources = map { $_ => 1 } @{$sources};

    no strict 'refs';

    # loop through the keywords ...
    foreach my $name ( @{$keywords} ) {

        # if we find one ...
        if ( defined &{ $package . '::' . $name } ) {
            my $keyword = \&{ $package . '::' . $name };

            # make sure it is from us
            my ($pkg_name) = Class::MOP::get_code_info($keyword);
            next unless $sources{$pkg_name};

            # and if it is from us, then undef the slot
            delete ${ $package . '::' }{$name};
        }
    }
}

1;

__END__

=head1 NAME

Moose::Exporter - make an import() and unimport() just like Moose.pm

=head1 SYNOPSIS

  package MyApp::Moose;

  use strict;
  use warnings;

  use Moose ();
  use Moose::Exporter;

  Moose::Exporter->build_export_methods(
      export         => [ 'sugar1', 'sugar2', \&Some::Random::thing ],
      init_meta_args => { metaclass_class => 'MyApp::Meta::Class' ],
  );

  # then later ...
  package MyApp::User;

  use MyApp::Moose;

  has 'name';
  sugar1 'do your thing';
  thing;

  no MyApp::Moose;

=head1 DESCRIPTION

This module encapsulates the logic to export sugar functions like
C<Moose.pm>. It does this by building custom C<import> and C<unimport>
methods for your module, based on a spec your provide.

It also lets your "stack" Moose-alike modules so you can export
Moose's sugar as well as your own, along with sugar from any random
C<MooseX> module, as long as they all use C<Moose::Exporter>.

=head1 METHODS

This module provides exactly one public method:

=head2 Moose::Exporter->build_import_methods(...)

When you call this method, C<Moose::Exporter> build custom C<import>
and C<unimport> methods for your module. The import method will export
the functions you specify, and you can also tell it to export
functions exported by some other module (like C<Moose.pm>).

The C<unimport> method cleans the callers namespace of all the
exported functions.

This method accepts the following parameters:

=over 4

=item * with_caller => [ ... ]

This a list of function I<names only> to be exported wrapped and then
exported. The wrapper will pass the name of the calling package as the
first argument to the function. Many sugar functions need to know
their caller so they can get the calling package's metaclass object.

=item * as_is => [ ... ]

This a list of function names or sub references to be exported
as-is. You can identify a subroutine by reference, which is handy to
re-export some other module's functions directly by reference
(C<\&Some::Package::function>).

=item * also => $name or \@names

This is a list of modules which contain functions that the caller
wants to export. These modules must also use C<Moose::Exporter>. The
most common use case will be to export the functions from C<Moose.pm>.

C<Moose::Exporter> also makes sure all these functions get removed
when C<unimport> is called.

=back

=head1 IMPORTING AND init_meta

If you want to set an alternative base object class or metaclass
class, simply define an C<init_meta> method in your class. The
C<import> method that C<Moose::Exporter> generates for you will call
this method (if it exists). It will always pass the caller to this
method via the C<for_class> parameter.

Most of the time, your C<init_meta> method will probably just call C<<
Moose->init_meta >> to do the real work:

  sub init_meta {
      shift; # our class name
      return Moose->init_meta( @_, metaclass => 'My::Metaclass' );
  }

=head1 AUTHOR

Dave Rolsky E<lt>autarch@urth.orgE<gt>

This is largely a reworking of code in Moose.pm originally written by
Stevan Little and others.

=head1 COPYRIGHT AND LICENSE

Copyright 2008 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut