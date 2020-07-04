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
                      string homeURL = "http://localhost:9090" // where do I connect at
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
    if (username is string && password is string) {
        auth:OutboundBasicAuthProvider outboundBasicAuthProvider = new ({
            username: <@untainted> username,
            password: <@untainted> password
        });
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

    if await {
        queryString = WANT_AWAIT_RESULTS; 
    }

    if image {
        imageClient = <@untainted> new (homeURL, {auth: auth});
        
        if queryString is () {
            queryString = WANT_IMAGE; 
        } else {
            queryString = "&" + WANT_IMAGE; 
        }
    }

    string wsUrl = "ws://localhost:9090/ws";

    if !(queryString is ()) {
        wsUrl += "?" + queryString;
    }

    // Creates a new WebSocket client with the backend URL and assigns a callback service.
    http:WebSocketClient wsClientEp = new (wsUrl, config = {callbackService: ClientService});
}

service ClientService = @http:WebSocketServiceConfig {} service {

    resource function onText(http:WebSocketClient conn, json payload) {
        // TODO: Check if we can improve this by introducing 4 different service or via function pointers
        // 1. results only
        // 2. results and await only
        // 3. results and image only
        // 4. all 3
        // With this impl, if the subscriber only wants results, we are doing unnecessary is checks (payload is string,
        // and objPayload["result"] is ()) for each result notification.
        if payload is string {
            // "Await Results" notification.
            log:printInfo("Await results notification received: " + payload);
            error? pingStatus = sound:ping();
            if !(pingStatus is ()) {
                log:printError("Error pinging on await notification", pingStatus);
            }
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
        log:printError("Error occurred on receipt", err);
    }
};
