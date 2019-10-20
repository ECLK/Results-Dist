import ballerina/config;
import ballerina/http;
import ballerina/log;
import ballerina/mime;
import ballerina/websub;
import ballerinax/java.jdbc;

import maryamzi/websub.hub.mysqlstore;

listener http:Listener httpListener = new (config:getAsInt("eclk.pub.port", 8080));

websub:WebSubHub webSubHub = startHubAndRegisterTopic();

// Instead of another service here, we can have an upstream publisher publish directly to the hub. TBD.
@http:ServiceConfig {
    basePath: "/results.dist"
}
service resultDist on httpListener {

    // This resource accepts result notification requests.
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/publish"
    }
    resource function publishResult(http:Caller caller, http:Request req) {
        if !(req.hasHeader(mime:CONTENT_TYPE)) {
            panic error(ERROR_REASON, message = "content-type header not available!");
        }

        publishContent(caller, req.getHeader(mime:CONTENT_TYPE), req);
    }

}

// Revisit what we are logging and the level.
function publishContent(http:Caller caller, string contentType, http:Request req) {
    if (contentType.endsWith("json")) {
        json|error content = req.getJsonPayload();
        if (content is json) {
            json jsonContent = content;
            actOnValidUpdate(caller, function() returns error? {
                log:printInfo("Notifying results for " + jsonContent.toJsonString());
                return webSubHub.publishUpdate(JSON_RESULTS_TOPIC, jsonContent, contentType);
            });
        } else {
            logAndRespondPayloadRetrievalFailure(caller, <@untainted> content);
        }
    } else if (contentType.endsWith("xml")) {
        xml|error content = req.getXmlPayload();
        if (content is xml) {
            xml xmlContent = content;
            actOnValidUpdate(caller, function() returns error? {
                log:printInfo("Notifying results for " + xmlContent.toString());
                return webSubHub.publishUpdate(XML_RESULTS_TOPIC, xmlContent, contentType);
            });
        } else {
            logAndRespondPayloadRetrievalFailure(caller, <@untainted> content);
        }
    } else {
        if (contentType.toLowerAscii() != mime:TEXT_PLAIN) {
            panic error(ERROR_REASON, message = "Unsupported content type: " + contentType);
        }

        string|error content = req.getTextPayload();
        if (content is string) {
            string stringContent = content;
            actOnValidUpdate(caller, function() returns error? {
                log:printInfo("Notifying results for " + stringContent);
                return webSubHub.publishUpdate(TEXT_RESULTS_TOPIC, stringContent, contentType);
            });
        } else {
            logAndRespondPayloadRetrievalFailure(caller, <@untainted> content);
        }
    }
}

function actOnValidUpdate(http:Caller caller, function() returns error? publishFunction) {
    error? result = caller->accepted();
    if (result is error) {
        log:printError("Error responding on result notification", result);
    }
    error? publishResult = publishFunction();
    if (publishResult is error) {
        log:printError("Error publishing update", publishResult);
    }
}

function logAndRespondPayloadRetrievalFailure(http:Caller caller, error err) {
    log:printError("Error retrieving payload", err);
    http:Response response = new;
    response.statusCode = http:STATUS_INTERNAL_SERVER_ERROR;
    response.setPayload("Error retrieving payload: " + err.toString());
    error? result = caller->respond(response);
    if (result is error) {
        log:printError("Error responding on payload retrieval failure", result);
    }
}

function startHubAndRegisterTopic() returns websub:WebSubHub {
    jdbc:Client subscriptionDb = new ({
        url: config:getAsString("eclk.hub.db.url"),
        username: config:getAsString("eclk.hub.db.username"),
        password: config:getAsString("eclk.hub.db.password"),
        dbOptions: {
            useSSL: config:getAsString("eclk.hub.db.useSsl")
        }
    });

    mysqlstore:MySqlHubPersistenceStore persistenceStore = checkpanic new (subscriptionDb);

    websub:WebSubHub | websub:HubStartedUpError hubStartUpResult =
        websub:startHub(new http:Listener(config:getAsInt("eclk.hub.port", 9090)),
                        {
                            remotePublish: {
                                enabled: config:getAsBoolean("eclk.hub.remotepublish.enabled")
                            },
                            hubPersistenceStore: persistenceStore,
                            clientConfig: {
                                // TODO: finalize
                                retryConfig: {
                                    count:  3,
                                    intervalInMillis: 5000
                                }
                            }
                        });

    if (hubStartUpResult is websub:WebSubHub) {
        registerTopics(hubStartUpResult);
        return hubStartUpResult;
    } else {
        panic error(ERROR_REASON, message = hubStartUpResult.message);
    }
}

function registerTopics(websub:WebSubHub hub) {
    registerTopic(hub, JSON_RESULTS_TOPIC);
    registerTopic(hub, XML_RESULTS_TOPIC);
    registerTopic(hub, TEXT_RESULTS_TOPIC);
}

function registerTopic(websub:WebSubHub hub, string topic) {
    error? result = hub.registerTopic(topic);
    if (result is error) {
        // Not panicking here, since the error would usually be an already registered.
        // TODO: check if we can improve this be more specific
        log:printError("Error registering topic", result);
    }
}
