import ballerina/config;
import ballerina/http;
import ballerina/log;
import ballerina/mime;

listener http:Listener httpListener = new (config:getAsInt("eclk.pub.port", 8181));

type Result record {|
    string code;
    json jsonData?;
    string textData?;
    byte[] image?;
|};
Result[] savedResults = [{code: "SUMMARY/x/y", jsonData: {"some": "stuff"}}];

// service for results tabulation to publish results to
@http:ServiceConfig {
    basePath: "/result",
    auth: {
        scopes: ["publisher"]
    }
}
service receiveResults on httpListener {
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/data/{resultCode}",
        body: "result"
    }
    resource function receiveData(http:Caller caller, http:Request req, string resultCode, json result) returns error? {
        // store the result in the DB against the resultCode
        log:printInfo("Result data received: " + result.toString());
        savedResults.push(<Result>{code: resultCode, jsonData: result}); // temp

        // publish the received result asynchronously
        _ = start publishResultData(resultCode, result);

        // respond accepted
        check caller->accepted();
        return;
    }

    @http:ResourceConfig {
        methods: ["POST"],
        path: "/image/{resultCode}"
    }
    resource function receiveImage(http:Caller caller, http:Request req, string resultCode) returns error? {
        // save the image in the DB
        byte[] binaryPayload = check req.getBinaryPayload();
        log:printInfo("IMG Result received: " + binaryPayload.toString());

        // update website
        updateWebsite();
        
        // respond accepted
        check caller->accepted();
        return;
    }
}

# Publish the results as follows:
# - update the website with the result
# - send SMSs to all subscribers
# - deliver the result data to all subscribers
function publishResultData(string resultCode, json result){
        worker smsWorker {
            // Send SMS to all subscribers.
            // TODO - should we ensure SMS is sent first?
        }

        worker jsonWorker {
            actOnValidUpdate(function() returns error? {
                log:printInfo("Notifying results for " + result.toJsonString());
                return webSubHub.publishUpdate(JSON_RESULTS_TOPIC, result, mime:APPLICATION_JSON);
            });
        }

        worker imageWorker {
            // TODO
        }

        worker siteWorker {
            updateWebsite();
        }
}

function updateWebsite(){
    log:printInfo("Website Updated");
}
