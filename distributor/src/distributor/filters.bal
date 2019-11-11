import ballerina/auth;
import ballerina/encoding;
import ballerina/http;
import ballerina/log;
import ballerina/websub;

const WWW_AUTHENTICATE_HEADER = "WWW-Authenticate";

const HUB_TOPIC = "hub.topic";
const HUB_CALLBACK = "hub.callback";

map<string> resultCallbackMap = {};
map<string> imageCallbackMap = {};

# Filter to challenge authentication.
public type AuthChallengeFilter object {
    *http:RequestFilter;

    public function filterRequest(http:Caller caller, http:Request request, http:FilterContext context) 
                        returns boolean {
        if request.hasHeader(http:AUTH_HEADER) || request.rawPath != "/" {
            return true;
        }

        http:Response res = new;
        res.statusCode = 401;
        res.addHeader(WWW_AUTHENTICATE_HEADER, "Basic realm=\"EC Media Results Delivery\"");
        error? err =  caller->respond(res);
        if (err is error) {
            log:printError("error responding with auth challenge", err);
        }
        return false;
    }
};

# Filter to remove an existing subscription for a user, when a new subscription request is sent.
public type SubscriptionFilter object {
    *http:RequestFilter;

    public function filterRequest(http:Caller caller, http:Request request, http:FilterContext context) returns boolean {
        if request.rawPath != "/websub/hub" {
            return true;
        }

        if (!request.hasHeader(http:AUTH_HEADER)) {
            return false;
        }

        map<string>|error params = request.getFormParams();

        if params is error {
            log:printError("error extracting form params: " + params.toString());
            return false;
        }

        map<string> paramMap = <map<string>> params;
        if !paramMap.hasKey(HUB_TOPIC) || !paramMap.hasKey(HUB_CALLBACK) {
            log:printError("topic and/or callback not available");
            return false;
        }

        string topic = paramMap.get(HUB_TOPIC);
        string callback = paramMap.get(HUB_CALLBACK);
        
        string|error decodedTopic = encoding:decodeUriComponent(topic, "UTF-8");
        if (decodedTopic is string) {
            topic = decodedTopic;
        } else {
            log:printWarn("error decoding topic, using the original form: " + topic + ". Error: " + decodedTopic.toString());
        }


        map<string> callbackMap = resultCallbackMap;
        match topic {
            JSON_RESULTS_TOPIC => {
                callbackMap = resultCallbackMap;
            }
            IMAGE_PDF_TOPIC => {
                callbackMap = imageCallbackMap;
            }
            _ => {
                log:printError("subscription request received for invalid topic " + topic);
                return false;
            }
        }

        string|error decodedCallback = encoding:decodeUriComponent(callback, "UTF-8");
        if (decodedCallback is string) {
            callback = decodedCallback;
        } else {
            log:printWarn("error decoding callback, using the original form: " + callback + ". Error: " + decodedCallback.toString());
        }

        websub:Hub hubVar = <websub:Hub> hub;

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
                                username + ", and topic: " + topic);
                error? remResult = hubVar.removeSubscription(topic, existingCallback);
                if (remResult is error) {
                    log:printError("error removing existing subscription for username: " + username, remResult);
                }
                log:printInfo("Adding a new subscription callback: " + callback + ", for username: " +
                                username + ", and topic: " + topic);
                updateUserCallback(username, topic, callback);
            } else {
                log:printInfo("Adding a subscription callback: " + callback + ", for username: " + username +
                                ", and topic: " + topic);
                saveUserCallback(username, topic, callback);
            }
            callbackMap[username] = <@untainted> callback;
        } else {
            log:printError("Error extracting credentials", result);
            return false;
        }
        return true;
    }
};
