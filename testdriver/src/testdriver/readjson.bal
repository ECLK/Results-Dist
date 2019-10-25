import ballerina/io;
import ballerina/log;

function readJson(string path) returns @tainted json | error {
    return readJsonFile(path);
}

function readJsonFile(string path) returns @tainted json | error {
    var rblCharChnl = check getRblCharChnl(getRblByteChnl(path));
    return readJsonFromCharChnl(rblCharChnl);
}

function readJsonFromCharChnl(io:ReadableCharacterChannel rblCharChnl) returns @tainted json | error {
    var content = rblCharChnl.readJson();   
    var err = rblCharChnl.close(); 
    if err is error {
        log:printError("Failed to close the character channel");
    }  
    return content;  
}

function getRblByteChnl(string path) returns @tainted io:ReadableByteChannel | error {
    return io:openReadableFile(path);
}

function getRblCharChnl(io:ReadableByteChannel | error rblByteChnl) returns io:ReadableCharacterChannel | error {
    return rblByteChnl is error ? rblByteChnl : new io:ReadableCharacterChannel(rblByteChnl, "UTF8");
}