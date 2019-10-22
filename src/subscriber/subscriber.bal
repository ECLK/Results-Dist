import ballerina/config;
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
const JSON_EXT = ".json";
const XML_EXT = ".xml";
const TEXT_EXT = ".txt";
const PDF_EXT = ".pdf";

int port = config:getAsInt("subscriber.port", 8080);

websub:Listener websubListener = new(port);

final string directoryPath = ""; // TODO: set

service jsonSubscriber =
@websub:SubscriberServiceConfig {
    path: "/json",
    subscribeOnStartUp: true,
    target: [HUB, JSON_TOPIC],
    leaseSeconds: 172800,
    callback: "http://localhost:" + port.toString() + "/json"
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

service xmlSubscriber =
@websub:SubscriberServiceConfig {
    path: "/xml",
    subscribeOnStartUp: true,
    target: [HUB, XML_TOPIC],
    leaseSeconds: 172800,
    callback: "http://localhost:" + port.toString() + "/xml"
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

service textSubscriber =
@websub:SubscriberServiceConfig {
    path: "/text",
    subscribeOnStartUp: true,
    target: [HUB, TEXT_TOPIC],
    leaseSeconds: 172800,
    callback: "http://localhost:" + port.toString() + "/text"
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

service imageSubscriber =
@websub:SubscriberServiceConfig {
    path: "/image",
    subscribeOnStartUp: true,
    target: [HUB, IMAGE_TOPIC],
    leaseSeconds: 172800,
    callback: "http://localhost:" + port.toString() + "/image"
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

public function main(string? contentType = ()) {
    match contentType {
        "--json"|() => {
            checkpanic websubListener.__attach(jsonSubscriber);
        }

        "--xml" => {
            checkpanic websubListener.__attach(xmlSubscriber);
        }

        "--text" => {
            checkpanic websubListener.__attach(textSubscriber);
        }

        "--image" => {
            checkpanic websubListener.__attach(imageSubscriber);
        }

        "--all" => {
            checkpanic websubListener.__attach(jsonSubscriber);
            checkpanic websubListener.__attach(xmlSubscriber);
            checkpanic websubListener.__attach(textSubscriber);
            checkpanic websubListener.__attach(imageSubscriber);
        }
    }

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
