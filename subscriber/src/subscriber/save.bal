import ballerina/io;
import ballerina/log;
import ballerina/system;
import ballerina/time;

function saveSummaryResult (json result) {
    log:printInfo("Received summary result: " + result.toString());
//    SummaryResult sr = check SummaryResult.constructFrom (result);
//   log:printInfo("Received SUMMARY result:");
//    writeJson(subscriberDirectoryPath.concat(getFileName(JSON_EXT)), result);
}

function savePartyResult (json result) {
    log:printInfo("Received party result: " + result.toString());
//    writeJson(subscriberDirectoryPath.concat(getFileName(JSON_EXT)), result);
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
