import ballerina/auth;
import ballerina/http;
import ballerina/io;
import ballerina/log;

import maryamzi/sound;

boolean wantJson = false;
boolean wantXml = false;
boolean wantHtml = false;
boolean sortedHtml = false;

boolean addCode = false;

public type ElectionType ELECTION_TYPE_PRESIDENTIAL|ELECTION_TYPE_PARLIAMENTARY;

http:OutboundAuthConfig? auth = ();
http:Client? imageClient = ();
ElectionType electionType = ELECTION_TYPE_PARLIAMENTARY;

// what formats does the user want results saved in?
public function main (string? username = (),        // my username  
                      string? password = (),        // my password  
                      boolean await = false,        // do I want the await results notification?
                      boolean 'json = false,        // do I want json?
                      boolean 'xml = false,         // do I want xml?
                      boolean image = false,        // do I want the image?
                      boolean html = false,         // do I want HTML?
                      //boolean sorted = true,        // do I want HTML results sorted highest to lowest
                      boolean wantCode = false,     // do I want electionCode in the filename
                      string homeURL = "https://mediaresultshub.ecdev.opensource.lk" // where do I connect at
                    ) returns @tainted error? {
    // Set the election type
    electionType = ELECTION_TYPE_PARLIAMENTARY;

    if electionType == ELECTION_TYPE_PARLIAMENTARY {
        getFileNameBase = getParliamentaryFileNameBase;
        generateHtml = generateParliamentaryResultHtml;
    }

    // check whether the user wants electionCode in the filename
    addCode = <@untainted>wantCode;

    // check what format the user wants results in
    wantJson = <@untainted>'json;
    wantXml = <@untainted>'xml;
    wantHtml = <@untainted>html;
    if !(wantJson || wantXml || wantHtml) {
        // default to giving json
        wantJson = true;
    }
    //sortedHtml = <@untainted>sorted;

    // set up auth
    string? token = ();
    if (username is string && password is string) {
        auth:OutboundBasicAuthProvider outboundBasicAuthProvider = new ({
            username: <@untainted> username,
            password: <@untainted> password
        });

        token = check outboundBasicAuthProvider.generateToken();
        
        http:BasicAuthHandler outboundBasicAuthHandler = 
                new (<auth:OutboundBasicAuthProvider> outboundBasicAuthProvider);
        auth = {
            authHandler: outboundBasicAuthHandler
        };
    }

    // contact home and display message
    http:Client hc = new(homeURL, { auth: auth });
    http:Response hr = check hc->get("/info");
    if hr.statusCode == 401 {
        return error("Authentication failure! Check your username & password.");
    } else if hr.statusCode == 200 {
        string msg = check hr.getTextPayload();
        io:println("Message from the results system:\n");
        io:println(msg);
    } else {
        string|error payload = hr.getTextPayload();
        return error("Unexpected response from distributor service: " + hr.statusCode.toString() + 
                     (payload is string ? (": " + payload) : ""));
    }

    // check whether this version is still supported
    hr = check hc->get("/isactive/" + MY_VERSION);
    if hr.statusCode != 200 {
        return error("*** This version of the subscriber is no longer supported!");
    }

    string? queryString = ();
    service callbackService = resultDataOnlyClientService;
    string kinds = "result data";

    if await {
        queryString = WANT_AWAIT_RESULTS; 
        callbackService = awaitAndResultDataClientService;
        kinds = "await notification and result data";
    }

    if image {
        imageClient = <@untainted> new (homeURL, {auth: auth});
        
        if queryString is () {
            queryString = WANT_IMAGE;
            callbackService = imageAndResultDataClientService;
            kinds = "result data and PDF";
        } else {
            queryString = "&" + WANT_IMAGE; 
            callbackService = allClientService;
            kinds = "await notification, result data, and PDF";
        }
    }

    string wsUrl;

    if homeURL.startsWith("http://") {
        wsUrl = "ws" + homeURL.substring(<int> homeURL.indexOf("http") + 4) + "/connect";
    } else if homeURL.startsWith("https://") {
        wsUrl = "wss" + homeURL.substring(<int> homeURL.indexOf("https") + 5) + "/connect";
    } else {
        panic error("InvalidHomeUrlError");
    }

    if !(queryString is ()) {
        wsUrl += "?" + queryString;
    }

    map<string> headers = {};
    if !(token is ()) {
        headers[http:AUTH_HEADER] = string `Basic ${token}`;
    }

    http:WebSocketClient wsClientEp = new (wsUrl, config = {
        callbackService: callbackService,
        customHeaders: headers,
        retryConfig: {
            intervalInMillis: 3000,
            maxCount: 10,
            backOffFactor: 1.5,
            maxWaitIntervalInMillis: 20000
        }
    });
    
    if wsClientEp.isOpen() {
        io:println(
            string `Established a connection to receive ${kinds}. Connection ID: ${wsClientEp.getConnectionId()}`);
    }    
}

