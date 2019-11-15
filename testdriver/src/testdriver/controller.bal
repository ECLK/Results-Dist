import ballerina/http;
import ballerina/log;
import ballerina/time;

listener http:Listener hl = new(9999);

boolean alreadyRunning = false;
int runCount = 0; // used to generate a unique election code

@http:ServiceConfig {
    basePath: "/"
}
service TestController on hl {
    @http:ResourceConfig {
        path: "/start/{electionCode}"
    }
    resource function start(http:Caller caller, http:Request req, string electionCode) returns error? {
        if alreadyRunning {
            return caller->ok("Test already running; try again later.");
        }
        string ec = <@untainted>electionCode;
        if !tests.hasKey(ec) {
            http:Response hr = new;
            hr.statusCode = 404;
            hr.setTextPayload("No such election to run tests with: " + ec);
            check caller->respond(hr);
        } 
        check caller->ok("Test data publishing starting.");

        // yes i know race condition possible .. need to use lock to do this better (after it becomes non experimental)
        alreadyRunning = true;

        [ string, map<map<json>>[], map<json>[], map<map<json>>[], map<json>[] ] 
            [electionName, results, resultsByPD, results2, resultsByPD2] = tests.get(ec);
    

        log:printInfo("Publishing new result set for " + ec + " starting at " + time:currentTime().toString());

        http:Client rc = new (resultsURL);
        _ = check rc->get("/result/reset"); // reset the results store
        var e = sendResults("PRESIDENTIAL-FIRST", ec, rc, results, resultsByPD);
        if e is error {
            log:printError("Error publishing results: " + e.toString());
        } else if results2.length() != 0 {
            e = sendResults("PRESIDENTIAL-PREFS", ec, rc, results2, resultsByPD2);
            if e is error {
                log:printError("Error publishing preference results: " + e.toString());
            }
        }
        alreadyRunning = false;
    }
}