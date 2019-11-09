import ballerina/config;
import ballerina/log;
import ballerina/stringutils;
import wso2/twilio;

const INVALID_NO = "Invalid no";

twilio:TwilioConfiguration twilioConfig = {
    accountSId: config:getAsString("eclk.sms.twilio.accountSid"),
    authToken: config:getAsString("eclk.sms.twilio.authToken"),
    xAuthyKey: config:getAsString("eclk.sms.twilio.authyApiKey")
};

twilio:Client twilioClient = new(twilioConfig);

// Keeps registered sms recipients in-memory. Values are populated in every service init and recipient registration
string[] mobileSubscribers = [];
string sourceMobile = config:getAsString("eclk.sms.twilio.source");

# Send SMS notification to all the subscribers.
#
# + electionCode - The respective code that represents the type of election
# + resultCode - The predefined code for a released result
function sendSMS(string electionCode, string resultCode) {
    string? retrievedData = getDivision(resultCode);
    string division = retrievedData is string ? retrievedData : resultCode;
    string message  = "Results will be releasing soon for " + electionCode +  "/" + division + "(" + resultCode + ")";

    foreach string targetMobile in mobileSubscribers {
        if (targetMobile == INVALID_NO) {
            continue;
        }
        var response = twilioClient->sendSms(sourceMobile, targetMobile, message);
        if response is error {
            log:printError(electionCode +  "/" + division + " message sending failed \'" + targetMobile +
                           "\' due to error:" + <string> response.detail()?.message);
        }
    }
}

# Get the respective division name for a given resultCode.
#
# + resultCode - The predefined code for a released result
# + return - The division name if resultCode is valid, otherwise nil
function getDivision(string resultCode) returns string? {
    return divisionCodeMap.hasKey(resultCode) ? divisionCodeMap.get(resultCode) : ();
}

# Validate and sanitize local mobile number into the proper format.(+94771234567).
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

    if (mobile.startsWith("0") && mobile.length() == 10) {
        return "+94" + mobile.substring(1);
    }
    if (mobile.startsWith("94") && mobile.length() == 11) {
        return "+" + mobile;
    }
    // Allow only the local mobile numbers to register via public API. International number are avoided.
    error err = error(ERROR_REASON, message = "Invalid mobile number. Resend the request as follows: If the " +
                                    "mobile no is 0771234567, send request as \"/sms/94771234567\". ");
    return err;
}

# Register recipient in the mobileSubscribers list and persist in the smsRecipients db table.
#
# + mobileNo - The recipient number
# + return - The status of registration or operation error
function registerAsSMSRecipient(string mobileNo) returns string|error {

    foreach string recipient in mobileSubscribers {
        if (recipient == mobileNo) {
            error err = error(ERROR_REASON, message = "Registration failed: " + mobileNo + " is already registered");
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

    return "Successfully registered: " + mobileNo;
}

# Unregister recipient from the mobileSubscribers array and remove from the smsRecipients db table.
#
# + mobileNo - The recipient number
# + return - The status of deregistration or operation error
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
        return "Successfully unregistered: " + mobileNo;
    }
    error err = error(ERROR_REASON, message = "Unregistration failed: " + mobileNo + " is not registered");
    return err;
}