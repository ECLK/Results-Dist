import ballerina/config;
import ballerina/log;
import ballerina/stringutils;

import wso2/twilio;

const INVALID_NO = "Invalid no";
const string CREATE_RECIPIENT_TABLE = "CREATE TABLE IF NOT EXISTS smsRecipients (" +
                                    "    mobileNo VARCHAR(50) NOT NULL," +
                                    "    PRIMARY KEY (mobileNo))";
const INSERT_RECIPIENT = "INSERT INTO smsRecipients (mobileNo) VALUES (?)";
const DELETE_RECIPIENT = "DELETE FROM smsRecipients WHERE mobileNo = ?";
const SELECT_RECIPIENT_DATA = "SELECT mobileNo FROM smsRecipients";

twilio:TwilioConfiguration twilioConfig = {
    accountSId: config:getAsString("eclk.sms.twilio.accountSid"),
    authToken: config:getAsString("eclk.sms.twilio.authToken"),
    xAuthyKey: config:getAsString("eclk.sms.twilio.authyApiKey")
};

twilio:Client twilioClient = new(twilioConfig);
// Contains registered sms recipients. Values are populated in every service init and recipient registration
string[] mobileSubscribers = [];
string sourceMobile = config:getAsString("eclk.sms.twilio.source");

# Create table with the SMS recipients and set up at module init time and load any data in there to
# memory to the mobileSubscribers. Panic if there's any issue.
function createSmsRecipientsTable() {

    _ = checkpanic dbClient->update(CREATE_RECIPIENT_TABLE);

    // load recipients to in-memory array
    table<Recipient> retrievedNos = checkpanic dbClient->select(SELECT_RECIPIENT_DATA, Recipient);
    int count = 0;
    while (retrievedNos.hasNext()) {
        Recipient recipient = <Recipient> retrievedNos.getNext();
        count += 1;
        mobileSubscribers.push(recipient.number);
    }
    if (count > 0) {
        log:printInfo("Loaded " + count.toString() + " SMS recipients from database");
    }
}

# Send SMS notification to all the subscribers.
#
# + electionCode - The respective code that represents the type of election
# + resultCode - The predefined code for a released result
function sendSMS(string electionCode, string resultCode) {
    string|error retrievedData = getDivision(resultCode);
    string division = retrievedData is string ? retrievedData : resultCode;
    string message  = "Results will be releasing soon for " + electionCode +  "/" + division;

    foreach string targetMobile in mobileSubscribers {
        if (targetMobile == INVALID_NO) {
            continue;
        }
        var response = twilioClient->sendSms(sourceMobile, targetMobile, message);
        if response is  twilio:SmsResponse {
            log:printInfo("Successfully delivered - " + targetMobile);
        } else {
            log:printError(electionCode +  "/" + division + " message sending failed - " + targetMobile +
                           " due to error:" + <string> response.detail()?.message);
        }
    }
}

# Get the respective division name for a given resultCode.
#
# + resultCode - The predefined code for a released result
# + return - The division name if resultCode is valid, otherwise error
function getDivision(string resultCode) returns string|error {
    return divisionCodeMap.get(resultCode);
}

# Sanitize and validate local mobile no into the proper format.(+94771234567).
#
# + mobileNo - User provided mobile number
# + return - Formatted mobile number or the error
function validate(string mobileNo) returns string|error {
    string mobile = <@untained> mobileNo.trim();

    boolean number = stringutils:matches(mobile, "^[0-9]*$");

    if !number {
        error err = error(ERROR_REASON, message = "Invalid mobile number. Given mobile number contains non numeric " +
                                                  "characters: " + mobile);
        return err;
    }

    if (mobile.startsWith("0")) {
        return "+94" + mobile.substring(1);
    }
    if (mobile.startsWith("94")) {
        return "+" + mobile;
    }

    if (mobile.length() != 12) {
        error err = error(ERROR_REASON, message = "Invalid mobile number. Resend the request as follows: If the " +
                                        "mobile no is 0771234567, send request as \"/sms/94771234567\". ");
        return err;
    }
    return mobile;
}

# Register recipient in the SMS publisher for SMS notification.
#
# + mobileNo - The recipient number
# + return - The status of registration
function registerAsSMSRecipient(string mobileNo) returns string|error {

    foreach string recipient in mobileSubscribers {
        if (recipient == mobileNo) {
            log:printError("Registration failed: " + mobileNo + " is already registered.");
            error err = error(ERROR_REASON, message = "Registration failed: " + mobileNo + " is already registered.");
            return err;
        }
    }

    // Persist recipient number in database
    var status = dbClient->update(INSERT_RECIPIENT, mobileNo);
    if status is error {
        log:printError("Failed to persist recipient no in database: " + status.toString());
        return status;
    }
    // Update the mobileSubscribers array
    mobileSubscribers.push(mobileNo);

    log:printInfo("Successfully registered: " + mobileNo);
    return "Successfully registered: " + mobileNo;
}

# Unregister recipient from the SMS publisher.
#
# + mobileNo - The recipient number
# + return - The status of deregistration
function unregisterAsSMSRecipient(string mobileNo) returns string|error {

    // Remove persisted recipient number from database
    var status = dbClient->update(DELETE_RECIPIENT, mobileNo);
    if status is error {
        log:printError("Failed to remove recipient from the database: " + status.toString());
        return status;
    }

    int index = 0;
    boolean found = false;
    foreach string recipient in mobileSubscribers {
        if (recipient == mobileNo) {
            found = true;
            break;
        }
        index += 1;
    }
    // Assign special string to particular array element as to remove the recipient from the mobileSubscribers array
    if found {
        mobileSubscribers[index] = INVALID_NO;
        log:printInfo("Successfully unregistered: " + mobileNo);
        return "Successfully unregistered: " + mobileNo;
    }
    log:printError("Failed to remove recipient from in-memory map: " + mobileNo);
    error err = error(ERROR_REASON, message = "Unregistration failed: " + mobileNo + " is already unregistered.");
    return err;
}