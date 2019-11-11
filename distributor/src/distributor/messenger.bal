import ballerina/config;
import ballerina/log;
import ballerina/stringutils;
import wso2/twilio;

twilio:TwilioConfiguration twilioConfig = {
    accountSId: config:getAsString("eclk.sms.twilio.accountSid"),
    authToken: config:getAsString("eclk.sms.twilio.authToken"),
    xAuthyKey: config:getAsString("eclk.sms.twilio.authyApiKey", "") // required only if Authy related APIs are used
};

twilio:Client twilioClient = new(twilioConfig);

// Keeps registered sms recipients in-memory. Values are populated in every service init and recipient registration
map<string> mobileSubscribers = {};
string sourceMobile = config:getAsString("eclk.sms.twilio.source");
boolean validTwilioAccount = false;

# Send SMS notification to all the subscribers.
#
# + result - The inbund results
function sendSMS(Result result) {
    string electionCode = result.election;
    string electionType = "/" + result.'type;
    string level = result.jsonResult.level is error ? "": <string> result.jsonResult.level;
    string message = "";

    if level == "POLLING-DIVISION" {
        string electoralDistrict = "/" + result.jsonResult.ed_name.toString();
        string pollingDivision = "/" + result.jsonResult.pd_name.toString();
        message  = "Await polling division results for " + electionCode + electionType + electoralDistrict + pollingDivision;

    } else if level == "ELECTORAL-DISTRICT" {
        string electoralDistrict = "/" + result.jsonResult.ed_name.toString();
        message  = "Await electoral results for " + electionCode + electionType + electoralDistrict;

    } else if level == "NATIONAL-FINAL" {
        message  = "Await NATIONAL-FINAL results for " + electionCode + electionType;
    } else {
        message  = "Await results for " + electionCode + electionType + "/" + result.code;
    }

    map<string> currentMobileSubscribers = mobileSubscribers;
    currentMobileSubscribers.forEach(function (string recipientUsername) {
        var response = twilioClient->sendSms(sourceMobile, currentMobileSubscribers[recipientUsername], message);
        if response is error {
            log:printError(electionCode +  "/" + division + " message sending failed for \'" + targetMobile +
                           "\' due to error:" + <string> response.detail()?.message);
        }
    });
}

# Validate and sanitize local mobile number into the proper format.(+94771234567).
#
# + mobileNo - User provided mobile number
# + return - Formatted mobile number or the error
function validate(string mobileNo) returns string|error {
    string mobile = <@untained> mobileNo.trim();

    boolean number = stringutils:matches(mobile, "^[0-9]*$");

    if !number {
        return error(ERROR_REASON, message = "Invalid mobile number. Given mobile number contains non numeric " +
                                                  "characters: " + mobile);
    }

    if (mobile.startsWith("0") && mobile.length() == 10) {
        return "+94" + mobile.substring(1);
    }
    if (mobile.startsWith("94") && mobile.length() == 11) {
        return "+" + mobile;
    }
    // Allow only the local mobile numbers to register via public API. International number are avoided.
    return error(ERROR_REASON, message = "Invalid mobile number. Resend the request as follows: If the " +
                                    "mobile no is 0771234567, send POST request to  \'/sms\' with JSON payload " +
                                    "\'{\"username\":\"myuser\", \"mobile\":\"0771234567\"}\'");
}

# Register recipient in the mobileSubscribers list and persist in the smsRecipients db table.
#
# + username - The recipient username
# + mobileNo - The recipient number
# + return - The status of registration or operation error
function registerAsSMSRecipient(string username, string mobileNo) returns string|error {

    if mobileSubscribers.hasKey(username) {
        string errMsg = "Registration failed: username:" + username + " is already registered with mobile:" + mobileNo;
        log:printError(errMsg);
        return error(ERROR_REASON, message = errMsg);
    }

    // Persist recipient number in database
    var status = dbClient->update(INSERT_RECIPIENT, username, mobileNo);
    if status is error {
        log:printError("Failed to persist recipient no in database", status);
        //return status;
        return error(ERROR_REASON, message = "Registration failed: username:" + username + " mobile:" + mobileNo + ": " +
                                            <string> status.detail()?.message);
    }
    mobileSubscribers[username] = mobileNo;

    return "Successfully registered: username:" + username + " mobile:"  + mobileNo;
}

# Unregister recipient from the mobileSubscribers map and remove from the smsRecipients db table.
#
# + username - The recipient username
# + mobileNo - The recipient number
# + return - The status of deregistration or operation error
function unregisterAsSMSRecipient(string username, string mobileNo) returns string|error {

    // Remove persisted recipient number from database
    var status = dbClient->update(DELETE_RECIPIENT, username, mobileNo);
    if status is error {
        log:printError("Failed to remove recipient from the database", status);
        return error(ERROR_REASON, message = "Unregistration failed: username:" + username + " mobile:" + mobileNo + ": " +
                                                    <string> status.detail()?.message);
    }

    if mobileSubscribers.hasKey(username) {
        if (mobileSubscribers.get(username) == mobileNo) {
            return "Successfully unregistered: username:" + username + " mobile:" + mobileSubscribers.remove(username);
        }
    }

    string errMsg = "Unregistration failed: No entry found for username:" + username + " mobile:"  + mobileNo;
    log:printError(errMsg);
    return error(ERROR_REASON, message = errMsg);
}
