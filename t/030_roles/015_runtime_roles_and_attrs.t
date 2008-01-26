#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 9;
use Test::Exception;
use Scalar::Util 'blessed';

BEGIN {
    use_ok('Moose');
}


{
    package Dog;
    use Moose::Role;

    sub talk { 'woof' }

    package Foo;
    use Moose;

    has 'dog' => (
        is   => 'rw',
        does => 'Dog',
    );
}

my $obj = Foo->new;
isa_ok($obj, 'Foo');    

ok(!$obj->can( 'talk' ), "... the role is not composed yet");
ok(!$obj->does('Dog'), '... we do not do any roles yet');

dies_ok {
    $obj->dog($obj)
} '... and setting the accessor fails (not a Dog yet)';

Dog->meta->apply($obj);

ok($obj->does('Dog'), '... we now do the Bark role');
ok($obj->can('talk'), "... the role is now composed at the object level");

is($obj->talk, 'woof', '... got the right return value for the newly composed method');

lives_ok {
    $obj->dog($obj)
} '... and setting the accessor is okay';
