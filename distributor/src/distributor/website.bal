import ballerina/auth;
import ballerina/file;
import ballerina/http;
import ballerina/log;
import ballerina/mime;
import ballerina/task;
import ballerina/time;
import ballerina/xmlutils;

const LEVEL_PD = "POLLING-DIVISION";
const LEVEL_ED = "ELECTORAL-DISTRICT";
const LEVEL_NI = "NATIONAL-INCREMENTAL";
const LEVEL_N = "NATIONAL";
const LEVEL_NF = "NATIONAL-FINAL";

const WANT_IMAGE = "image";
const WANT_AWAIT_RESULTS = "await";

const USERNAME = "username";

map<http:WebSocketCaller> jsonConnections = {};
map<http:WebSocketCaller> imageConnections = {};
map<http:WebSocketCaller> awaitConnections = {};

service disseminator = @http:WebSocketServiceConfig {} service {

    resource function onOpen(http:WebSocketCaller caller) {
        string connectionId = caller.getConnectionId();

        any username = caller.getAttribute(USERNAME);

        if username is string {
            log:printInfo(string `Registered user: ${username}, connectionId: ${connectionId}`);
        } else {
            log:printInfo("Registered: " + connectionId);
        }

        jsonConnections[connectionId] = <@untainted> caller;

        if <anydata> caller.getAttribute(WANT_IMAGE) == true {
            imageConnections[connectionId] = <@untainted> caller;
        }

        if <anydata> caller.getAttribute(WANT_AWAIT_RESULTS) == true {
            awaitConnections[connectionId] = <@untainted> caller;
        }
    }

    resource function onClose(http:WebSocketCaller caller, int statusCode, string reason) {
        string connectionId = caller.getConnectionId();

        _ = jsonConnections.remove(connectionId);

        if imageConnections.hasKey(connectionId) {
            _ = imageConnections.remove(connectionId);
        }

        if awaitConnections.hasKey(connectionId) {
            _ = awaitConnections.remove(connectionId);
        }

        any username = caller.getAttribute(USERNAME);

        if username is string {
            log:printInfo(string `Unregistered user: ${username}, connectionId: ${connectionId}, statusCode: ${statusCode}, reason: ${reason}`);
        } else {
            log:printInfo(string `Unregistered: ${connectionId}, statusCode: ${statusCode}, reason: ${reason}`);     
        }
    }
};

