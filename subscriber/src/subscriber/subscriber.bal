import ballerina/auth;
import ballerina/http;
import ballerina/io;
import ballerina/log;

import maryamzi/sound;

const WANT_IMAGE = "image=true";
const WANT_AWAIT_RESULTS = "await=true";

const MY_VERSION = "2019-11-15";

const UNDERSOCRE = "_";
const COLON = ":";

const JSON_EXT = ".json";
const XML_EXT = ".xml";
const TEXT_EXT = ".txt";
const PDF_EXT = ".pdf";

boolean wantJson = false;
boolean wantXml = false;
boolean wantHtml = false;
boolean sortedHtml = false;

boolean wantCode = false;

http:OutboundAuthConfig? auth = ();
http:Client? imageClient = ();

// what formats does the user want results saved in?
public function main (string? username = (),        // my username  
                      string? password = (),        // my password  
                      boolean await = false,        // do I want the await results notification?
                      boolean 'json = false,        // do I want json?
                      boolean 'xml = false,         // do I want xml?
                      boolean image = false,        // do I want the image?
                      boolean html = false,         // do I want HTML?
                      boolean sorted = true,        // do I want HTML results sorted highest to lowest
                      boolean wantCode = false,     // do I want electionCode in the filename
                      string homeURL = "https://resultstest.ecdev.opensource.lk" // where do I connect at
                    ) returns @tainted error? {

    // check what format the user wants results in
    wantJson = <@untainted>'json;
    wantXml = <@untainted>'xml;
    wantHtml = <@untainted>html;
    if !(wantJson || wantXml || wantHtml) {
        // default to giving json
        wantJson = true;
    }
    sortedHtml = <@untainted>sorted;

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
        return error("Unexpected response from distributor service: " + hr.toString());
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

    string wsUrl = "ws://localhost:9090/ws";

    if !(queryString is ()) {
        wsUrl += "?" + queryString;
    }

    map<string> headers = {};
    if !(token is ()) {
        headers[http:AUTH_HEADER] = string `Basic ${token}`;
    }

    http:WebSocketClient wsClientEp = new (wsUrl, config = {callbackService: callbackService, customHeaders: headers});
    
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
};

function notifyAwait() {
    error? pingStatus = sound:ping();
    if !(pingStatus is ()) {
        log:printError("Error pinging on await notification", pingStatus);
    }
}
