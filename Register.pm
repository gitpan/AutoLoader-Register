package AutoLoader::Register;

use 5.006;
use strict;
use warnings;
use Carp;

our $AUTOLOAD;
our $VERSION = '0.01';
our (%CODE, %CONFIG);

sub import (@_) {
    my $class  = shift;
    my $caller = caller;

    # does someone want to import?
    if (ref $_[-1] eq 'ARRAY') {
        my @export = @{+pop};
        for my $exp (@export) {
            no strict 'refs';
            *{ $caller . "::" . $exp } = \&{ $exp };
        }
    }
    
    $CODE{$caller} = { @_ };
    
    {   
        # make us the caller's superclass
        no strict 'refs';
        unshift @{ $caller . "::ISA" }, __PACKAGE__; 
    }
}

sub can {
    my ($self, $method) = @_;
    return if ! ref $self or ! $method;
    my $me = ref $self;
    if (exists $CODE{$me}->{$method}) {
        no strict 'refs';
        if (! ref $CODE{$me}->{$method}) {
            *{ $me . "::" . $method } = eval $CODE{$me}->{$method};
        }
        else {
            *{ $me . "::" . $method } = $CODE{$me}->{$method};
        }
    }
    return UNIVERSAL::can ($self, $method);
};

sub autoloader_configure (@_) {
    my %args = @_;
    my $caller = caller;
    while (my ($key, $value) = each %args) {
        $CONFIG{$caller}->{$key} = $value;
    }
}
        
sub get_methods_from ($@) {
    
    my ($from, @methods) = @_;
    my $caller = caller;
   
    # to make can() work
    eval "require $from" if ! exists $CODE{$from};
    if ($@) {
        carp "Class '$from' does not seem to exist";
        return;
    }

    my $dummy = bless {}, $from;
    
    for my $meth (@methods) {
         if (exists $CODE{$from}->{$meth}) {
            $CODE{$caller}->{$meth} = $CODE{$from}->{$meth};
            next;
        }
        elsif (my $code = UNIVERSAL::can ($dummy, $meth)) {
            no strict 'refs';
            *{ $caller . "::" . $meth } = $code;
            next;
        }
        else { carp "'$from" . "::$meth' does not exit" } 
    }
}

sub AUTOLOAD {
    no strict 'refs';
    my ($class, $method) = $AUTOLOAD =~ /(.*?)::(.*)/;

    return if $method eq 'DESTROY';

    if (exists $CODE{$class}->{$method}) {
        if (ref $CODE{$class}->{$method} eq 'CODE') {
            *$AUTOLOAD = $CODE{$class}->{$method};
        }
        else {
            *$AUTOLOAD = eval $CODE{$class}->{$method};
        }
        delete $CODE{$class}->{$method};
        goto &$AUTOLOAD;
    }
    
    # method not found
    else {
        my $msg = "Method '$method' is not available via package '$class'";
        croak ("Croaked: ", $msg), return 
            if lc $CONFIG{$class}->{exception} eq 'croak';
        carp  ("Carped: ", $msg), return 
            if lc $CONFIG{$class}->{exception} eq 'warn';

        if (ref $CONFIG{$class}->{exception} eq 'CODE') {
            $CONFIG{$class}->{exception}->($AUTOLOAD);
        }
        elsif (ref $CONFIG{$class}->{exception} eq 'ARRAY') {
            my $c = shift @{ $CONFIG{$class}->{exception} };
            $c->(@{ $CONFIG{$class}->{exception} });
        }
    }
}

1;
__END__

=head1 NAME

B<AutoLoader::Register> - A smart autoloader to be inherited by your classes

=head1 SYNOPSIS
    
    package MyModule;

    use AutoLoader::Register
        method1 => q{ sub {
                        my ($self, $arg) = @_;
                        $self->{$arg};
                    }},
        method2 => q{ sub {
                        my $self = shift;
                        return $self->{arg};
                    }},
        method3 => q{ sub {
                        my $self = shift;
                        print $self->method2;
                    }};

    sub new {
        my $class   = shift;
        $self       = { };
        ...
        return bless $self, $class;
    }

=head1 DESCRIPTION

Before reading on, please notice: This code is absolute ALPHA. Things may change in the future (or may not).

B<AutoLoader::Register> is an extension to Perl's normal autoloading mechanism. Compilation of the code is delayed until one of the specified methods is actually called the first time. Once it has been called, the method is compiled into your module's namespace so that consecutive calls to it will avoid any look-up through the autoloader. 