# Show a website for media people to get a list of all released results with
# links to each json value and the image with the signed official document.
@http:ServiceConfig {
    basePath: "/"
}
service mediaWebsite on mediaListener {
    @http:ResourceConfig {
        path: "/",
        methods: ["GET"]
    }
    resource function showAll(http:Caller caller, http:Request req) returns error? {
        string head = "<head>";
        head += "<title>Sri Lanka Elections Commission</title>";
        head += "<link rel=\"stylesheet\" href=\"https://maxcdn.bootstrapcdn.com/bootstrap/3.4.0/css/bootstrap.min.css\">";
        head += "</head>";

        string body = "<body style='margin: 5%'>";
        body += "<div class='container-fluid'>";
        body = body + "<h1>Released Results Data for Media Partners</h1>";
        string tt = check time:format(time:currentTime(), "yyyy-MM-dd'T'HH:mm:ss.SSSZ");
        body += "<p>Current time: " + tt + "</p>";

        body += getTables();
        body = body + "<p/>";
        body = body + "<p>All  results released so far as single JSON value: "
                    + "<a href='/allresults'>All Results</a>";
        body = body + "</div>";
        body = body + "</body>";
        string doc = "<html>" + head + body + "</html>";

        http:Response hr = new;
        hr.setPayload(doc);
        hr.setContentType(mime:TEXT_HTML);
        return caller->ok(hr);
    }

    resource function allresults(http:Caller caller, http:Request req) returns error? {
        json[] results = [];
        // return results in reverse order
        int i = resultsCache.length();
        if electionType == ELECTION_TYPE_PARLIAMENTARY {
            while i > 0 { // show non-incremental results in reverse order of release
                i = i - 1;
                if !(resultsCache[i].'type == RE_VI || resultsCache[i].'type == RN_SI) {
                    results.push(resultsCache[i].jsonResult);
                }
            }
        } else {
            while i > 0 { // show non-incremental results in reverse order of release
                i = i - 1;
                if resultsCache[i].jsonResult.level != "NATIONAL-INCREMENTAL" {
                    results.push(resultsCache[i].jsonResult);
                }
            }
        }
        return caller->ok(results);
    }

    resource function allresultswithincremental(http:Caller caller, http:Request req) returns error? {
        json[] results = [];
        // return results in reverse order
        int i = resultsCache.length();
        if electionType == ELECTION_TYPE_PARLIAMENTARY {
            while i > 0 { // show non-incremental results in reverse order of release
                i = i - 1;
                results.push(resultsCache[i].jsonResult);
            }
        } else {
            while i > 0 { // show non-incremental results in reverse order of release
                i = i - 1;
                if resultsCache[i].jsonResult.level != "NATIONAL-INCREMENTAL" {
                    results.push(resultsCache[i].jsonResult);
                }
            }
        }
        return caller->ok(results);
    }

    @http:ResourceConfig {
        path: "/result/{election}/{seqNo}",
        methods: ["GET"]
    }
    resource function data(http:Caller caller, http:Request req, string election, int seqNo) returns error? {
        // what's the format they want? we'll default to json if they don't say or get messy
        string format = req.getQueryParamValue ("format") ?: "json";
        if format != "xml" && format != "json" && format != "html" {
            format = "json";
        }

        // find the result object and send it in the format they want
        foreach Result r in resultsCache {
            if r.election == election && r?.sequenceNo == seqNo {
                if format == "json" {
                    return caller->ok(r.jsonResult);
                } else if format == "html" {
                    http:Response hr = new;
                    string resultType = r.jsonResult.'type.toString();
                    boolean sorted = (resultType == RN_SI || resultType == RN_V || resultType == RN_VS ||
                                      resultType == RN_VSN) ? true : false;
                    hr.setTextPayload(<@untainted>check generateHtml(election, r.jsonResult, sorted));
                    hr.setContentType("text/html");
                    return caller->ok(hr);
                } else { // xml
                    // put the result json object into a wrapper object to get a parent element
                    // NOTE: this code must match the logic in the subscriber saving code as
                    // both add this object wrapper with the property named "result". Bit
                    // dangerous as someone can forget to change both together - hence this comment!
                    json j = { result: r.jsonResult };
                    return caller->ok(check xmlutils:fromJSON(j));
                }
            }
        }

        // bad request
        return caller->notFound();
    }

    @http:ResourceConfig {
        path: "/release/{election}/{seqNo}",
        methods: ["GET"]
    }
    resource function releaseDoc (http:Caller caller, http:Request req, string election, int seqNo) returns error? {
        http:Response hr = new;

        // find image of the release doc and return it (if its there - may not have appeared yet)
        foreach Result r in resultsCache {
            if r.election == election && r?.sequenceNo == seqNo {
                byte[]? imageData = r.imageData;
                string? imageMediaType = r.imageMediaType;

                if imageData is byte[] && imageMediaType is string {
                    hr.setBinaryPayload(imageData);
                    hr.setContentType(imageMediaType);
                    return caller->ok(hr);
                } else {
                    return caller->ok("No official release available (yet)");
                }
            }
        }

        // bad request
        return caller->notFound();
    }

    # Hook for subscriber to be sent some info to display. Can put some HTML content into 
    # web/info.html and it'll get shown at subscriber startup
    # + return - error if problem
    resource function info(http:Caller caller, http:Request request) returns error? {
        http:Response hr = new;
        hr.setFileAsPayload("web/info.txt", "text/plain");
        check caller->ok(hr);
    }

    # Hook for subscriber to check whether their version is still active. If version is active
    # then must have file web/active-{versionNo}. If its missing will return 404.
    # + return - error if problem
    @http:ResourceConfig {
        path: "/isactive/{versionNo}",
        methods: ["GET"]
    }
    resource function isactive(http:Caller caller, http:Request request, string versionNo) returns error? {
        if file:exists("web/active-" + <@untainted> versionNo) {
            return caller->ok("Still good");
        } else {
            return caller->notFound("This version is no longer active; please upgrade (see status message).");
        }
    }

    //@http:ResourceConfig {
    //    path: "/sms",
    //    methods: ["POST"],
    //    body: "smsRecipient",
    //    auth: {
    //        scopes: ["ECAdmin"]
    //    }
    //}
    //resource function smsRegistration(http:Caller caller, http:Request req, Recipient smsRecipient) returns error? {
    //    string|error validatedNo = validate(smsRecipient.mobile);
    //    if validatedNo is error {
    //        return caller->badRequest(<string> validatedNo.detail()?.message);
    //    }
    //
    //    // If the load is high, we might need to sync following db/map update
    //    string|error status = registerSmsRecipient(smsRecipient.username.trim(), <string> validatedNo);
    //    if status is error {
    //        return caller->internalServerError(<@untainted> <string> status.detail()?.message);
    //    }
    //    return caller->ok(<@untainted> <string> status);
    //}
    //
    //// This API enables registering mobile nos via a file(binary payload). Make sure the data is structured
    //// as an array of Recipients and the content type is `application/octet-stream`.
    //// [
    ////   { "username":"newuser1", "mobile":"0771234567" },
    ////   { "username":"newuser2", "mobile":"0771234568" },
    ////   { "username":"newuser3", "mobile":"0771234569" }
    //// ]
    //@http:ResourceConfig {
    //    path: "/sms/all",
    //    methods: ["POST"],
    //    consumes: ["application/octet-stream"],
    //    auth: {
    //        scopes: ["ECAdmin"]
    //    }
    //}
    //resource function smsBulkRegistration (http:Caller caller, http:Request req) returns error? {
    //    Recipient[]|error recipient = readRecipients(req.getByteChannel());
    //    if recipient is error {
    //        log:printError("Invalid input", recipient);
    //        return caller->badRequest(<@untainted> recipient.toString());
    //    }
    //    Recipient[] smsRecipient = <Recipient[]> recipient;
    //    error? validatedNo = validateAllRecipients(smsRecipient);
    //    if validatedNo is error {
    //        return caller->badRequest("Validation failed: " + <@untainted string> validatedNo.detail()?.message);
    //    }
    //
    //    error? status = registerAllSMSRecipients(smsRecipient);
    //    if status is error {
    //        return caller->internalServerError("Registration failed: " + <@untainted string> status.detail()?.message);
    //    }
    //
    //    return caller->ok("Successfully registered all");
    //}
    //
    //@http:ResourceConfig {
    //    path: "/sms",
    //    methods: ["DELETE"],
    //    body: "smsRecipient",
    //    auth: {
    //        scopes: ["ECAdmin"]
    //    }
    //}
    //resource function smsDeregistration(http:Caller caller, http:Request req, Recipient smsRecipient) returns error? {
    //    string|error validatedNo = validate(smsRecipient.mobile);
    //    if validatedNo is error {
    //        return caller->badRequest(<string> validatedNo.detail()?.message);
    //    }
    //
    //    // If the load is high, we might need to sync following db/map update
    //    string|error status = unregisterSmsRecipient(smsRecipient.username.trim(), <string> validatedNo);
    //    if status is error {
    //        return caller->internalServerError(<@untainted string> status.detail()?.message);
    //    }
    //    return caller->ok(<@untainted string> status);
    //}
    //
    //@http:ResourceConfig {
    //    path: "/sms/all",
    //    methods: ["DELETE"],
    //    auth: {
    //        scopes: ["ECAdmin"]
    //    }
    //}
    //resource function resetSmsRecipients(http:Caller caller, http:Request req) returns error? {
    //    error? status = unregisterAllSMSRecipient();
    //    if status is error {
    //        return caller->internalServerError(<string> status.detail()?.message);
    //    }
    //    return caller->ok("Successfully unregistered all");
    //}

    // May have to move to a separate service.
    @http:ResourceConfig {
        webSocketUpgrade: {
            upgradePath: "/connect",
            upgradeService: disseminator
        }
    }
    resource function upgrader(http:Caller caller, http:Request req) {
        map<string[]> queryParams = req.getQueryParams();

        http:WebSocketCaller|http:WebSocketError wsEp = caller->acceptWebSocketUpgrade({});
        if (wsEp is http:WebSocketCaller) {
            if queryParams.hasKey(WANT_IMAGE) {
                wsEp.setAttribute(WANT_IMAGE, true);
            }

            if queryParams.hasKey(WANT_AWAIT_RESULTS) {
                wsEp.setAttribute(WANT_AWAIT_RESULTS, true);
            }

            wsEp.setAttribute(USERNAME, getUsername(req));
        } else {
            log:printError("Error occurred during WebSocket upgrade", wsEp);
        }
    }
}