service resultDataOnlyClientService = @http:WebSocketServiceConfig {} service {

    resource function onText(http:WebSocketClient conn, json payload) {
        if !(payload is map<json>) {
            log:printError("Expected map<json> payload, received:" + payload.toString());
            return;
        }

        saveResult(<@untainted> <map<json>> payload);
    }

    resource function onError(http:WebSocketClient conn, error err) {
        log:printError("Error occurred", err);
    }

    resource function onClose(http:WebSocketClient wsEp, int statusCode, string reason) {
        log:printInfo(string `Connection closed: statusCode: ${statusCode}, reason: ${reason}`);  
    }
};

service awaitAndResultDataClientService = @http:WebSocketServiceConfig {} service {

    resource function onText(http:WebSocketClient conn, json payload) {
        if payload is string {
            // "Await Results" notification.
            log:printInfo("Await results notification received: " + payload);
            _  = start notifyAwait();
            return;
        }

        if !(payload is map<json>) {
            log:printError("Expected map<json> payload, received:" + payload.toString());
            return;
        }

        saveResult(<@untainted map<json>> payload);
    }

    resource function onError(http:WebSocketClient conn, error err) {
        log:printError("Error occurred", err);
    }

    resource function onClose(http:WebSocketClient wsEp, int statusCode, string reason) {
        log:printInfo(string `Connection closed: statusCode: ${statusCode}, reason: ${reason}`);  
    }
};

service imageAndResultDataClientService = @http:WebSocketServiceConfig {} service {

    resource function onText(http:WebSocketClient conn, json payload) {
        if !(payload is map<json>) {
            log:printError("Expected map<json> payload, received:" + payload.toString());
            return;
        }

        map<json> objPayload = <map<json>> payload;

        if objPayload["result"] is () {
            // Image notification.
            saveImagePdf(<@untainted> objPayload);
            return;
        }

        // Result notification.
        saveResult(<@untainted> objPayload);
    }

    resource function onError(http:WebSocketClient conn, error err) {
        log:printError("Error occurred", err);
    }

    resource function onClose(http:WebSocketClient wsEp, int statusCode, string reason) {
        log:printInfo(string `Connection closed: statusCode: ${statusCode}, reason: ${reason}`);  
    }
};


service allClientService = @http:WebSocketServiceConfig {} service {

    resource function onText(http:WebSocketClient conn, json payload) {
        if payload is string {
            // "Await Results" notification.
            log:printInfo("Await results notification received: " + payload);
            _  = start notifyAwait();
            return;
        }

        if !(payload is map<json>) {
            log:printError("Expected map<json> payload, received:" + payload.toString());
            return;
        }

        map<json> objPayload = <map<json>> payload;

        if objPayload["result"] is () {
            // Image notification.
            saveImagePdf(<@untainted> objPayload);
            return;
        }

        // Result notification.
        saveResult(<@untainted> objPayload);
    }

    resource function onError(http:WebSocketClient conn, error err) {
        log:printError("Error occurred", err);
    }

    resource function onClose(http:WebSocketClient wsEp, int statusCode, string reason) {
        log:printInfo(string `Connection closed: statusCode: ${statusCode}, reason: ${reason}`);  
    }
};

function notifyAwait() {
    error? pingStatus = sound:ping();
    if !(pingStatus is ()) {
        log:printError("Error pinging on await notification", pingStatus);
    }
}
