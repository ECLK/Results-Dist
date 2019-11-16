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

function getAwaitResultsMessage(string electionCode, string resultType, string resultCode, string level, 
                                string? ed_name, string? pd_name) returns string {
    string message;

    match level {
        LEVEL_PD => {
            string electoralDistrict = "/" + (ed_name ?: "<unknown electoral district>");
            string pollingDivision = "/" + (pd_name ?: "<unknown polling division>");
            message  = "Await " + (resultCode.endsWith("P") ? "POSTAL" : "POLLING-DIVISION") + " results for " 
                    + electionCode + resultType + electoralDistrict + pollingDivision;
        }
        LEVEL_ED => {
            string electoralDistrict = "/" + (ed_name ?: "<unknown electoral district>");

            message  = "Await ELECTORAL-DISTRICT results for " + electionCode + resultType + electoralDistrict;
        }
        LEVEL_NF => {
            message  = "Await NATIONAL-FINAL results for " + electionCode + resultType;
        }
        _ => {
            message  = "Await results for " + electionCode + resultType + "/" + resultCode;
        }
    }

    return message + "(" + resultCode + ")";
}

# Send SMS notification to all the subscribers.
#
# + message - The message to send
# + resultId - The message identification
function sendSMS(string message, string resultId) {
    map<string> currentMobileSubscribers = mobileSubscribers;
    if (currentMobileSubscribers.length() > 0) {
        log:printInfo("Sending SMS for " + resultId);
    }
    foreach string targetMobile in currentMobileSubscribers {
        log:printInfo("Sending SMS for " + resultId + " to " + targetMobile);
        var response = twilioClient->sendSms(sourceMobile, targetMobile, message);
        if response is error {
            log:printError("Message sending failed for \'" + targetMobile + "\' due to error:" +
                            <string> response.detail()?.message);
        }
    }
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
        return error(ERROR_REASON, message = "Registration failed: username:" + username + " mobile:" + mobileNo
                                            + ": " + <string> status.detail()?.message);
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
        return error(ERROR_REASON, message = "Unregistration failed: username:" + username + " mobile:" + mobileNo +
                                            ": " + <string> status.detail()?.message);
    }

    if mobileSubscribers.hasKey(username) && mobileSubscribers.get(username) == mobileNo {
        return "Successfully unregistered: username:" + username + " mobile:" + mobileSubscribers.remove(username);
    }

    string errMsg = "Unregistration failed: No entry found for username:" + username + " mobile:"  + mobileNo;
    log:printError(errMsg);
    return error(ERROR_REASON, message = errMsg);
}