function getTables() returns string {
    string body = "";
    if electionType == ELECTION_TYPE_PARLIAMENTARY {
        body = generateParliamentaryResultsTable();
    } else {
        body += generatePresidentialResultsTable(PRESIDENTIAL_PREFS_RESULT);
        body += generatePresidentialResultsTable(PRESIDENTIAL_RESULT);
    }
    return body;
}

# Print the results
# 
# + return - HTML string for results of the given type from the results cache
function generatePresidentialResultsTable(string 'type) returns string {
    string tab = "";
    int i = resultsCache.length();
    boolean first = true;
    while i > 0 { // show results in reverse order of release
        i = i - 1;
        Result r = resultsCache[i];
        if r.'type != 'type {
            continue;
        }
        if first {
            first = false;
            match 'type {
                PRESIDENTIAL_RESULT => { tab = "<h2>First Preference Results</h2>"; }
                PRESIDENTIAL_PREFS_RESULT => { tab = "<h2>Revised Results with Second/Third Preferences</h2>"; }
            }
            tab += "<table class='table'><tr><th>Election</th><th>Sequence No</th><th>Release Time</th><th>Code</th><th>Level</th><th>Electoral District</th><th>Polling Division</th><th>JSON</th><th>XML</th><th>HTML</th><th>Document</th></tr>";
        }
        string election = r.election;
        string seqNo = r.jsonResult.sequence_number.toString();
        string timestamp = r.jsonResult.timestamp.toString();
        string code = "";
        string level = r.jsonResult.level.toString();
        // figure out and ED / PD name if needed
        string edName = "";
        string pdName = "";
        match level {
            LEVEL_PD => { 
                code = r.jsonResult.pd_code.toString(); //  has 2 digit ED code and 1 letter PD code
                edName = r.jsonResult.ed_name.toString();
                pdName = r.jsonResult.pd_name.toString();
            }
            LEVEL_ED => { 
                code = r.jsonResult.ed_code.toString();
                edName = r.jsonResult.ed_name.toString();
            }
            LEVEL_NI => { }
            LEVEL_NF => {
                code = r.code.toString();
            }
        }

        tab = tab + "<tr>" +
                    "<td>" + election + "</td>" +
                    "<td>" + seqNo + "</td>" +
                    "<td>" + timestamp + "</td>" +
                    "<td>" + code + "</td>" +
                    "<td>" + level + "</td>" +
                    "<td>" + edName + "</td>" +
                    "<td>" + pdName + "</td>" +
                    "<td><a href='/result/" + r.election + "/" + seqNo + "?format=json'>JSON</a>" + "</td>" +
                    "<td><a href='/result/" + r.election + "/" + seqNo + "?format=xml'>XML</a>" + "</td>" +
                    "<td><a href='/result/" + r.election + "/" + seqNo + "?format=html'>HTML</a>" + "</td>" +
                    "<td><a href='/release/" + r.election + "/" + seqNo + "'>Release</a>" + "</td>" +
                    "</tr>";
    }
    tab = tab + "</table>";
    return tab;
}

