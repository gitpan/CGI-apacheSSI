# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl basic_tests.t'

#########################

use strict;
use warnings FATAL => 'all';

use Test::More tests => 21;

use List::Util qw(sum);
use File::Temp qw(tempfile tempdir);

use_ok('CGI::apacheSSI');

#########################
# all these tests were part of the CGI::SSI test vector
#########################

# set and echo

{
    my $ssi = CGI::apacheSSI->new();
    $ssi->set(var => 'value');
    my $value = $ssi->echo('var');
    ok($value eq 'value','set/echo 1');
}

# other ways to call set and echo

{
    my $ssi = CGI::apacheSSI->new();
    $ssi->set(var => "var2", value => "value2");
    my $value = $ssi->echo(var => 'var2');
    ok($value eq 'value2','set/echo 2');
}

# objects don't crush each other's vars.

{
    my $ssi = CGI::apacheSSI->new();
    my $ssi2 = CGI::apacheSSI->new();

    $ssi->set(var => "value");
    $ssi2->set(var => "value2");

    my $value  = $ssi->echo("var");
    my $value2 = $ssi2->echo("var");

    ok($value eq "value" && $value2 eq "value2",'data encapsulation');
}

# args to new()

{
    my $ssi = CGI::apacheSSI->new(
			    DOCUMENT_URI  => "doc_uri",
			    DOCUMENT_NAME => "doc_name",
			    DOCUMENT_ROOT => "/",
			    errmsg        => "[ERROR!]",
			    sizefmt       => "bytes",
                timefmt       => "%B",
			    );
    ok(   ($ssi->echo("DOCUMENT_URI")  eq "doc_uri"
       and $ssi->echo("DOCUMENT_NAME") eq "doc_name"
       and $ssi->echo("DOCUMENT_ROOT") eq "/"),'new()');
}

# config

{
    my %months = map { ($_,1) } qw(January February March April May June 
                                   July August September October November December);

        # create a tmp file for testing.
    use IO::File;
    use POSIX qw(tmpnam);
    
    my($filename,$fh); # Thanks, Perl Cookbook!
    do { $filename = tmpnam() } until $fh = IO::File->new($filename, O_RDWR|O_CREAT|O_EXCL);
#   select( ( select($fh), $| = 1 )[0] );
    print $fh ' ' x 10;
    close $fh;

    my $ssi = CGI::apacheSSI->new();
    $ssi->config(timefmt => "%B");
    ok($months{ $ssi->flastmod(file => $filename) },'config 1');

    $ssi->config(sizefmt => "bytes"); # TODO: combine these calls to config.

    my $size = $ssi->fsize(file => $filename);
    ok($size eq int $size,'config 2');

    $ssi->config(errmsg => "error"); # TODO combine config calls

	# close STDERR for this test
	open COPY,'>&STDERR' or die "no copy of STDERR: $!";
	close STDERR;

	# perform the test
    ok($ssi->flastmod("") eq "error",'config 3');

	# re-open STDERR and continue
	open STDERR,">&COPY" or die "no reassign to STDERR: $!";

    unlink $filename;
}

    # tough to do these well, without more info...
# include file - with many types of input
# include virtual - with different types of input

