//import ballerina/config;
import ballerina/io;
import ballerina/http;
import ballerina/log;
import ballerina/stringutils;

import laf/ideamart;

const SOURCE_ADDRESS = "tel:947778882543";
const INVALID_NO = "Invalid no";
const string CREATE_RECIPIENT_TABLE = "CREATE TABLE IF NOT EXISTS smsRecipients (" +
                                    "    mobileNo VARCHAR(50) NOT NULL," +
                                    "    PRIMARY KEY (mobileNo))";
const INSERT_RECIPIENT = "INSERT INTO smsRecipients (mobileNo) VALUES (?)";
const DELETE_RECIPIENT = "DELETE FROM smsRecipients WHERE mobileNo = ?";
const SELECT_RECIPIENT_DATA = "SELECT mobileNo FROM smsRecipients";


// Contains registered sms recipients. Values are populated in every service init and recipient registration
string[] mobileSubscribers = [];
map<string> resultCodeMap = { "01A": "Colombo-North", "01B": "Colombo-Central", "01C":"BORELLA", "01D": "COLOMBO-EAST" };

type Recipient record {|
    string number;
|};

http:ClientConfiguration clientEPConfig = {
    secureSocket: {
        trustStore: {
            path: "${ballerina.home}/bre/security/ballerinaTruststore.p12",
            password: "ballerina"
        },
        protocol: {
            name: "TLS"
        },
        ciphers: ["TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA"]
    }
};

ideamart:IdeaMartConfiguration ideaMartConfig = {
    applicationId : config:getAsString("eclk.sms.appId", "APP_000001"),
    password : config:getAsString("eclk.sms.password", "password"),
    baseURL : config:getAsString("eclk.sms.baseURL", "http://localhost:7000"),
    clientConfig : clientEPConfig
};

ideamart:Client ideaMartClient = new(ideaMartConfig);

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
    io:println(message);

    foreach string mobileNo in mobileSubscribers {
        if (mobileNo == INVALID_NO) {
            continue;
        }

        var response = ideaMartClient->sendSMS([mobileNo], message, SOURCE_ADDRESS);
        if (response is error) {
            log:printError(electionCode +  "/" + division + " message has not delivered to " + mobileNo +
                                " due to error:" + <string> response.detail()?.message);
        }

        string statusCode = <string> response;
        if (statusCode == "E1318" || statusCode == "E1603") { // retry once for retryable status codes
            var secondResponse = ideaMartClient->sendSMS([mobileNo], message, SOURCE_ADDRESS);
            //TODO handle error
        } else if (statusCode == "S1000") {
            log:printInfo("Successfully delivered to " + mobileNo);
        } else {
            log:printError("Message not delivered to " + mobileNo + " due to error:" + statusCode);
        }
    }
}

# Get the respective division name for a given resultCode.
#
# + resultCode - The predefined code for a released result
# + return - The division name if resultCode is valid, otherwise error
function getDivision(string resultCode) returns string|error {
    return resultCodeMap.get(resultCode);
}

# Sanitize mobile no into valid format.(94771234567).
#
# + mobileNo - User provided mobile number
# + return - Formatted mobile number
function sanitize(string mobileNo) returns string {
    string mobile = <@untained> mobileNo.trim();
    if (mobile.startsWith("0")) { // Do we allow only local mobile nos?
        return stringutils:replace(mobile, "0","94");
    }
    if (mobile.startsWith("+94")) {
        return stringutils:replace(mobile, "+94","94");
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

    // Persist recipient no in database
    var status = dbClient->update(INSERT_RECIPIENT, mobileNo);
    if (status is error) {
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

    // Persist recipient no in database
    var status = dbClient->update(DELETE_RECIPIENT, mobileNo);
    if (status is error) {
        log:printError("Failed to remove recipient from the database: " + status.toString());
        return status;
    }

    int index = 0;
    foreach string recipient in mobileSubscribers {
        if (recipient == mobileNo) {
            break;
        }
        index = index + 1;
    }
    // Assign special string to particular array element as to remove the recipient from the mobileSubscribers array
    mobileSubscribers[index] = INVALID_NO;

    log:printInfo("Successfully unregistered: " + mobileNo);
    return "Successfully unregistered: " + mobileNo;
}