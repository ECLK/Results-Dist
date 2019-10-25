import ballerina/log;
import ballerina/websub;

// TODO: set correct ones once decided
const JSON_TOPIC = "https://github.com/ECLK/Results-Dist-json";
const XML_TOPIC = "https://github.com/ECLK/Results-Dist-xml";
const TEXT_TOPIC = "https://github.com/ECLK/Results-Dist-text";
const IMAGE_TOPIC = "https://github.com/ECLK/Results-Dist-image";

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

// what formats does the user want results saved in?
boolean wantJson = false;
boolean wantXml = false;
boolean wantTxt = false;

public function main (string secret, string publicUrl, 
                      boolean 'json = false, boolean 'xml = false, boolean text = false,
                      int port = 8080, string? certFile = (), string directoryPath = "",
                      string hubURL = "https://6052758a.ngrok.io/websub/hub") returns error? {
    subscriberSecret = <@untainted> secret;
    subscriberPublicUrl = <@untainted> publicUrl;
    subscriberPort = <@untainted> port;
    subscriberDirectoryPath = <@untainted> directoryPath;
    hub = <@untainted> hubURL;

    service subscriberService;

    websub:SubscriberListenerConfiguration config = {};
    if (certFile is string) {
        config.httpServiceSecureSocket = {
            certFile: certFile
        };
    }

    // check what format the user wants results in
    if 'json {
        wantJson = true;
    }
    if 'xml {
        wantXml = true;
    }
    if 'text {
        wantTxt = true;
    }
    if !(wantJson || wantXml || wantTxt) {
        log:printError("No output format requested! Quitting ... ask for json or txt!");
        return;
    }

    // start the listener
    websub:Listener websubListener = new(subscriberPort, config);

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
            json|error jsonPayload = notification.getJsonPayload();
            if (jsonPayload is json) {
                if jsonPayload.'type == "SUMMARY" {
                    saveSummaryResult(jsonPayload);
                } else if jsonPayload.'type == "PARTY" {
                    savePartyResult(jsonPayload);
                } else {
                    log:printError ("Unknown JSON data received: " + jsonPayload.toString());
                }
                
                //match jsonPayload {
                  //  { 'type : "SUMMARY" } => { saveSummaryResult(jsonPayload); }
                    //{ 'type : "PARTY" } => { savePartyResult(jsonPayload); }
                  //  var _ => { log:printError ("Unknown JSON data received: " + jsonPayload.toString()); }
                //}
            } else {
                log:printError("Expected JSON payload, received:", jsonPayload);
            }
        }
    };
    check websubListener.__attach(subscriberService);

    // attach Image subscriber
    subscriberService = @websub:SubscriberServiceConfig {
        path: IMAGE_PATH,
        subscribeOnStartUp: true,
        target: [hub, IMAGE_TOPIC],
        leaseSeconds: TWO_DAYS_IN_SECONDS,
        secret: subscriberSecret,
        callback: subscriberPublicUrl.concat(IMAGE_PATH)
    }
    service {
        resource function onNotification(websub:Notification notification) {
            byte[]|error binaryPayload = notification.getBinaryPayload();
            if (binaryPayload is byte[]) {
                log:printInfo("IMG Result received: " + binaryPayload.toString());
                write(subscriberDirectoryPath.concat(getFileName(PDF_EXT)), binaryPayload.toBase64());
            } else {
                log:printError("Error extracting image payload", binaryPayload);
            }
        }
    };    
    check websubListener.__attach(subscriberService);

    // start off
    check websubListener.__start();
}

