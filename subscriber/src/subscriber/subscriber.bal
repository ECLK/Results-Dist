import ballerina/auth;
import ballerina/http;
import ballerina/io;
import ballerina/log;
import ballerina/websub;

const MY_VERSION = "2019-11-02";

// TODO: set correct ones once decided
const JSON_TOPIC = "https://github.com/ECLK/Results-Dist-json";

const UNDERSOCRE = "_";
const COLON = ":";

const JSON_EXT = ".json";
const XML_EXT = ".xml";
const TEXT_EXT = ".txt";
const PDF_EXT = ".pdf";

const JSON_PATH = "/json";
const XML_PATH = "/xml";
const TEXT_PATH = "/txt";
const IMAGE_PATH = "/image";

const TWO_DAYS_IN_SECONDS = 172800;

string hub = "";
string subscriberSecret = "";

string subscriberPublicUrl = "";
int subscriberPort = -1;

boolean wantJson = false;
boolean wantXml = false;

auth:OutboundBasicAuthProvider? outboundBasicAuthProvider = ();
http:BasicAuthHandler? outboundBasicAuthHandler = ();
http:OutboundAuthConfig? auth = ();

// what formats does the user want results saved in?
public function main (string secret,                // secret to send to the hub
                      string? username = (),        // my username  
                      string? password = (),        // my password  
                      boolean 'json = false,        // do I want json?
                      boolean 'xml = false,         // do I want xml?
                      string homeURL = "http://resultstest.ecdev.opensource.lk", // where do I subscribe at
                      int port = 1111,              // port I'm going to open
                      string myURL=""          // how to reach me over the internet
                    ) returns error? {
    subscriberSecret = <@untainted> secret;
    subscriberPublicUrl = <@untainted> (myURL == "" ? string `http://localhost:${port}` : myURL);
    subscriberPort = <@untainted> port;
    hub = <@untainted> homeURL + "/websub/hub";

    service subscriberService;

    // check what format the user wants results in
    if 'json {
        wantJson = true;
    }
    if 'xml {
        wantXml = true;
    }
    if !(wantJson || wantXml) {
        // default to giving json
        wantJson = true;
    }

    // contact home and display message
    http:Client hc = new(homeURL);
    http:Response hr = check hc->get("/info");
    if hr.statusCode == 200 {
        string msg = check hr.getTextPayload();
        io:println("Message from the results system:\n");
        io:println(msg);
    }

    // check whether this version is still supported
    hr = check hc->get("/isactive/" + MY_VERSION);
    if hr.statusCode != 200 {
        return error("*** This version of the subscriber is no longer supported!");
    }

    // start the listener
    websub:Listener websubListener = new(subscriberPort);

    if (username is string && password is string) {
        outboundBasicAuthProvider = new({
            username: <@untainted> username,
            password: <@untainted> password
        });

        outboundBasicAuthHandler = new(<auth:OutboundBasicAuthProvider> outboundBasicAuthProvider);
        auth = {
            authHandler: <http:BasicAuthHandler> outboundBasicAuthHandler
        };
    }

    // attach JSON subscriber
    subscriberService = @websub:SubscriberServiceConfig {
        path: JSON_PATH,
        subscribeOnStartUp: true,
        target: [hub, JSON_TOPIC],
        leaseSeconds: TWO_DAYS_IN_SECONDS,
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

    // start off
    check websubListener.__start();
}

