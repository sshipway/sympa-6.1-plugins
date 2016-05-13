#!/bin/sh
#
# Test the SOAP API

# This one cannot create lists or add/remove subscribers
#APP=steve_ro
# This one cannot create lists
#APP=steve_nc
# This app can do anything
APP=application
PASS=password
USER=nobody@auckland.ac.nz
DOMAIN=sympa.test.auckland.ac.nz
LIST=sshi052@$DOMAIN
MAIL=foo@steveshipway.org
TESTLIST=test-$$

SOAPCLIENT=/usr/share/sympa/bin/sympa_soap_client.pl

echo "Using SOAP API to $DOMAIN as application user [$APP]"
echo "With scenario rights of user [$USER]"
echo ""
echo "Testing list info"

$SOAPCLIENT --soap_url=https://$DOMAIN/sympasoap --trusted_application=$APP --trusted_application_password="$PASS" --proxy_vars="USER_EMAIL=$USER" --service=info --service_parameters=$LIST

echo ""
echo "Testing adding a subscriber"

$SOAPCLIENT --soap_url=https://$DOMAIN/sympasoap --trusted_application=$APP --trusted_application_password="$PASS" --proxy_vars="USER_EMAIL=$USER" --service="add" --service_parameters=$LIST,$MAIL,"Test user",0

echo ""
echo "Test self-subscription"

$SOAPCLIENT --soap_url=https://$DOMAIN/sympasoap --trusted_application=$APP --trusted_application_password="$PASS" --proxy_vars="USER_EMAIL=$MAIL" --service="subscribe" --service_parameters=$LIST

echo ""
echo "Test subscriber details"

$SOAPCLIENT --soap_url=https://$DOMAIN/sympasoap --trusted_application=$APP --trusted_application_password="$PASS" --proxy_vars="USER_EMAIL=$MAIL" --service="getDetails" --service_parameters=$LIST

echo ""
echo "List members"

$SOAPCLIENT --soap_url=https://$DOMAIN/sympasoap --trusted_application=$APP --trusted_application_password="$PASS" --proxy_vars="USER_EMAIL=$MAIL" --service="review" --service_parameters=$LIST

echo ""
echo "Removing a subscriber"

$SOAPCLIENT --soap_url=https://$DOMAIN/sympasoap --trusted_application=$APP --trusted_application_password="$PASS" --proxy_vars="USER_EMAIL=$USER" --service="del" --service_parameters=$LIST,$MAIL

echo ""
echo "Test self-unsubscription"

$SOAPCLIENT --soap_url=https://$DOMAIN/sympasoap --trusted_application=$APP --trusted_application_password="$PASS" --proxy_vars="USER_EMAIL=$MAIL" --service="signoff" --service_parameters=$LIST

echo ""
echo "Creating a list"

$SOAPCLIENT --soap_url=https://$DOMAIN/sympasoap --trusted_application=$APP --trusted_application_password="$PASS" --proxy_vars="USER_EMAIL=$USER" --service="createList" --service_parameters=$TESTLIST,"Test list",uoa_announce,"Test list",test

echo ""
echo "Deleting a list"

$SOAPCLIENT --soap_url=https://$DOMAIN/sympasoap --trusted_application=$APP --trusted_application_password="$PASS" --proxy_vars="USER_EMAIL=$USER" --service="closeList" --service_parameters=$TESTLIST

