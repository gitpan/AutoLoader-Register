package TestClass;

BEGIN {
    # since we use Net::Ping to import from we need to set
    # proto => 'tcp' so that close() will in fact do nothing
    use AutoLoader::Register
        new  => q{ sub { bless { proto => 'tcp' }, shift } },
        put  => q{ sub { my $self = shift; $self->{arg} = shift; 2 } },
        get  => q{ sub { shift->{arg} } },
        comp =>    sub { 42 },
        [ qw(get_methods_from autoloader_configure) ];

    get_methods_from( "Net::Ping", "close" );
    autoloader_configure( exception => sub { shift } );
}

package main;

use Test;
BEGIN { plan tests => 11 };
use AutoLoader::Register;

ok(1); # If we made it this far, we're ok.

my $obj = TestClass->new;

ok($obj->isa("TestClass"), 1);
ok(ref $obj->can("put"), 'CODE');
ok(ref $obj->can("get"), 'CODE');
ok(ref $obj->can("comp"), 'CODE');
ok(ref $obj->can("close"), 'CODE');
ok($obj->put("arg"), 2);
ok($obj->get, "arg");
ok($obj->comp, 42);
ok($obj->close, 1);
ok($obj->not_there, "TestClass::not_there");
