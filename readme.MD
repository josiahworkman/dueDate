# Due Date
A brute force method for requiring users to return checkout laptops. This is a script used in conjunction with JAMF to "encourage" users to return their laptops on time. This project was created as a learning experience after taking the JAMF 300 certification course.

It became necessary to implement some sort of automatic notifying system after I had loaned out over ten laptops. Keeping track of dates in JAMF and emailing users when their loan period expired was needlessly complicated. This project attempts to automate as much of that process as possible.

When a laptop is loaned out to a user, I now assign their username to the laptop within JAMF. In addition, I set the agreed upon return date to an extension attribute. After that date the user (or any user of that laptop) is notified to return the laptop. After seven days the laptop is locked and if a user hasn't returned the laptop within the grace period they certainly walk into the office with the locked laptop.

If the laptop is not past it's due date the script just executes and submits a log to JAMF.

## Requirements

### Encrypted Strings
I've leaned on several existing projects for to implement some of the encryption elements, thanks [brysontyrrell](https://github.com/brysontyrrell/EncryptedStrings) for creating the quick method for encryption. EncryptedStrings are used to authenticate to the JAMF API during various parts of the script.

### Extension Attribute Requirements
Two extension attributes are required. The first extension attribute tracks the number of days any given laptop is past it's due date. The other extension attribute stores the due date of a laptop. It's necessary to grab the ID of both of those extension attributes and assign that ID value within this script.

The grace period extension attribute can track a simple integer data type. The return date extension attribute should collect date in the (yyyy-mm-dd). Examples below:
![extension attribute example](ext.png "extension attribute example")

### Policy Requirements
A JAMF policy which runs the script once a day, on your set of loaner laptops. The script requires at that you at least pass the API password and lock code from this policy.

### API Requirements
You need to set an API account with access to at least view and modify computers for the script to be able to interact with the values. I'm just passing the username of my API account into the script itself. The password is encoded using the EncryptedStrings project linked above. 
