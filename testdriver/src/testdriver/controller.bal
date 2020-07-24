import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/mime;

listener http:Listener hl = new(9999);

boolean alreadyRunning = false;
int runCount = 0; // used to generate a unique election code

// TODO : Fix this properly - Negation issue
//function(http:Caller caller, http:Request req, string electionCode) returns error? startResults =
//    electionType == ELECTION_TYPE_PARLIAMENTARY ? startParliamentaryResults : startPresidentialResults;
function(http:Caller caller, http:Request req, string electionCode) returns error? startResults =
    startParliamentaryResults;

@http:ServiceConfig {
    basePath: "/"
}
service TestController on hl {
    @http:ResourceConfig {
        path: "/"
    }
    resource function home(http:Caller caller, http:Request req) returns error? {
        string head = "<head><title>Test Generator Controller</title>";
        head += "<link rel=\"stylesheet\" href=\"https://maxcdn.bootstrapcdn.com/bootstrap/3.4.0/css/bootstrap.min.css\">";
        head += "</head>";

        string body = "<body style='margin: 5%'>";
        body += "<div class='container-fluid'>";
        body += "<h1>Select a test to run:</h1>";
        body += "<ul>";
        //TODO make it generic
        foreach var [code, [name, _, _, _, _]] in parliamentaryTests.entries() {
            body += "<li><a href='/start/" + code + "'>" + name + "</a></li>";
        }
        body += "</ul>";
        body += "</div>";
        body += "</body>";

        string doc = "<html>" + head + body + "</html>";

        http:Response hr = new;
        hr.setPayload(doc);
        hr.setContentType(mime:TEXT_HTML);
        return caller->ok(hr);
    }

    @http:ResourceConfig {
        path: "/start/{electionCode}"
    }
    resource function start(http:Caller caller, http:Request req, string electionCode) returns error? {
        check startResults(caller, req, electionCode);
    }
}

function startParliamentaryResults(http:Caller caller, http:Request req, string electionCode) returns error? {
    if alreadyRunning {
        return caller->ok("Test already running; try again later.");
    }
    string ec = <@untainted>electionCode;
    if ec != "FAKE" {
        check caller->notFound("No such election to run tests with: " + ec);
    }
    check caller->ok("Test data publishing starting.");

    // yes i know race condition possible .. need to use lock to do this better (after it becomes non experimental)
    alreadyRunning = true;

    [ string, map<map<json>>[], map<json>[], map<map<json>>[], map<json>[] ]
        [electionName, _ , parliamentaryFake, _ , _ ] = parliamentaryTests.get(ec);


    log:printInfo("Publishing new result set for " + electionName + " starting at " + time:currentTime().toString());

    http:Client rc = new (resultsURL);
    _ = check rc->get("/result/reset"); // reset the results store

    var e = sendParliamentaryResults(electionName, rc, parliamentaryFake);
    if e is error {
        log:printError("Error publishing results: " + e.toString());
    }
    alreadyRunning = false;
}

function startPresidentialResults(http:Caller caller, http:Request req, string electionCode) returns error? {
    if alreadyRunning {
        return caller->ok("Test already running; try again later.");
    }
    string ec = <@untainted>electionCode;
    if !tests.hasKey(ec) {
        check caller->notFound("No such election to run tests with: " + ec);
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
