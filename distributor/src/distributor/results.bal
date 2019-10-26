import ballerina/http;
import ballerina/log;
import ballerina/mime;
import ballerina/websub;

# Service for results tabulation to publish results to. We assume that results tabulation will deliver
# a result in two separate messages - one with the json result data and another with an image of the
# signed result document.
# 
# Both will be saved for resilience and later access for subscribers who want it.
@http:ServiceConfig {
    basePath: "/result",
    auth: {
        scopes: ["publisher"]
    }
}
service receiveResults on resultsListener {
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/data/{resultCode}",
        body: "jsonResult"
    }
    resource function receiveData(http:Caller caller, http:Request req, string resultCode, json jsonResult) returns error? {
        PresidentialResult | PresidentialPreferencesResult result;
        string resultType;

        // make sure its a good result
        [resultType, result] = check convertJsonToResult (resultCode, jsonResult);
        log:printInfo("Result data received for '" + resultCode + "': " + jsonResult.toJsonString());

        // store the result in the DB against the resultCode and assign it a sequence #
        check saveResult(resultCode, jsonResult, resultType);

        // publish the received result asynchronously
        _ = start publishResultData(resultCode, jsonResult, result);

        // respond accepted
        return caller->accepted();
    }

    @http:ResourceConfig {
        methods: ["POST"],
        path: "/image/{resultCode}",
        body: "imageData"
    }
    resource function receiveImage(http:Caller caller, http:Request req, string resultCode, byte[] imageData) returns error? {
        log:printInfo("IMG Result received for '" + resultCode + "': " + imageData.toString());

        // store the image in the DB against the resultCode
        check saveImage(resultCode, req.getContentType(), imageData);

        // update website asynchronously
        _ = start updateWebsite();
        
        // respond accepted
        return caller->accepted();
    }
}

function convertJsonToResult (string resultCode, json jsonResult) returns [string, PresidentialResult | PresidentialPreferencesResult] | error {
    PresidentialResult | PresidentialPreferencesResult result;
    string resultType;

    if jsonResult.'type == PRESIDENTIAL_RESULT {
        result = check PresidentialResult.constructFrom(jsonResult);
        resultType = PRESIDENTIAL_RESULT;
    } else if jsonResult.'type == PRESIDENTIAL_PREFS_RESULT {
        result = check PresidentialResult.constructFrom(jsonResult);
        resultType = PRESIDENTIAL_PREFS_RESULT;
    } else {
        log:printError ("Unknown JSON data for '" + resultCode + "': " + jsonResult.toString());
        return error("Unknown result type for '" + resultCode + "': " + jsonResult.'type.toString());
    }
    return [resultType, result];
}

# Publish the results as follows:
# - update the website with the result
# - send SMSs to all subscribers
# - deliver the result data to all subscribers
function publishResultData(string resultCode, json jsonResult, PresidentialResult | PresidentialPreferencesResult result) {
        worker smsWorker {
            // Send SMS to all subscribers.
            // TODO - should we ensure SMS is sent first?
        }

        worker jsonWorker {
            log:printInfo("Notifying results for " + resultCode);
            websub:WebSubHub wh = <websub:WebSubHub> hub; // safe .. working around type guard limitation
            var r = wh.publishUpdate(JSON_RESULTS_TOPIC, jsonResult, mime:APPLICATION_JSON);
            if r is error {
                log:printError("Error publishing update: ", r);
            }
        }

        worker siteWorker {
            updateWebsite();
        }
}

function updateWebsite(){
    log:printInfo("Website Updated");
}