Thus the speed-penalty that is usually caused by autoloading is minimized: Your scripts start up more quickly since less code is to be compiled and during runtime each used method only has to be looked up and compiled once. You wont get much closer to optimal performance.

The module is very similar in functionality to SelfLoader and AutoSplit/AutoLoader. Unlike those it is intended only for methods (either class- or instance-methods). More to it, no reading from whatsoever filehandle is required which also avoids the necessity to parse Perl-code as SelfLoader does.

=head1 USE

It is pretty straight-forward actually:

=head2 1) SUBCLASSING

Nothing to be done here. Usually you make your class a subclass of something by adding
    
    use base qw(Something);

to your script. As far as B<AutoLoader::Register> is concerned, you do not need this line since your class will automatically turn into a subclass once you include this module via C<use()>.
    
=head2 2) INCLUDE THE MODULE

Now include B<AutoLoader::Register> with the use()-statement. You have to supply the methods to be autoloaded as key/value pairs. The key is the name of the method under which it should be accessible while the value a string of an anonymous Perl-subroutine is. Example:

    use AutoLoader::Register
        method1 => q{ sub {
                        my $self = shift;
                        ...
                    }},
        method2 => ... ;

Additionally, you can pass a method as code-reference. In such a case all you have to is leave away the quotes around the anonymous subroutine. This has the effect that the code is already compiled when it is passed to B<AutoLoader::Register>:

    use AutoLoader::Register
        compiled_method => sub { print "I am already compiled\n" } ;

=head2 3) CONFIGURE THE AUTOLOADER

You can specify how your module should behave if a method is called that is not defined in your class nor managed by the autoloader. Currently four behaviours can be specified with the 'exception' option: 'warn' (but continue your program), 'croak' (spectacularly report the error and terminate the program), ignore it (the default) or a custom behaviour you specify with passing an anonymous subroutine to C<autoloader_configure>.

For that purpose B<AutoLoader::Register> provides a function, C<autoloader_configure>. 

    use AutoLoader::Register
        method1 => ...
        method2 => ... ;
    
    # constructor
    sub new {
        AutoLoader::Register::autoloader_configure (exception => 'warn');
        bless {}, shift;
    }

See also further below L<"FUNCTIONS">.

=head2 4) WRITE THE CODE OF YOUR CLASS

What follows is simply what you always do when you write Perl-code. Add functions, methods, include modules, whatever...it's all up to you.

=head1 A COMPILE-TIME ONLY CLASS

