import ballerina/config;
import ballerina/http;
import ballerina/log;
import ballerina/websub;
import ballerinax/java.jdbc;

import maryamzi/websub.hub.mysqlstore;

websub:WebSubHub webSubHub = startHubAndRegisterTopic();

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

    byte[]? key = ();
    string encryptionKey = config:getAsString("eclk.hub.db.encryptionkey");
    if (encryptionKey.trim() != "") {
        key = encryptionKey.toBytes();
    }

    mysqlstore:MySqlHubPersistenceStore persistenceStore = checkpanic new (subscriptionDb, key);

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
