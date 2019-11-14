import ballerina/auth;
import ballerina/http;
import ballerina/io;
import ballerina/log;
import ballerina/websub;

import maryamzi/ping;

const MY_VERSION = "2019-11-10";

// TODO: set correct ones once decided
const JSON_TOPIC = "https://github.com/ECLK/Results-Dist-json";
const IMAGE_PDF_TOPIC = "https://github.com/ECLK/Results-Dist-image";
const AWAIT_RESULTS_TOPIC = "https://github.com/ECLK/Results-Dist-await";

const UNDERSOCRE = "_";
const COLON = ":";

const JSON_EXT = ".json";
const XML_EXT = ".xml";
const TEXT_EXT = ".txt";
const PDF_EXT = ".pdf";

const JSON_PATH = "/json";
const XML_PATH = "/xml";
const IMAGE_PATH = "/image";
const AWAIT_PATH = "/await";

const ONE_WEEK_IN_SECONDS = 604800;

string hub = "";
string subscriberSecret = "";

string subscriberPublicUrl = "";
int subscriberPort = -1;

boolean wantJson = false;
boolean wantXml = false;
boolean wantHtml = false;
boolean sortedHtml = false;

http:OutboundAuthConfig? auth = ();
http:Client? imageClient = ();

// what formats does the user want results saved in?
public function main (string secret,                // secret to send to the hub
                      string? username = (),        // my username  
                      string? password = (),        // my password  
                      boolean await = false,        // do I want the await results notification?
                      boolean 'json = false,        // do I want json?
                      boolean 'xml = false,         // do I want xml?
                      boolean image = false,        // do I want the image?
                      boolean html = false,         // do I want HTML?
                      boolean sorted = true,        // do I want HTML results sorted highest to lowest
                      string homeURL = "https://resultstest.ecdev.opensource.lk", // where do I subscribe at
                      int port = 1111,              // port I'm going to open
                      string myURL = ""             // how to reach me over the internet
                    ) returns error? {
    subscriberSecret = <@untainted> secret;
    subscriberPublicUrl = <@untainted> (myURL == "" ? string `http://localhost:${port}` : myURL);
    subscriberPort = <@untainted> port;
    hub = <@untainted> homeURL + "/websub/hub";

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

    // start the listener
    websub:Listener websubListener = new(subscriberPort);

    // attach JSON subscriber
    service subscriberService = @websub:SubscriberServiceConfig {
        path: JSON_PATH,
        subscribeOnStartUp: true,
        target: [hub, JSON_TOPIC],
        leaseSeconds: ONE_WEEK_IN_SECONDS,
        secret: subscriberSecret,
        callback: subscriberPublicUrl.concat(JSON_PATH),
        hubClientConfig: {
            auth: auth
        }
    }
    service {
        resource function onNotification(websub:Notification notification) {
            json|error payload = notification.getJsonPayload();
            if (payload is json) {
                saveResult(<@untainted map<json>>payload); // we know its an object
            } else {
                log:printError("Expected JSON payload, received:", payload);
            }
        }
    };
    check websubListener.__attach(subscriberService);

    if await {
        // attach the await results subscriber
        service awaitResultsSubscriberService = @websub:SubscriberServiceConfig {
           path: AWAIT_PATH,
           subscribeOnStartUp: true,
           target: [hub, AWAIT_RESULTS_TOPIC],
           leaseSeconds: ONE_WEEK_IN_SECONDS,
           secret: subscriberSecret,
           callback: subscriberPublicUrl.concat(AWAIT_PATH),
           hubClientConfig: {
               auth: auth
           }
        }
        service {
           resource function onNotification(websub:Notification notification) {
               string|error textPayload = notification.getTextPayload();
               if (textPayload is string) {
                   log:printInfo("Await results notification received: " + textPayload);
                   error? pingStatus = ping:ping();
                   if !(pingStatus is ()) {
                       log:printError("Error pinging on await notification", pingStatus);

                   }
               } else {
                   log:printError("Expected text payload, received:" + textPayload.toString());
               }
           }
        };
        check websubListener.__attach(awaitResultsSubscriberService);
    }

    if image {
        imageClient = <@untainted> new (homeURL, {auth: auth});

        // attach the image subscriber
        service imageSubscriberService = @websub:SubscriberServiceConfig {
           path: IMAGE_PATH,
           subscribeOnStartUp: true,
           target: [hub, IMAGE_PDF_TOPIC],
           leaseSeconds: ONE_WEEK_IN_SECONDS,
           secret: subscriberSecret,
           callback: subscriberPublicUrl.concat(IMAGE_PATH),
           hubClientConfig: {
               auth: auth
           }
        }
        service {
           resource function onNotification(websub:Notification notification) {
               json|error jsonPayload = notification.getJsonPayload();
               if (jsonPayload is map<json>) {
                   saveImagePdf(<@untainted> jsonPayload);
               } else {
                   log:printError("Expected map<json> payload, received:" + jsonPayload.toString());
               }
           }
        };
        check websubListener.__attach(imageSubscriberService);
    }

    // start off
    check websubListener.__start();
}
