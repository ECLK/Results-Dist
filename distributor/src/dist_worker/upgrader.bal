import ballerina/auth;
import ballerina/config;
import ballerina/file;
import ballerina/http;
import ballerina/log;
import ballerina/task;

const WANT_IMAGE = "image";
const WANT_AWAIT_RESULTS = "await";

map<http:WebSocketCaller> jsonConnections = {};
map<http:WebSocketCaller> imageConnections = {};
map<http:WebSocketCaller> awaitConnections = {};

service connector = @http:WebSocketServiceConfig {} service {

    resource function onOpen(http:WebSocketCaller caller) {
        string connectionId = caller.getConnectionId();

        log:printInfo("Registered: " + connectionId);

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

        log:printInfo(string `Unregistered: ${connectionId}, statusCode: ${statusCode}, reason: ${reason}`);     
    }
};

@http:ServiceConfig {
    basePath: "/"
}
service receiver on new http:Listener(config:getAsInt("eclk.dist_worker.receiver.port", 8080)) {
    
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/await",
        body: "message"
    }
    resource function receiveNotification(http:Caller caller, http:Request req, string message) returns error? {
        log:printInfo("Notification initiated for '" + message + "'");

        pushAwaitNotification(message);        

        return caller->accepted();
    }

    @http:ResourceConfig {
        methods: ["POST"],
        path: "/result",
        body: "jsonResult"
    }
    resource function receiveData(http:Caller caller, http:Request req, json jsonResult) returns error? {
        map<json> resultObject = <map<json>> jsonResult; 
        map<json> result = <map<json>> resultObject.result;

        log:printInfo("Result dissemination initiated for " + result.sequence_number.toString());

        publishResultData(resultObject);

        return caller->accepted();
     }

    @http:ResourceConfig {
        methods: ["POST"],
        path: "/image",
        body: "imageData"
    }
    resource function receiveImage(http:Caller caller, http:Request req, json imageData) returns error? {
        map<json> update = <map<json>> imageData; 
        log:printInfo("Image PDF dissemination initiated for " + update.sequence_number.toString());

        publishResultImage(update);

        // respond accepted
        return caller->accepted();
    }
}

http:BasicAuthHandler inboundBasicAuthHandler = new (new auth:InboundBasicAuthProvider());

# Listener for media orgs to subscribe, for the website and for them to pull specific results.
listener http:Listener subscriptionListener = new (config:getAsInt("eclk.dist_worker.disseminator.port", 8282), config = {
    auth: {
        authHandlers: [inboundBasicAuthHandler],
        mandateSecureSocket: false
    }
});


@http:ServiceConfig {
    basePath: "/"
}
service disseminator on subscriptionListener {
    
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

    @http:ResourceConfig {
        webSocketUpgrade: {
            upgradePath: "/connect",
            upgradeService: connector
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
        } else {
            log:printError("Error occurred during WebSocket upgrade", wsEp);
        }
    }
}

# Publish the results as follows:
# - update the website with the result
# - deliver the result data to all subscribers
function publishResultData(json resultAll) {
    string[] keys = jsonConnections.keys();
    foreach string k in keys {
        http:WebSocketCaller? con = jsonConnections[k];
        if !(con is ()) {
           log:printInfo("Sending JSON data for " + con.getConnectionId());
           _ = start pushData(con, "results data", resultAll);
        }
    }
}

function pushData(http:WebSocketCaller con, string kind, json data) {
    var err = con->pushText(data);
    if (err is http:WebSocketError) {
        log:printError(string `Error pushing ${kind} for ${con.getConnectionId()}`, err);
    }
}

# Publish results image.
function publishResultImage(json imageData) {
    string[] keys = imageConnections.keys();
    foreach string k in keys {
        http:WebSocketCaller? con = imageConnections[k];
        if !(con is ()) {
           log:printInfo("Sending image data for " + con.getConnectionId());
           _ = start pushData(con, "image data", imageData);
        }
    }
}

function pushAwaitNotification(string message) {
    string jsonString = "\"" + message + "\"";
    string[] keys = awaitConnections.keys();
    foreach string k in keys {
        http:WebSocketCaller? con = awaitConnections[k];
        if !(con is ()) {
           log:printInfo("Sending await notification for " + con.getConnectionId());
           _ = start pushData(con, "await notification", jsonString);
        }
    }
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

final byte[] pingData = "ping".toBytes();

function ping(http:WebSocketCaller con) {
    var err = con->ping(pingData);
    if (err is http:WebSocketError) {
        log:printError(string `Error pinging ${con.getConnectionId()}`, err);
    }
}
