import ballerina/config;
import ballerina/http;
import ballerina/log;
import ballerina/mime;
import ballerina/websub;
import ballerina/xmlutils;
import ballerinax/java.jdbc;

import maryamzi/websub.hub.mysqlstore;

websub:WebSubHub webSubHub = startHubAndRegisterTopic();

listener http:Listener httpListener = new (config:getAsInt("eclk.pub.port", 8181));

// Instead of another service here, we can have an upstream publisher publish directly to the hub. TBD.
@http:ServiceConfig {
    basePath: "/results.dist",
    auth: {
        scopes: ["publisher"]
    }
}
service resultDist on httpListener {

    // This resource accepts result notification requests.
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/publish"
    }
    resource function publishResult(http:Caller caller, http:Request req) {
        json|error payloadResult = req.getJsonPayload();

        if payloadResult is error {
            panic error(ERROR_REASON, message = "Error extracting JSON payload: " + payloadResult.toString());
        }

        error? respResult = caller->accepted();
        if (respResult is error) {
            log:printError("Error responding on result notification", respResult);
        }

        json jsonPayload = <json> payloadResult;

        worker smsWorker {
            // Send SMS to all subscribers.
            // TODO - should we ensure SMS is sent first?
        }

        worker jsonWorker {
            actOnValidUpdate(function() returns error? {
                log:printInfo("Notifying results for " + jsonPayload.toJsonString());
                return webSubHub.publishUpdate(JSON_RESULTS_TOPIC, jsonPayload, mime:APPLICATION_JSON);
            });
        }

        worker xmlWorker {
            xml|error xmlResult = xmlutils:fromJSON(jsonPayload);
            if xmlResult is error {
                panic error(ERROR_REASON, message = "Error converting JSON to XML: " + xmlResult.toString());
            }

            xml xmlPayload = <xml> xmlResult;
            actOnValidUpdate(function() returns error? {
                log:printInfo("Notifying results for " + xmlPayload.toString());
                return webSubHub.publishUpdate(XML_RESULTS_TOPIC, xmlPayload);
            });
        }

        worker textWorker {
            // TODO
            string stringPayload = jsonPayload.toJsonString();
            actOnValidUpdate(function() returns error? {
                log:printInfo("Notifying results for " + stringPayload);
                return webSubHub.publishUpdate(TEXT_RESULTS_TOPIC, stringPayload);
            });

        }

        worker imageWorker {
            // TODO
        }

        worker siteWorker {
            // TODO
        }
    }
}

function actOnValidUpdate(function() returns error? publishFunction) {
    error? publishResult = publishFunction();
    if (publishResult is error) {
        log:printError("Error publishing update", publishResult);
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

    string encryptionKey = config:getAsString("eclk.hub.db.encryptionkey");
    if (encryptionKey.trim() == "") {
        panic error(ERROR_REASON, message = "encryption key not specified or invalid");
    }

    mysqlstore:MySqlHubPersistenceStore persistenceStore = checkpanic new (subscriptionDb, encryptionKey.toBytes());

    websub:WebSubHub | websub:HubStartedUpError hubStartUpResult =
        websub:startHub(new http:Listener(config:getAsInt("eclk.hub.port", 9090)),
                        {
                            hubPersistenceStore: persistenceStore,
                            clientConfig: {
                                // TODO: finalize
                                retryConfig: {
                                    count:  3,
                                    intervalInMillis: 5000
                                },
                                followRedirects: {
                                    enabled: true,
                                    maxCount: 5
                                },
                                timeoutInMillis: 5*60000 // Check
                                //secureSocket: {
                                //    trustStore: {
                                //        path: config:getAsString("eclk.hub.client.truststore.path"),
                                //        password: config:getAsString("eclk.hub.client.truststore.password")
                                //    }
                                //}
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
    registerTopic(hub, IMAGE_RESULTS_TOPIC);
}

function registerTopic(websub:WebSubHub hub, string topic) {
    error? result = hub.registerTopic(topic);
    if (result is error) {
        string? message = result.detail()?.message;

        if (message is string && message.indexOf("topic already exists") != ()) {
            // Not panicking for failures due to already being registered.
            return;
        }

        panic result;
    }
}
