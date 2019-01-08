#!/bin/bash

################################################################################
# This Script will look to JAMF Pro to see when a laptop is to be returned to
# the EBIO IT office For the most part this requires a bunch of overhead work,
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

# This var is the number of days the loaner computer can go past it's Due Date before it's locked
daysLeft=7

# Variables for Date and Grace Period
# DD (Due Date) GP (Grace Period)
DD=23
GP=40
encodedStr="U2FsdGVkX19IceMm4J5883SZLODUYcwZVFdxHqmJ5Ek=" # turn into parameter for JAMF

#- Functions -#

# Using Encrypted Bash Strings from brysontyrrell, thanks fam
# Alternative format for DecryptString function
function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String"
    # Salt and local Code generated in another file
    local SALT="4871e326e09e7cf3"
    local K="d5203ebbc10b79e4787711aa"
    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "$SALT" -k "$K"
}
# API Vars
apiURL=https://panda.colorado.edu:8443/JSSResource
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
	jssDue=$(curl -sku $apiUser:$apiPass -H "Accept: text/xml" $apiURL/computers/id/$1/subset/extension_attributes | xmllint --xpath "//*[id=23]/value/text()" -)
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

#- Script Logic -#

# Test of function - gets the due date of of a computer
# To run on a computer use the code below, for testing use JSSID 57
GetDueDate $(GetJamfID)
echo $(GetDueDate $(GetJamfID))
#GetDueDate 57

# Basic logic of the script, check if the jamf data suggests that the date is overdue.
OverDueBy=$(curl -sku $apiUser:$apiPass -H "Accept: text/xml" $apiURL/computers/id/$(GetJamfID)/subset/extension_attributes | xmllint --xpath "//*[id=40]/value/text()" -)
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
            <id>40</id>
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
		osascript -e 'tell app "System Events" to display dialog "This laptop needs to be returned to Ramaley N122D. This Computer will lock after: '$((daysLeft-OverDueBy))' days" buttons {"OK"} default button 1 with icon {"/usr/local/ebio/culogo.png"}'
	fi
	# Lock computer if the grace period has expired
		echo "Locking Computer with code 123456"

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
            <id>40</id>
            <value>0</value>
        </extension_attribute>
    </extension_attributes>
</computer>
EOF
	curl -sku $apiUser:$apiPass -H "Content-type: text/xml" $apiURL/computers/id/$(GetJamfID)/subset/extension_attributes -T /private/tmp/ea.xml -X PUT
	fi
fi
exit 0
