import ballerina/io;
import ballerina/log;
import ballerina/system;
import ballerina/time;
import ballerina/websub;

// TODO: set correct ones once decided
const HUB = "http://localhost:9090/websub/hub";
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

string subscriberSecret = "";

string scheme = "http://";
string subscriberDomain = "localhost";
int subscriberPort = 8080;

final string directoryPath = ""; // TODO: set

function getJsonSubscriber() returns service {
    return
    @websub:SubscriberServiceConfig {
        path: JSON_PATH,
        subscribeOnStartUp: true,
        target: [HUB, JSON_TOPIC],
        leaseSeconds: TWO_DAYS_IN_SECONDS,
        secret: subscriberSecret,
        callback: getUrl(JSON_PATH)
    }
    service {
        resource function onNotification(websub:Notification notification) {
            json|error jsonPayload = notification.getJsonPayload();
            if (jsonPayload is json) {
                writeJson(directoryPath.concat(getFileName(JSON_EXT)), jsonPayload);
            } else {
                log:printError("Error extracting JSON payload", jsonPayload);
            }
        }
    };
}

function getXmlSubscriber() returns service {
    return
    @websub:SubscriberServiceConfig {
        path: XML_PATH,
        subscribeOnStartUp: true,
        target: [HUB, XML_TOPIC],
        leaseSeconds: TWO_DAYS_IN_SECONDS,
        secret: subscriberSecret,
        callback: getUrl(XML_PATH)
    }
    service {
        resource function onNotification(websub:Notification notification) {
            xml|error xmlPayload = notification.getXmlPayload();
            if (xmlPayload is xml) {
                writeXml(directoryPath.concat(getFileName(XML_EXT)), xmlPayload);
            } else {
                log:printError("Error extracting XML payload", xmlPayload);
            }
        }
    };
}

function getTextSubscriber() returns service {
    return
    @websub:SubscriberServiceConfig {
        path: TEXT_PATH,
        subscribeOnStartUp: true,
        target: [HUB, TEXT_TOPIC],
        leaseSeconds: TWO_DAYS_IN_SECONDS,
        secret: subscriberSecret,
        callback: getUrl(TEXT_PATH)
    }
    service {
        resource function onNotification(websub:Notification notification) {
            string|error textPayload = notification.getTextPayload();
            if (textPayload is string) {
                write(directoryPath.concat(getFileName(TEXT_EXT)), textPayload);
            } else {
                log:printError("Error extracting text payload", textPayload);
            }
        }
    };
}

function getImageSubscriber() returns service {
    return
    @websub:SubscriberServiceConfig {
        path: IMAGE_PATH,
        subscribeOnStartUp: true,
        target: [HUB, IMAGE_TOPIC],
        leaseSeconds: TWO_DAYS_IN_SECONDS,
        secret: subscriberSecret,
        callback: getUrl(IMAGE_PATH)
    }
    service {
        resource function onNotification(websub:Notification notification) {
            byte[]|error binaryPayload = notification.getBinaryPayload();
            if (binaryPayload is byte[]) {
                write(directoryPath.concat(getFileName(PDF_EXT)), binaryPayload.toBase64());
            } else {
                log:printError("Error extracting image payload", binaryPayload);
            }
        }
    };
}

public function main(string secret, boolean 'json = false, boolean 'xml = false, boolean text = false,
                     string domain = "localhost", int port = 8080,
                     string? keystorePath = (), string keystorePassword = "") {
    subscriberSecret = <@untainted> secret;
    subscriberDomain = <@untainted> domain;
    subscriberPort = <@untainted> port;

    websub:SubscriberListenerConfiguration config = {};
    if (keystorePath is string) {
        scheme = "https://";
        config.httpServiceSecureSocket = {
            keyStore: {
                path: keystorePath,
                password: keystorePassword
            }
        };
    }

    websub:Listener websubListener = new(subscriberPort, config);

    if ('json) {
        checkpanic websubListener.__attach(getJsonSubscriber());
    }

    if ('xml) {
        checkpanic websubListener.__attach(getXmlSubscriber());
    }

    if ('text) {
        checkpanic websubListener.__attach(getTextSubscriber());
    }

    checkpanic websubListener.__attach(getImageSubscriber());

    checkpanic websubListener.__start();
}

function getFileName(string ext) returns string {
    return time:currentTime().time.toString().concat(UNDERSOCRE, system:uuid(), ext);
}

function closeWcc(io:WritableCharacterChannel wc) {
    var result = wc.close();
    if (result is error) {
        log:printError("Error occurred while closing the character stream", result);
    }
}

function closeWbc(io:WritableByteChannel wc) {
    var result = wc.close();
    if (result is error) {
        log:printError("Error occurred while closing the byte stream", result);
    }
}

function writeJson(string path, json content) {
    writeContent(path, function(io:WritableCharacterChannel wch) returns error? {
        return wch.writeJson(content);
    });
}

function writeXml(string path, xml content) {
    writeContent(path, function(io:WritableCharacterChannel wch) returns error? {
        return wch.writeXml(content);
    });
}

function write(string path, string content) {
    writeContent(path, function(io:WritableCharacterChannel wch) returns int|error {
        return wch.write(content, 0);
    });
}

function writeContent(string path, function(io:WritableCharacterChannel wch) returns int|error? writeFunc) {
    io:WritableByteChannel|error wbc = io:openWritableFile(path);
    if (wbc is io:WritableByteChannel) {
        io:WritableCharacterChannel wch = new(wbc, "UTF8");
        var result = writeFunc(wch);
        if (result is error) {
            log:printError("Error writing content", result);
        } else {
            log:printInfo("Update written to " + path);
        }
        closeWcc(wch);
        closeWbc(wbc);
    } else {
        log:printError("Error creating a byte channel for " + path, wbc);
    }
}

function getUrl(string path) returns string {
    return scheme.concat(subscriberDomain, COLON, subscriberPort.toString(), path);
}
