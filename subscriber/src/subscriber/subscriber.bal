import ballerina/log;
import ballerina/websub;

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
string subscriberDirectoryPath = "";

boolean wantJson = false;
boolean wantXml = false;

// what formats does the user want results saved in?
public function main (string secret,                // secret to send to the hub
                      boolean 'json = false,        // do I want json?
                      boolean 'xml = false,         // do I want xml?
                      string hubURL = "http://localhost:9090/websub/hub", // where do I subscribe at
                      int port = 1111,              // port I'm going to open
                      string publicURL="",          // how to reach me over the internet
                      string resultsPath= "/tmp"    // where to store results
                    ) returns error? {
    subscriberSecret = <@untainted> secret;
    subscriberPublicUrl = <@untainted> (publicURL == "" ? string `http://localhost:${port}` : publicURL);
    subscriberPort = <@untainted> port;
    subscriberDirectoryPath = <@untainted> resultsPath;
    hub = <@untainted> hubURL;

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

    // start the listener
    websub:Listener websubListener = new(subscriberPort);

    // attach JSON subscriber
    subscriberService = @websub:SubscriberServiceConfig {
        path: JSON_PATH,
        subscribeOnStartUp: true,
        target: [hub, JSON_TOPIC],
        leaseSeconds: TWO_DAYS_IN_SECONDS,
        secret: subscriberSecret,
        callback: subscriberPublicUrl.concat(JSON_PATH)
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

