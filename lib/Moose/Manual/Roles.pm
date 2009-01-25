=pod

=head1 NAME

Moose::Manual::Roles - Roles, an Alternative to Deep Hierarchies and Base Classes

=head1 WHAT IS A ROLE?

A role is something that classes do. Usually, a role encapsulates some
piece of behavior or state that can be shared between classes. It is
important to understand that I<roles are not classes>. Roles do not
participate in inheritance, and a role cannot be instantiated.

Instead, a role is I<composed> into a class. In practical terms, this
means that all of the methods and attributes defined in a role are
added directly to (we sometimes say ("flattened into") the class that
consumes the role. These attributes and methods then show up in the
class as if they were defined directly in the class.

Moose roles are similar to mixins or interfaces in other languages.

Besides defining their own methods and attributes, roles can also
require that the consuming class define certain methods of its
own. You could have a role that consisted only of a list of required
methods, in which case the role would be very much like a Java
interface.

=head1 A SIMPLE ROLE

Creating a role looks a lot like creating a Moose class:

  package Breakable;

  use Moose::Role;

  has 'is_broken' => (
      is  => 'rw',
      isa => 'Bool',
  );

  sub break {
      my $self = shift;

      print "I broke\n";

      $self->is_broken(1);
  }

Except for our use of C<Moose::Role>, this looks just like a class
definition with Moose. However, this is not a class, and it cannot be
instantiated.

Instead, its attributes and methods will be composed into classes
which use the role:

  package Car;

  use Moose;

  with 'Breakable';

  has 'engine' => (
      is  => 'ro',
      isa => 'Engine',
  );

The C<with> function composes roles into a class. Once that is done,
the C<Car> class has an C<is_broken> attribute and a C<break>
method. The C<Car> class also C<does('Breakable')>:

  my $car = Car->new( engine => Engine->new );

  print $car->is_broken ? 'Still working' : 'Busted';
  $car->break;
  print $car->is_broken ? 'Still working' : 'Busted';

  $car->does('Breakable'); # true

This prints:

  Still working
  I broke
  Busted

We could use this same role in a C<Bone> class:

  package Bone;

  use Moose;

  with 'Breakable';

  has 'marrow' => (
      is  => 'ro',
      isa => 'Marrow',
  );

=head1 REQUIRED METHODS

As mentioned previously, a role can require that consuming classes
provide one or more methods. Using our C<Breakable> example, let's
make it require that consuming classes implement their own C<break>
methods:

  package Breakable;

  use Moose::Role;

  requires 'break';

  has 'is_broken' => (
      is  => 'rw',
      isa => 'Bool',
  );

  after 'break' => sub {
      my $self = shift;

      $self->is_broken(1);
  };

If we try to consume this role in a class that does not have a
C<break> method, we will get an exception.

Note that attribute-generated accessors do not satisfy the requirement
that the named method exists. Similarly, a method modifier does not
satisfy this requirement either. This may change in the future.

You can also see that we added a method modifier on
C<break>. Basically, we want consuming classes to implement their own
logic for breaking, but we make sure that the C<is_broken> attribute
is always set to true when C<break> is called.

  package Car

      use Moose;

  with 'Breakable';

  has 'engine' => (
      is  => 'ro',
      isa => 'Engine',
  );

  sub break {
      my $self = shift;

      if ( $self->is_moving ) {
          $self->stop;
      }
  }

=head1 USING METHOD MODIFIERS

Method modifiers and roles are a very powerful combination.  Often, a
role will combine method modifiers and required methods. We already
saw one example with our C<Breakable> example.

Method modifiers increase the complexity of roles, because they make
the role application order relevant. If a class uses multiple roles,
each of which modify the same method, those modifiers will be applied
in the same order as the roles are used:

  package MovieCar;

  use Moose;

  extends 'Car';

  with 'Breakable', 'ExplodesOnBreakage';

Assuming that the new C<ExplodesOnBreakage> method I<also> has an
C<after> modifier on C<break>, the C<after> modifiers will run one
after the other. The modifier from C<Breakable> will run first, then
the one from C<ExplodesOnBreakage>.

=head1 METHOD CONFLICTS

If a class composes multiple roles, and those roles have methods of
the same name, we will have a conflict. In that case, the composing
class is required to provide its I<own> method of the same name.

  package Breakdances;

  use Moose::Role

  sub break {

  }

If we compose both C<Breakable> and C<Breakdancer> in a class, we must
provide our own C<break> method:

  package FragileDancer;

  use Moose;

  with 'Breakable', 'Breakdancer';

  sub break { ... }

=head1 METHOD EXCLUSION AND ALIASING

If we want our C<FragileDancer> class to be able to call the methods
from both its roles, we can alias the methods:

  package FragileDancer;

  use Moose;

  with 'Breakable'   => { alias => { break => 'break_bone' } },
       'Breakdancer' => { alias => { break => 'break_dance' } };

However, aliasing a method simply makes a I<copy> of the method with
the new name. We also need to exclude the original name:

  with 'Breakable' => {
      alias   => { break => 'break_bone' },
      exclude => 'break',
      },
      'Breakdancer' => {
      alias   => { break => 'break_dance' },
      exclude => 'break',
      };

The exclude parameter prevents the C<break> method from being composed
into the C<FragileDancer> class, so we don't have a conflict. This
means that C<FragileDancer> does not need to implement its own
C<break> method.

This is useful, but it's worth noting that this breaks the contract
implicit in consuming a role. Our C<FragileDancer> class does both the
C<Breakable> and C<BreakDancer>, but does not provide a C<break>
method. If some API expects an object that does one of those roles, it
probably expects it to implement that method.

=head1 AUTHOR

Dave Rolsky E<lt>autarch@urth.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2008 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
