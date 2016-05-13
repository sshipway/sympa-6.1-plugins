#============================================================= -*-Perl-*-
#
# Template::Plugin::Tracking
#
# DESCRIPTION
#   Template Toolkit plugin module for Sympa mailing lists
#   Provide tracking for mailmerge messages
#
# AUTHOR
#   Steve Shipway
#
# This plugin provides both functions for adding the tracking to mailmerged
# messages, and also the functions to query the database used by the web
# frontend.
#
#============================================================================
# 0.1 : first working version
# 0.2 : extra checks for when not in content-type=~/html/ and non-null return
#       more helpful comment code
#       multiple ways to seek out the message-id header content
#       better defaults for base_url etc
#       Tracking.unsubscribe function
# 0.3 : Support Sympa 6.1.21 and later with part.type instead of headers.content-type
# 0.4 : Fix unsubscribe function HTML detection test
# 0.5 : Remove trailing %0A from RCPT_ID
# 0.6 : Second listname param to unsubscribe function
#============================================================================

package Template::Plugin::Tracking;
use base 'Template::Plugin';
use Sys::Hostname;
use Digest::MD5;
use DBI;
use URI::Escape;
use strict;

our $VERSION   = 0.06;

sub new {
	my ($class, $context, @args) = @_;

	# This increments by one for each link we track
	my  $LINK_ID = 1;
	# This is the ID for this message
	my  $MSG_ID = '';
	# This is the ID for this recipient
	my  $RCPT_ID = 'default';
	# The base tracking URL
	my  $BASE_URL = '/cgi-bin/track.cgi';
	# The mailing list address
	my  $LIST_NAME = 'default';

	if($args[0] and !ref $args[0] and $args[0]=~/^http/) {
		$BASE_URL = $args[0] ;
	} elsif( $context->{STASH}{'wwsympa_url'} ) {
		$BASE_URL = $context->{STASH}{'wwsympa_url'};
		$BASE_URL =~ s/sympa$//;
		$BASE_URL .= 'cgi-bin/track.cgi';
	} else {
		# Set up BASE_URL from info in the stash
		$BASE_URL = 'http://'.hostname().'/cgi-bin/track.cgi';
	}

	# Set up default list name
	if( $context->{STASH}{listname} ) { # for mail context
		$LIST_NAME = $context->{STASH}{listname}.'@'.$context->{STASH}{robot};
	} else { # for web context
		$LIST_NAME = $context->{STASH}{list}.'@'.$context->{STASH}{robot};
	}

	# Define MSG_ID based on message details as held in
	# the context.
	if($context->{STASH}{headers}{'message-id'}) {
		$MSG_ID = Digest::MD5::md5_base64($context->{STASH}{headers}{'message-id'});
	} elsif($context->{STASH}{'message-id'}) {
		$MSG_ID = Digest::MD5::md5_base64($context->{STASH}{'message-id'});
	} elsif($context->{STASH}{'messageid'}) {
		$MSG_ID = Digest::MD5::md5_base64($context->{STASH}{'messageid'});
	}

	# The message subject
	my $SUBJECT = $context->{STASH}{headers}{'subject'} || 'None';

	if( ref $args[0] =~ /HASH/ ) {
		$MSG_ID = $args[0]->{msgid} if($args[0]->{msgid});
		$BASE_URL = $args[0]->{url} if($args[0]->{url});
		$SUBJECT = $args[0]->{subject} if($args[0]->{subject});
		$LIST_NAME = $args[0]->{list}.'@'.$context->{STASH}{robot} if($args[0]->{list});
	}

	$MSG_ID =~ s/[\/&?@%'"\\+]/_/g; # just in case

	# Define RCPT_ID for this recipient based on stash
	$RCPT_ID = $context->{STASH}{user}{escaped_email};
	$RCPT_ID =~ s/%0A//ig; # remove any trailing newlines

	# IF we are in message mode...
	# If MSG_ID not already in database, then do initial setup for this
	# write msgs=($MSG_ID,$subject,$LIST_NAME,NOW())
	if( $MSG_ID ) {
		my $sql = "INSERT into `tracking_msgs` (`msg_id`,`subject`,`list_name`,`sent`) VALUES(?,?,?,NOW())";
		my $dbh = &List::db_get_handler();
		if($dbh) { 
			my($sth) = $dbh->prepare($sql);
			my($rows)= $sth->execute($MSG_ID,$SUBJECT,$LIST_NAME); 
		}

		# Store it here, since filters cant see the object
		$context->{STASH}{Tracking} = { MSG_ID=>$MSG_ID,
		    RCPT_ID=>$RCPT_ID, LINK_ID=>1, BASE_URL=>$BASE_URL };

		# Define a new filter that can be used later
		# This filter handles general replacement of links with tracked links
		$context->define_filter('Tracking', [ \&track_ff => 1 ]);
	}

	return bless { _CONTEXT=>$context, SUBJECT=>$SUBJECT, MSG_ID=>$MSG_ID, 
		RCPT_ID=>$RCPT_ID, BASE_URL=>$BASE_URL, LIST_NAME=>$LIST_NAME, LINK_ID=>$LINK_ID
	}, $class;
}

##########################################################
# These functions are used in web frontend mode

# [% errormessage = Tracking.messages %]
# [% FOREACH message = message_list %]
sub messages { 
	my($obj,@args) = @_;
	my($rv) = '';
	my(@messages) = ();
	my($sth,$sql,$ret);
	my(@msg);

	my $dbh = &List::db_get_handler();
	if(!$dbh) {
		$rv = "Unable to connect to database.";
		return $rv;
	}

	$sql = "SELECT m.`msg_id`,m.`subject`,m.`sent`,count(c.`rcpt_id`) numsent from `tracking_msgs` m,`tracking_clicks` c where m.`list_name` = ? AND c.`msg_id` = m.`msg_id` AND  c.`link_id` = 0 GROUP BY m.`msg_id` ORDER BY m.`sent` DESC LIMIT 100";
	$sth = $dbh->prepare($sql);
	$sth->execute($obj->{LIST_NAME});
	$ret = $sth->fetchall_arrayref;
	if( !$ret or $dbh->err ) {
		$rv = "Database error: ".$dbh->errstr;
		$obj->{_CONTEXT}{STASH}{message_sql} = $sql;
		return $rv;
	}
	foreach ( @$ret ) { push @messages, { id=>($_->[0]), subject=>($_->[1]), sent=>($_->[2]), num=>($_->[3]) }; }

	$obj->{_CONTEXT}{STASH}{message_list} = \@messages;
	$obj->{_CONTEXT}{STASH}{message_count} = $#messages + 1;
	$obj->{_CONTEXT}{STASH}{message_sql} = $sql;
	return $rv;
}

# [% msg = Tracking.msg(messageid) %]
# Subject is [% msg.subject %]
sub msg {
	my($obj,$msgid) = @_;
	my($rv) = '';
	my(%msgdata) = { id=>$msgid, subject=>'None', sent=>'Unknown', num=>0, seen=>0, rate=>'Unknown' };
	my($sql,$ret,$sth);

	my $dbh = &List::db_get_handler();
	if(!$dbh) {
		$msgdata{error} = "Unable to connect to database.";
		return \%msgdata;
	}

	$sql = "SELECT m.`msg_id`,m.`subject`,m.`sent`,(SELECT count(*) from `tracking_clicks` c WHERE c.`msg_id` = m.`msg_id` and c.`link_id` = 0) numsent, (SELECT count(*) from `tracking_clicks` c WHERE c.`msg_id` = m.`msg_id` and c.`link_id` = 0 and c.`clicks`>0) numseen from `tracking_msgs` m WHERE m.`msg_id` = ? LIMIT 1";
	$sth = $dbh->prepare($sql);
	$sth->execute($msgid);
	$ret = $sth->fetchrow_arrayref();
	if($ret and @$ret) {
		$msgdata{id}      = $ret->[0];
		$msgdata{subject} = $ret->[1];
		$msgdata{sent}    = $ret->[2];
		$msgdata{num}     = $ret->[3];
		$msgdata{seen}    = $ret->[4];
		$msgdata{rate}    = $ret->[4]/$ret->[3]*100.0 if($ret->[3]);
	}

	$obj->{_CONTEXT}{STASH}{message_sql} = $sql;
	return \%msgdata;
}
# [% lnk = Tracking.lnk(messageid,linkid) %]
# Link URL is [% lnk.url %]
sub lnk {
	my($obj,$msgid,$linkid) = @_;
	my($rv) = '';
	my(%lnkdata) = ();
	my($sql,$ret,$sth);

	my $dbh = &List::db_get_handler();
	if(!$dbh) {
		$lnkdata{error} = "Unable to connect to database.";
		return \%lnkdata;
	}

	$linkid = 0 if($linkid eq 'none');

	$sql = "SELECT l.`link_id`,l.`url`,(SELECT count(*) from `tracking_clicks` c WHERE  c.`msg_id` = ? and c.`link_id` = ? and c.`clicks`>0 ) num from `tracking_links` l WHERE l.`msg_id` = ? and l.`link_id` = ? LIMIT 1";
	$sth = $dbh->prepare($sql);
	$sth->execute($msgid,$linkid,$msgid,$linkid);
	$ret = $sth->fetchrow_arrayref();
	if($ret and @$ret) {
		$lnkdata{id}      = $ret->[0];
		$lnkdata{url}     = $ret->[1];
		$lnkdata{seen}    = $ret->[2];
	}

	$obj->{_CONTEXT}{STASH}{message_sql} = $sql;
	return \%lnkdata;
}

# [% errormessage = Tracking.links(message.id) %]
# [% FOREACH link = link_list %]
sub links { 
	my($obj,$msgid) = @_;
	my($rv) = '';
	my(@links) = ();
	my($sql,$ret,$sth);

	my $dbh = &List::db_get_handler();
	if(!$dbh) {
		$rv = "Unable to connect to database.";
		return $rv;
	}

	$sql = "SELECT l.`link_id`, l.`url`, ( SELECT count(*) from `tracking_clicks` c where c.`msg_id` = ? and c.`link_id` = l.`link_id` and c.`clicks` > 0 ) clickers "
	."FROM `tracking_links` l "
	."WHERE l.`msg_id` = ? and l.`link_id` > 0 "
	."ORDER BY l.`link_id` LIMIT 100 " ;
	$sth = $dbh->prepare($sql);
	$sth->execute($msgid,$msgid);
	$ret = $sth->fetchall_arrayref();
	if( !$ret or $dbh->err ) {
		$rv = "Database error: ".$dbh->errstr;
		$obj->{_CONTEXT}{STASH}{message_sql} = $sql;
	return $rv;
	}
	foreach ( @$ret ) { push @links, { id=>($_->[0]), url=>($_->[1]), rcpt=>($_->[2]), first=>($_->[3]) }; }

	$obj->{_CONTEXT}{STASH}{link_list} = \@links;
	$obj->{_CONTEXT}{STASH}{message_sql} = $sql;
	return $rv;
}
sub clicks {
	my($obj,$msgid,$linkid) = @_;
	my($rv) = '';
	my(@clicks) = ();
	my($sql,$ret,$sth);

	my $dbh = &List::db_get_handler();
	if(!$dbh) {
		$rv = "Unable to connect to database.";
		return $rv;
	}

	$linkid = 0 if($linkid eq 'none');

	$sql = "SELECT c.`rcpt_id`,c.`clicks`,c.`first_click`,c.`last_click` from `tracking_clicks` c where c.`msg_id` = ? and c.`link_id` = ? and c.`clicks` > 0 ";
	$sth = $dbh->prepare($sql);
	$sth->execute($msgid,$linkid);
	$ret = $sth->fetchall_arrayref();
	if( !$ret or $dbh->err ) {
		$rv = "Database error: ".$dbh->errstr;
		$obj->{_CONTEXT}{STASH}{message_sql} = $sql;
		return $rv;
	}
	foreach ( @$ret ) { 
		my $rcpt = $_->[0];
		$rcpt =~ s/\%40/\@/g;
		push @clicks, { rcpt=>$rcpt, count=>($_->[1]), first=>($_->[2]), last=>($_->[3]) }; 
	}

	$obj->{_CONTEXT}{STASH}{click_list} = \@clicks;
	$obj->{_CONTEXT}{STASH}{message_sql} = $sql;
	return $rv;
}
# Delete a message entirely from the database, by messageid
# Maybe this should ensure the message relates to this list?
sub delmsg {
	my($obj,$msgid) = @_;
	my($rv) = '';
	my($sql,$sth);
	my(@sql) = ();

	my $dbh = &List::db_get_handler();
	if(!$dbh) {
		$rv = "Unable to connect to database.";
		return $rv;
	}

	@sql = ( 
		"DELETE from `tracking_clicks` where `msg_id` = ?",
		"DELETE from `tracking_links`  where `msg_id` = ?",
		"DELETE from `tracking_msgs`   where `msg_id` = ?",
	);
	foreach $sql ( @sql ) {
	  $sth = $dbh->prepare($sql);
	  $sth->execute($msgid) if($sth);
	  if( $dbh->err ) {
		$rv = "Database error: ".$dbh->errstr;
		$obj->{_CONTEXT}{STASH}{message_sql} = $sql;
		return $rv;
	  }
	}

	return $rv;
}

##########################################################
# The below functions are used when in message mode

# Set up HTML for base tracking - 1px image link, etc
# [% Tracking.base %]
sub base {
	my($obj,@args) = @_;
	my($rv) = '';

	return $rv if(!$obj->{MSG_ID}); # not message mode
	if($obj->{_CONTEXT}{STASH}{'part'}) {
		return $rv if($obj->{_CONTEXT}{STASH}{'part'}{'type'}!~/html/);
	} else {
		return $rv if($obj->{_CONTEXT}{STASH}{'headers'}{'content-type'}!~/html/);
	}

	# Set up database entry for MSG_ID, RCPT_ID
	my $sql = "INSERT into `tracking_clicks` (`msg_id`,`rcpt_id`,`link_id`,`clicks`,`last_click`,`first_click`) VALUES(?,?,0,0,NULL,NULL)";

	my $dbh = &List::db_get_handler();
	if($dbh) {
		my $sth = $dbh->prepare($sql);
		my $rows = $sth->execute($obj->{MSG_ID},$obj->{RCPT_ID});
		if(! $rows ) { # returns 0 for error, 0E0 (==true) for no rows affected
			$rv .= "<!-- ERR: Message seems to have already been sent?\n     ".$dbh->errstr." -->\n";
		}
	} else {
		$rv .= "<!-- ERR: Unable to contact database -->";
	}


	# Base tracking links
	$rv = '<IMG SRC="'.$obj->{BASE_URL}.'/'.$obj->{MSG_ID}.'/'.$obj->{RCPT_ID}."\" WIDTH=1 HEIGHT=1 />\n";

	return $rv;
}
sub unsubscribe {
	my($obj,$msg,$listname) = @_;
	my($rv) = '';
	my($url);

	$listname = $obj->{_CONTEXT}{STASH}{'listname'} if(!$listname);
	$url = $obj->{_CONTEXT}{STASH}{'wwsympa_url'}.'/auto_signoff/'.$listname.'/'.$obj->{_CONTEXT}{STASH}{'user'}{'escaped_email'};

	return $rv if(!$url);
	if(($obj->{_CONTEXT}{STASH}{'part'} 
		and $obj->{_CONTEXT}{STASH}{'part'}{'type'}=~/html/)
		or $obj->{_CONTEXT}{STASH}{'headers'}{'content-type'}=~/html/) {
	   $msg = "Click here to unsubscribe from this list" if(!$msg);
	   $rv = "<A HREF=\"$url\">$msg</A>";
	} else {
	   $msg = "To unsubscribe from this list, visit" if(!$msg);
	   $rv = "$msg $url";
	}
	return $rv;
}

# Replace links with tracked links
sub _track_links {
	my($text, $context) = @_;
	my($linkdest);
	my(%links) = ();
	my($MSG_ID) = $context->{STASH}{Tracking}{MSG_ID};
	my($RCPT_ID) = $context->{STASH}{Tracking}{RCPT_ID};
	my($linksql)  = "INSERT into `tracking_links`  (`msg_id`,`link_id`,`url`) VALUES(?,?,?)";
	my($clicksql) = "INSERT into `tracking_clicks` (`msg_id`,`link_id`,`rcpt_id`,`clicks`,`last_click`,`first_click`) VALUES(?,?,?,0,NULL,NULL)";
	my($rows) = 0;
	my($LINK_ID) = $context->{STASH}{Tracking}{LINK_ID};
	my($BASE_URL) = $context->{STASH}{Tracking}{BASE_URL};
	my($lsth,$csth) = (undef,undef);
	my $dbh = &List::db_get_handler();

	return $text if(!$MSG_ID or !$RCPT_ID); # not message mode or not supported
	if($context->{STASH}{'part'}) {
		return $text if($context->{STASH}{'part'}{'type'}!~/html/);
	} else {
		return $text if($context->{STASH}{'headers'}{'content-type'}!~/html/);
	}

	# Check we have a working database connection
	if($dbh) {
		$lsth = $dbh->prepare($linksql);
		$csth = $dbh->prepare($clicksql);
	} else {
 		$text .= "\n<!-- ERROR: No database connection. -->\n";
		return $text;
	}

	# Identify all the links in the text block
	$LINK_ID = 1 if(!$LINK_ID);
	while( $text =~ s/href="?(https?:\/\/[^\s">]+)"?/href="\001$LINK_ID\001"/i  ) {
		$links{$LINK_ID}=$1;
		$LINK_ID += 1;
	}
	foreach my $lnk ( keys %links ) {
		$linkdest = $links{$lnk};
		#$text .= "<!-- adding $lnk,$linkdest -->\n";
		# Save to database if not already there links=($MSG_ID,$lnk,$linkdest)
		$lsth->execute($MSG_ID,$lnk,$linkdest) if($lsth);
		# Save to database clicks=($MSG_ID,$lnk,$RCPT_ID,0,0,0)
		if($csth) {
			$rows = $csth->execute($MSG_ID,$lnk,$RCPT_ID);
			if(! $rows ) {
				$text .= "\n<!-- Error: Cannot write click entry to database: $MSG_ID,$lnk \n     ".$dbh->errstr." -->";
			}
		}
		$text =~ s/\001$lnk\001/$BASE_URL\/$MSG_ID\/$RCPT_ID\/$lnk/;
	}
	$context->{STASH}{Tracking}{LINK_ID} = $LINK_ID;
	return $text;
}

# This defines a filter, Tracking, that adds tracking to any URLs in HTML A tags
# [% FILTER Tracking %] <A href=http://foo/>Click here</A> [% END %]
sub track_ff {
	# These are the params passed at plugin load time
	my ($context, @args) = @_;
	return sub {
		# This is the param passed at filter execute time
		my $text = shift;
		_track_links($text, $context, @args);
	}
}

1;

__END__

