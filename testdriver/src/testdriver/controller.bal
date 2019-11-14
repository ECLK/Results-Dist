import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/io;

listener http:Listener hl = new(9999);

boolean alreadyRunning = false;
int runCount = 0; // used to generate a unique election code

@http:ServiceConfig {
    basePath: "/"
}
service TestController on hl {
    resource function start(http:Caller caller, http:Request req) returns error? {
        boolean is2019 = req.getQueryParamValue("2019") == () ? false : true;

        http:Response hr = new;
        if alreadyRunning {
            return caller->ok("Test already running; try again later.");
        } else {
            // yes i know race condition possible .. need to use lock to do this better (after it becomes non experimental)
            alreadyRunning = true;
            check caller->ok("Test data publishing starting.");
        }
    
        string electionCode = (is2019 ? "2019-PRE-EMPTY-" : "2015-PRE-REPLAY-") + io:sprintf("%03d", runCount);
        log:printInfo("Publishing new result set for " + electionCode + " starting at " + time:currentTime().toString());

        http:Client rc = new (resultsURL);
        _ = check rc->get("/result/reset"); // reset the results store
        var e = publishResults(electionCode, rc, (is2019 ? results2019 : results2015), (is2019 ? resultsByPD2019 : resultsByPD2015));
        if e is error {
            log:printInfo("Error publishing results: " + e.toString());
            alreadyRunning = false;
        }
    }
}