# Print the parliamentary election results
#
# + return - HTML string for results from the results cache
function generateParliamentaryResultsTable() returns string {
    string tab = "<table class='table'><tr><th>Election</th><th>Sequence No</th><th>Release Time</th>" +
                 "<th>Type</th><th>Code</th><th>Level</th><th>Electoral District</th><th>Polling Division</th>" +
                 "<th>JSON</th><th>XML</th><th>HTML</th><th>Document</th></tr>";
    int i = resultsCache.length();
    while i > 0 { // show results in reverse order of release
        i -= 1;
        Result r = resultsCache[i];

        string election = r.election;
        string seqNo = r.jsonResult.sequence_number.toString();
        string timestamp = r.jsonResult.timestamp.toString();
        string 'type = r.jsonResult.'type.toString();
        string code = "-";
        string level = r.jsonResult.level.toString();
        // figure out and ED / PD name if needed
        string edName = "-";
        string pdName = "-";
        match level {
            LEVEL_PD => {
                code = r.jsonResult.pd_code.toString(); //  has 2 digit ED code and 1 letter PD code
                edName = r.jsonResult.ed_name.toString();
                pdName = r.jsonResult.pd_name.toString();
            }
            LEVEL_ED => {
                code = r.jsonResult.ed_code.toString();
                edName = r.jsonResult.ed_name.toString();
            }
            LEVEL_N => {
                code = r.code.toString();
            }
        }

        tab = tab + "<tr>" +
                    "<td>" + election + "</td>" +
                    "<td>" + seqNo + "</td>" +
                    "<td>" + timestamp + "</td>" +
                    "<td>" + 'type + "</td>" +
                    "<td>" + code + "</td>" +
                    "<td>" + level + "</td>" +
                    "<td>" + edName + "</td>" +
                    "<td>" + pdName + "</td>" +
                    "<td><a href='/result/" + r.election + "/" + seqNo + "?format=json'>JSON</a>" + "</td>" +
                    "<td><a href='/result/" + r.election + "/" + seqNo + "?format=xml'>XML</a>" + "</td>" +
                    "<td><a href='/result/" + r.election + "/" + seqNo + "?format=html'>HTML</a>" + "</td>";
        if ('type == RE_VI || 'type == RN_SI) {
            tab += "<td>" + "-" + "</td>";
        } else {
            tab += "<td><a href='/release/" + r.election + "/" + seqNo + "'>Release</a>" + "</td>";
        }
        tab += "</tr>";
    }
    tab = tab + "</table>";
    return tab;
}

