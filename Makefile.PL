use ExtUtils::MakeMaker;

WriteMakefile(
    NAME		 => 'AutoLoader::Register',
    VERSION_FROM => 'Register.pm',   # finds $VERSION
    PREREQ_PM	 => {},
    AUTHOR       => 'Tassilo v. Parseval <tassilo.parseval@post.rwth-aachen.de',
    DISTNAME     => 'AutoLoader-Register'
);
