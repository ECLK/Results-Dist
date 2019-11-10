import ballerina/auth;
import ballerina/encoding;
import ballerina/http;
import ballerina/log;
import ballerina/websub;

const HUB_TOPIC = "hub.topic";
const HUB_CALLBACK = "hub.callback";

map<string> callbackMap = {};

public type SubscriptionFilter object {
    *http:RequestFilter;

    public function filterRequest(http:Caller caller, http:Request request, http:FilterContext context) returns boolean {
        map<string>|error params = request.getFormParams();

        if params is error {
            log:printDebug("error extracting form params: " + params.toString());
            return true;
        }

        map<string> paramMap = <map<string>> params;
        if !paramMap.hasKey(HUB_TOPIC) || !paramMap.hasKey(HUB_CALLBACK) {
            log:printError("topic and/or callback not available");
            return true;
        }

        string topic = paramMap.get(HUB_TOPIC);
        string callback = paramMap.get(HUB_CALLBACK);
        
        string|error decodedTopic = encoding:decodeUriComponent(topic, "UTF-8");
        if (decodedTopic is string) {
            topic = decodedTopic;
        } else {
            log:printWarn("error decoding topic, using the original form: " + topic + ". Error: " + decodedTopic.toString());
        }

        if (topic != JSON_RESULTS_TOPIC && topic != IMAGE_PDF_TOPIC) {
            log:printError("subscription request received for invalid topic " + topic);
            return false;
        }

        string|error decodedCallback = encoding:decodeUriComponent(callback, "UTF-8");
        if (decodedCallback is string) {
            callback = decodedCallback;
        } else {
            log:printWarn("error decoding callback, using the original form: " + callback + ". Error: " + decodedCallback.toString());
        }

        websub:Hub hubVar = <websub:Hub> hub;

        if (!request.hasHeader(http:AUTH_HEADER)) {
            return false;
        }

        string headerValue = request.getHeader(http:AUTH_HEADER);
        
        if !(headerValue.startsWith(auth:AUTH_SCHEME_BASIC)) {
            return false;
        }

        string credential = headerValue.substring(5, headerValue.length()).trim();

        var result = auth:extractUsernameAndPassword(credential);

        if (result is [string, string]) {
            [string, string][username, _] = result;
            
            if callbackMap.hasKey(username) {
                string existingCallback = callbackMap.get(username);
                log:printInfo("Removing existing subscription callback: " + existingCallback + ", for username: " +
                                username);
                error? remResult = hubVar.removeSubscription(topic, existingCallback);
                if (remResult is error) {
                    log:printError("error removing existing subscription for username: " + username, remResult);
                }
                log:printInfo("Adding a new subscription callback: " + callback + ", for username: " +
                                username);
                updateUserCallback(username, callback);
            } else {
                log:printInfo("Adding a subscription callback: " + callback + ", for username: " + username);
                saveUserCallback(username, callback);
            }
            callbackMap[username] = <@untainted> callback;
        } else {
            log:printError("Error extracting credentials", result);
            return false;
        }
        return true;
    }
};