task:TimerConfiguration timerConfiguration = {
    intervalInMillis: 30000,
    initialDelayInMillis: 30000
};
listener task:Listener timer = new (timerConfiguration);

service timerService on timer {
    resource function onTrigger() {
        string[] keys = jsonConnections.keys();
        foreach string k in keys {
            http:WebSocketCaller? con = jsonConnections[k];
            if !(con is ()) {
                log:printDebug("Pinging " + con.getConnectionId());
                _ = start ping(con);
            }
        }  
    }
}

function getUsername(http:Request request) returns string? {
    if !request.hasHeader(http:AUTH_HEADER) {
        return;
    }

    string headerValue = request.getHeader(http:AUTH_HEADER);
    
    if !(headerValue.startsWith(auth:AUTH_SCHEME_BASIC)) {
        return;
    }

    string credential = headerValue.substring(5, headerValue.length()).trim();

    var result = auth:extractUsernameAndPassword(credential);

    string? username = ();
    if (result is [string, string]) {
        [username, _] = result;
    }
    return <@untainted> username;
}

final byte[] pingData = "ping".toBytes();

function ping(http:WebSocketCaller con) {
    var err = con->ping(pingData);
    if (err is http:WebSocketError) {
        log:printError(string `Error pinging ${con.getConnectionId()}`, err);
    }
}