{
    my $ssi = CGI::apacheSSI->new();
    my $html = $ssi->process(q[<!--#include virtual="http://www.yahoo.com" -->]);
    ok($html =~ /yahoo/i && $html =~ /mail/i,'include virtual 1');
}

    # tough to do these well, without more info...
# include file - with many types of input
# include virtual - with different types of input

{
    my $ssi = CGI::apacheSSI->new(DOCUMENT_ROOT => '.');
    my $html = $ssi->process(q[<!--#include virtual="/MANIFEST" -->]);
    ok($html =~ /Changes/i,'include virtual 2');
}

# exec cgi - with different input

{
    my $ssi = CGI::apacheSSI->new();
    my $html = $ssi->process(q[<!--#exec cgi="http://www.yahoo.com/" -->]);
    ok($html =~ /yahoo/i,'exec cgi');
}

# exec cmd - with different input

{
    my $ssi = CGI::apacheSSI->new();
    my $perl = $^X;
    $perl =~ s|\\|/|g;
    my $html = $ssi->process(qq[<!--#exec cmd="$perl -v" -->]);
    ok($html =~ /perl/i,'exec cmd');
}

# flastmod - different input
# fsize - different input

# derive a class, and do something simple (empty class)

{
    package CGI::apacheSSI::Empty;
    @CGI::apacheSSI::Empty::ISA = qw(CGI::apacheSSI);

    package main;

    my $empty = CGI::apacheSSI::Empty->new();
    my $html = $empty->process(q[<!--#set var="varname" value="foo" --><!--#echo var="varname" -->]);
    ok($html eq "foo",'inherit 1');
}

# derive a class, and do something simple (altered class)

{
    package CGI::apacheSSI::UCEcho;
    @CGI::apacheSSI::UCEcho::ISA = qw(CGI::apacheSSI);

    sub echo {
		return uc shift->SUPER::echo(@_);
    }

    package main;

    my $echo = CGI::apacheSSI::UCEcho->new();
    my $html = $echo->process(q[<!--#set var="varname" value="foo" --><!--#echo var="varname" -->]);
    ok($html eq "FOO",'inherit 2');
}

# DATE_LOCAL/DATE_GMT with config{timefmt}
{
    my $ssi = new CGI::apacheSSI (timefmt => '%Y');
    ok($ssi->echo('DATE_LOCAL') =~ /^\d{4}$/,'config{timefmt}');
}

{
  # timefmt applied to LAST_MODIFIED
  my $ssi = CGI::apacheSSI->new();
  my $html = $ssi->process('<!--#config timefmt="%m/%d/%Y %X" --><!--#echo var="LAST_MODIFIED" -->');
  like($html, qr{^\d\d/\d\d/\d{4} \d\d:\d\d:\d\d$}, 'timefmt applied to LAST_MODIFIED');
}

{
  # newlines in directives
  my $ssi = CGI::apacheSSI->new();
  my $html = $ssi->process('<!--#config 
 timefmt="%m/%d/%Y %X" --><!--#echo var="LAST_MODIFIED" -->');

  like($html, qr{^\d\d/\d\d/\d{4} \d\d:\d\d:\d\d$}, 'newlines in directives');
}

# check recursion test
SKIP: {
		# create tempfile to hold include directive
    my($fh,$filename) = tempfile();
    skip("Failed to create tempfile: $!",1) unless $filename;
	$filename =~ s/\\/\\\\/g;
	print $fh qq[<!--#include file="$filename"-->];
	close $fh;
	
	my $ssi = CGI::apacheSSI->new(MAX_RECURSIONS => 42);

	# close STDERR for this test
	open COPY,'>&STDERR' or die "no copy of STDERR: $!";
	close STDERR;

	# perform the test
	my $html = $ssi->include(file => $filename);
	ok($html eq $ssi->{_config}->{errmsg}
		&& (
			sum(values %{$ssi->{_recursions}}) == 43 
			||
			sum(values %{$ssi->{_recursions}}) == 42
		   )
		, "recursion check");

	# re-open STDERR and continue
	open STDERR,">&COPY" or die "no reassign to STDERR: $!";


}

# test cookie support
SKIP: {
	eval "use HTTP::Cookies; 1" or skip("HTTP::Cookies not installed", 1);
	my $jar = HTTP::Cookies->new({});
	my $cookie_name = "CGI_APACHESSI_COOKIE";
	my $cookie_val = "COOKIEVAL";
	$jar->set_cookie(1,$cookie_name,$cookie_val,'/','insaner.com',80,0,0,100);

	my $ssi = CGI::apacheSSI->new(COOKIE_JAR => $jar);
	my $html = $ssi->process(qq[<!--#include virtual="http://insaner.com/dev/apacheSSI/cookie_test.html"-->]);
	ok($html =~ m{$cookie_val}, "cookie support [$html]");
}


SKIP: {
	# tie by hand & close
    my($dir) = tempdir();
#	print $dir,"\n";
	open FH, "+>$dir/AfDCSd43.tmp" or skip('failed to open tempfile',2);
	my $ssi = tie *FH, 'CGI::apacheSSI', filehandle => 'FH';
	isa_ok(tied(*FH),'CGI::apacheSSI','tied object');

	print FH "this is the first test\n";

	close FH;
	eval { print FH "this is the second test\n" or die "FH is closed" };
	ok($@ =~ /^FH is closed/,'close()');
}

# autotie ?


__END__
