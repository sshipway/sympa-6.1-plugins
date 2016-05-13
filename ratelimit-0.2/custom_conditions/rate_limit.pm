#!/usr/bin/perl
#
# This function returns TRUE if the message should be dropped
# Params:
#   listname, subscriber (optional), max per timewindow (Day), unique param
#
# CustomCondition::rate_limit([listname],[sender],10,[header->Message-ID]) smtp,dkim,smime reject(tt2=rate_limit)
#
# Version 0.2
#
# History
# 0.1 - first release
# 0.2 - standardised field names.  Fixed insert test to work correctly

package CustomCondition::rate_limit;
use strict;
use Log; 
my($DEBUG) = 'debug2'; 
my($WINDOW) = 86400; # seconds (one day)

sub verify {
  my($listname,$sender,$maxrate) = @_;
  my($count);
  my($sql,$dbh,$sth,$rows,$ret,$lastmsg);
  my($now) = time();

  if($sender) {
    do_log ($DEBUG, "rate_limit: Rate limit for list $listname, subscriber $sender is $maxrate/hr");
  } else {
    $sender = '';
    do_log ($DEBUG, "rate_limit: Rate limit for list $listname is $maxrate/hr");
  }
  $dbh = &List::db_get_handler();
  if(!$dbh) {
    do_log ('err', "rate_limit: Unable to connect to database");
    return undef;
  }
  # obtain current number
  $count = 0; $lastmsg = 0;
  $sql  = "SELECT `count_rate`,UNIX_TIMESTAMP(`last_rate`) FROM `rate_limit` WHERE `name_rate` = ? AND `user_rate` = ? LIMIT 1 ";
  $sth  = $dbh->prepare($sql);
  $ret  = $sth->execute($listname,$sender);
  if(!$ret) {
    do_log ('warning', "rate_limit: Cannot search database: (".$dbh->err.") ",$dbh->errstr) if($dbh->err);
    $sql = "CREATE TABLE IF NOT EXISTS `rate_limit` ( `name_rate` VARCHAR(100) NOT NULL, `user_rate` VARCHAR(100) DEFAULT NULL, `count_rate` INTEGER, `last_rate` DATETIME, PRIMARY KEY( `name_rate`, `user_rate` ) ) ";
    $ret = $dbh->do($sql);
    do_log ('err', "rate_limit: Cannot create table: ",$dbh->errstr)
	if(!$ret);
  } else {
    $rows = $sth->fetchall_arrayref();
    if( @$rows ) {
      $count = $rows->[0][0];
      $lastmsg = $rows->[0][1];
      do_log ($DEBUG, "rate_limit: Current count for list $listname, subscriber $sender is $count at time ".localtime($lastmsg));
    }
  }
  # increment count or create new record
  # set to 0 if new hour
  if(!$count) {
    $count = 1;
  } else {
    if( int($now / $WINDOW) != int($lastmsg / $WINDOW) ) {
      # different hour
      $count = 1; 
    } else {
      $count += 1;
    }
  }
  # update database
  $sql = "UPDATE `rate_limit` SET `count_rate` = ?, `last_rate` = FROM_UNIXTIME( ? ) WHERE `name_rate` = ? AND `user_rate` = ?";
  $sth  = $dbh->prepare($sql);
  $ret  = $sth->execute($count,$now,$listname,$sender);
  do_log ($DEBUG, "rate_limit: Updating for list $listname, subscriber $sender with $count at time ".localtime($now));
  if(!$ret or !$sth->rows) {
    do_log ($DEBUG, "rate_limit: Trying to create record for $listname, $sender");
    $sql = "INSERT INTO `rate_limit` (`count_rate`,`last_rate`,`name_rate`,`user_rate`) VALUES( ?, FROM_UNIXTIME( ? ), ?, ? )";
    $sth  = $dbh->prepare($sql);
    $ret  = $sth->execute($count,$now,$listname,$sender);
    if(!$ret) {
      do_log ('err', "rate_limit: Cannot update database: (".$dbh->err.") ",$dbh->errstr);
    }
  } else {
    do_log ($DEBUG, "rate_limit: Updated $ret rows");
  }
 
  # Threshold 
  return 1 if($count > $maxrate);
  return 0; # pass
}
## Packages must return true.
1;
