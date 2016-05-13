#============================================================= -*-Perl-*-
#
# Template::Plugin::UOA_whitelist
#
# DESCRIPTION
#   Template Toolkit plugin module for modlist/whitelist handling
#
# AUTHOR
#   Steve Shipway
#
#============================================================================

package Template::Plugin::UOA_whitelist;
use base 'Template::Plugin';
use Sympa::Constants;
use strict;

our $VERSION   = 0.01;

sub new {
	my ($class, $context, $args) = @_;
	my($home) = Sympa::Constants::EXPLDIR;
	my($file) = "whitelist.txt";
	$home = $args->{home} if($args->{home});
	$file = $args->{file} if($args->{file});
	return bless { 
		_CONTEXT => $context,
		search_filters => "",
		content => '',
		whitelist => '',
		saveerror => '',
		_HOME => $home,
		_FILE => $file,
	}, $class;
}

sub update {
	my( $obj, @args ) = @_;
	my($rv) = "";
	my($sfdir)='';
	my($content)='';

	$sfdir = $obj->{'_HOME'}."/".$obj->{_CONTEXT}{STASH}{robot}."/".$obj->{_CONTEXT}{STASH}{list}."/search_filters";
	$sfdir = $obj->{'search_filters'} if($obj->{'search_filters'});
	if( $sfdir and ! -d $sfdir ) { mkdir $sfdir; }
	$content = $obj->{'content'};
	$content =~ s/^.// ;  # kill strange initial metacharacter
	$content =~ s/\s*[\r\n]\s+/\n/g; # kill blank lines
	if( defined $content  ) {
		if( open WLFILE,(">${sfdir}/".$obj->{_FILE}) ) {
			print WLFILE $content;
			close WLFILE;
			$obj->{saved}=1;
		} else {
			$rv = "Unable to save: $!";
			$obj->{saveerror}=$rv;
		}
	} else {
		$rv = "No content available to save";
		$obj->{saveerror}=$rv;
	}
	return $rv;
}

sub fetch {
	my( $obj, @args ) = @_;
	my($rv) = "";
	my($whitelist,$fname);

	$fname = $obj->{'_HOME'}."/".$obj->{_CONTEXT}{STASH}{robot}."/".$obj->{_CONTEXT}{STASH}{list}."/search_filters/".$obj->{_FILE};
	$fname = $obj->{'search_filters'}."/".$obj->{_FILE} if($obj->{'search_filters'});
	$whitelist = "";
	if( -r $fname ) {
		open WLFILE,"<$fname";
		my @whitelist = <WLFILE>;
		close WLFILE;
		$whitelist = join "",@whitelist;
		$obj->{rows}=($#whitelist + 1);
	}
	$obj->{whitelist}=$whitelist;

	return $whitelist;
}

1;

__END__

