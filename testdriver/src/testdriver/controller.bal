import ballerina/http;
import ballerina/log;

listener http:Listener hl = new(9999);

boolean alreadyRunning = false;
int runCount = 0; // used to generate a unique election code

@http:ServiceConfig {
    basePath: "/"
}
service TestController on hl {
    resource function start(http:Caller caller, http:Request request) returns error? {
        http:Response hr = new;
        if alreadyRunning {
            return caller->ok("Test already running; try again later.");
        } else {
            // yes i know race condition possible .. need to use lock to do this better (after it becomes non experimental)
            alreadyRunning = true;
            check caller->ok("Test data publishing starting.");
        }
    
        log:printInfo("Starting new test");
        var e = publishOneSet();
        if e is error {
            log:printInfo("Error publishing results: " + e.toString());
        }
    }
}