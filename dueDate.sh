#!/bin/bash

################################################################################
# This Script will look to JAMF Pro to see when a laptop is to be returned to
# the IT office. For the most part this requires a bunch of overhead work,
# creating two extension attributes for date and another as a simple counter for
# the grace period. This is intended to run once every day when a computer is
# dropped into a smart group. I think that should work...

# Parameters are used to define the Encrypted Sting for the API Password, Return
# Date, Checkout Date.

################################################################################

#- Variables -#

# Get Today's date
today=$(date +%Y-%m-%d) # - date format 2019-02-09 returned as 1549753755
# Convert to Unix time for evaluation later in the script
todayUnix=$(date -j -f "%F" $today +%s)

# https://www.jamf.com/jamf-nation/discussions/27299/calling-osascript-not-working-in-high-sierra
# run osascripts as a user from jamf script
## Get the logged in user's name
loggedInUser=$( ls -l /dev/console | awk '{print $3}' )
## Get the UID of the logged in user
loggedInUID=$(id -u "$loggedInUser")

# This var is the number of days the loaner computer can go past it's Due Date
# before it's locked
daysLeft=7

# Variables for Date and Grace Period: Replace with your own values
# parameter 4 in Jamf is the encoded string - needs to match salt and hash below
# within DecryptString() function
encodedStr="$4"
# parameter 5 in Jamf - code to lock needs to be 6 digits.
deviceLock="$5"
# DD (Due Date) GP (Grace Period)
# Due Date Ext ID: 23 for testing
# paramater 6 in Jamf - extension attribute id of loan return date
DD="$6"
# paramater 7 in Jamf - extension attribute id of days left in grace period
# Grace Period Ext ID: 40 for testing
GP="$7"

#- Functions -#

# Using Encrypted Bash Strings from brysontyrrell just using openssl to encrypt  
# and decrypt password values
# Alternative format for DecryptString function
function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String"
    # Salt and local Code generated in another file
    local SALT="4871e326e09e7cf3"
    local K="d5203ebbc10b79e4787711aa"
    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "$SALT" -k "$K"
}
# API Vars
apiURL=https://jamfpro.example.edu:8443/JSSResource
apiUser=API
apiPass=$(DecryptString $encodedStr)

# Check for Serial Number
function GetSN() {
	system_profiler SPHardwareDataType | awk '/Serial/{print $4}'
}

# Check JAMF Pro ID using SN
function GetJamfID(){
	curl -sku $apiUser:$apiPass -H "Accept: text/xml" $apiURL/computers/serialnumber/$(GetSN) | xmllint --xpath '/computer/general/id/text()' -
}

# Get Due Date from JAMF Pro
function GetDueDate(){
	# Require argument $1 for comptuer's ID

	# Command subsitiution
	jssDue=$(curl -sku $apiUser:$apiPass -H "Accept: text/xml" $apiURL/computers/id/$1/subset/extension_attributes | xmllint --xpath "//*[id=$DD]/value/text()" -)
	# If jssDue returns a zero length string, the following command will produce a string
	# If jssDue has a value, it will return it's value to the command line
	if [[ -z $jssDue ]]
	then
		echo "This computer ID does not have a vaild Due Date"
    # The computer shouldnt have been in this smart group exit with error
    exit 1
	else
		echo $jssDue
		dueDate=$(date -j -f "%F" $jssDue +%s)
	fi
}

#- Sanity Check -#
# Is the code from Jamf 6 digits?
if [[ $deviceLock =~ ^[0-9]{6,6}$ ]]
then
  echo "code is valid"
else
  echo "code is invalid"
  exit 1
fi

#- Script Logic -#

# Test of function - gets the due date of of a computer
# To run on a computer use the code below, for testing use JSSID 57
GetDueDate $(GetJamfID)
echo $(GetDueDate $(GetJamfID))
#GetDueDate 57

# Basic logic of the script, check if the jamf data suggests that the date is overdue.
OverDueBy=$(curl -sku $apiUser:$apiPass -H "Accept: text/xml" $apiURL/computers/id/$(GetJamfID)/subset/extension_attributes | xmllint --xpath "//*[id=$GP]/value/text()" -)
if [[ $todayUnix -ge $dueDate ]]
then
	echo Compuer is past its loan date
	# Updated JSS OverDueBy Date by a day
	if [[ $OverDueBy != $daysLeft ]]
	then
		OverDueBy=$((OverDueBy+1))
    	cat << EOF > /private/tmp/ea.xml
<computer>
    <extension_attributes>
        <extension_attribute>
            <id>$GP</id>
            <value>$OverDueBy</value>
        </extension_attribute>
    </extension_attributes>
</computer>
EOF
	curl -sku $apiUser:$apiPass -H "Content-type: text/xml" $apiURL/computers/id/$(GetJamfID)/subset/extension_attributes -T /private/tmp/ea.xml -X PUT
	fi

	# Notify User: if we are within the grace peirod of 7 days, display this message
	if [[ $((daysLeft-OverDueBy)) > 0 ]]
	then
    echo notifying user of their due date
    /bin/launchctl asuser "${loggedInUID}" sudo -iu "${loggedInUser}" /usr/bin/osascript -e 'tell application "System Events" to display dialog "This computer was scheduled to be returned to the EBIO IT office in Ramaley N122D by '$jssDue'. This computer will lock after: '$((daysLeft-OverDueBy))' days. Contact ebio-helpdesk@colorado.edu if you need assistance." buttons {"OK"} default button 1 with icon {"/usr/local/ebio/culogo.png"}'
	else
	# Lock computer if the grace period has expired
		echo "Locking Computer with code 123456"
    #curl -sku $apiUser:apiPass -H "Content-type: text/xml" $apiURL/computercommands/command/DeviceLock/passcode/$deviceLock/id/$(GetJamfID) -X POST
  fi
else
	echo computer $(GetSN) not overdue
	# Check that the Overdue Day Extension Attribute is set to 0
	# update the value to 0, this would occur automatically if somone forgot to change the value before loaning a computer (if the loan date is within its scheduled date, the overdue limit is set to 0)
	if [[ $OverDueBy != 0 ]]
	then
	# Create xml file to copy the data to JAMF
    cat << EOF > /private/tmp/ea.xml
<computer>
	<extension_attributes>
		<extension_attribute>
			<id>$GP</id>
			<value>0</value>
		</extension_attribute>
	</extension_attributes>
</computer>
EOF
	curl -sku $apiUser:$apiPass -H "Content-type: text/xml" $apiURL/computers/id/$(GetJamfID)/subset/extension_attributes -T /private/tmp/ea.xml -X PUT
	fi
fi
exit 0