Since you can even make your constructor autoloadable, you can create a class that only contains compile-time code:

    package CompileTimeClass;

    BEGIN { 
        
    our $VERSION = '0.01'; 
    use AutoLoader::Register new   => q{ sub { bless { }, shift } },
                             store => q{ sub { my $self = shift;
                                               $self->{arg} = shift } },
                             get   => q{ sub { shift->{arg} } ;
    }

Three little methods: an empty constructor, a store-method to store an arbitrary scalar and a get-method to retrieve this value.

Nothing except C<$VERSION> gets compiled when you C<use()> this little class in your program. It's all done on the fly and only once per method. Use the above to impress your colleagues at work.

=head1 INHERITANCE (OR NOT)

Consider you have a class C<Class1> that has a bunch of methods (irrelevant whether managed by B<AutoLoader::Register> or not). Now consider that you have another Class C<Class2>. This class should have some methods of C<Class1> but yet you don't want to make C<Class1> a superclass. You can now use B<AutoLoader::Cache> to sort of copy methods from C<Class1> into your second class. For that there is the C<AutoLoader::Cache::get_methods_from> function:

    package Class2;

    BEGIN {
        use AutoLoader::Register
                            method => ... 
                            ...    => ... ;
        AutoLoader::Register::get_methods_from ( "Class1", qw(meth1 meth2) );
    }

Think of this as inheritance among siblings. 

Perhaps as a side-note: You can C<use AutoLoader::Register> without any further arguments to it. The above example shows that this can be useful from time to time, namely if you only want a few methods from another class.

However, mark that you can load methods from B<any> class even if this class has nothing whatsoever to do with B>AutoLoader::Register>. There are two scenarios actually:

=over 4

=item * Getting methods from a class not under control of B<AutoLoader::Register>:

The methods to be imported *must not* be supplied via autoloading.

=item * Getting methods from a class managed by B<AutoLoader::Register>:

Can both be autoloaded methods or those hard-coded in the class.

=back

=head1 FUNCTIONS

B<AutoLoader::Register> comes with a few functions that are by default not exported into your class' namespace. You can do that by providing a reference to an array of functions you want to import as last argument to the C<use> statement:

    use Register::AutoLoader
                    method1 => ... ,
                    method2 => ... ,
                    [ qw(autoloader_configure ...) ];

=over 4
                    
=item B<autoloader_configure (OPTIONS)>

Currently only used to indicate what should be done in case a called method could not be autoloaded. Arguments come in key/value pairs:

=over 4

=item * exception =E<gt> 'warn' | 'croak' | [ CODEREF, arguments ... ]

When set to 'warn' each time a non-existing method is called, a warning message is printed, but execution of the code continues.
'croak' will give the same message but terminate your program immediately.

CODEREF will allow you to set up a custom behaviour under such circumstances. This can be anything, beginning with your own error-messages (perhaps writing to a log-file) or more complex things. If you want to pass additional arguments to your CODEREF, pass it all as a reference to an anonymous array. 

Each handler you write will have one default argument: namely the value of C<$AUTOLOAD>. This is a string consisting of the fully qualified method call. So if you called the method 'foo' in your class 'bar', the first argument to your handler will be the string "bar::foo".

Example:

    # Setting up a handler with additional arguments:
    # A silly one, since it will always return 100
    my $code = sub { return $_[1] * $_[2] };
    autoloader_configure ( exception => [ $code, 10, 10 ] );

    # Setting up one without arguments
    my $code = sub { print "Method does not exist: $_[0]\n" }
    autoloader_configure ( exception => $code );

As you see, you only have to give an array-ref when you actually pass additional arguments. 

=back

=item B<get_method_from (FROM, METHODS)>

This will add METHODS (a simple list of strings) from the class FROM to your current class. Thus you can selectively sort of inherit the methods you want without making your class a subclass of FROM. Care is taken that no unnecessary compilation of code takes place. That means: if the any methods you want to pull are not yet compiled (perhaps because they were themselves methods given to AutoLoader::Register by the class FROM and not yet called), just a string-copy is done internally. 

You can pull in methods from practically any class. So if you selectively want a few methods from MIME::Entity, no problem. Example:

    get_method_from ("MIME::Entity", "effective_type");

You do not even need to C<require> or C<use> the module. B<AutoLoader::Register> does all of that for you.

=head1 NOTES

One limitation of autoloading is that autoloaded methods are not reported by C<UNIVERSAL::can()>. B<AutoLoader::Register> however has its own custom C<can()> that circumvents these limitations. When you do C<$obj-E<gt>can("method")> (given that you did not define a can-method in your class) Autoloader::Cache returns the code-ref to "method" if the method has been found. If it has not been found, it calls C<UNIVERSAL::can()> so that methods you directly define in your class are reported properly.

If you use a CODEREF to be executed on calling non-existing methods using C<autoloader_configure> be careful when inspecting the caller-stack using C<caller>. Since this CODEREF always is an anonymous subroutine, the code can't be executed using C<goto &$CODEREF>. That means that in your caller-stack there should be an entry 'AutoLoader::Register'. But thus you can still distinguish between a registered method (since in such a case the method is compiled into your class) and one called on an exception.

=head1 BUGS

Any code not being in either the methods or a BEGIN (or CHECK) block seems to be NOT executed. There is not much to worry about it since you can in fact put it into a BEGIN-block or have several of those. So whenever you create a class, be sure to put vital things (such as the $VERSION package-variable) into the BEGIN-block.

Another problem seems to occur when you define to (sort-of) inner-classes in your program and put one class under control of B<AutoLoader::Register> while at the same time trying to C<get_methods_from> the other class.

This beast needs more testing so I guess there are a few more lying around. Whenever you happen to find one, please do not hesitate to send me a note to the email-address found further below.

=head1 THANKS

Many thanks to Mark Jason Dominus for the wealth of Perl-related information and Perl-techniques on his webside http://perl.plover.com/ .

=head1 VERSION

This is version 0.01.

=head1 AUTHOR AND COPYRIGHT

Tassilo von Parseval

B<E<lt>tassilo.parseval@post.rwth-aachen.deE<gt>>

Copyright (c)  2001-2002 Tassilo von Parseval. 
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<AutoLoader>

http://perl.plover.com/yak/tricks/slide073.html

=cut
