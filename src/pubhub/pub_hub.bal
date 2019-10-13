import ballerina/config;
import ballerina/http;
import ballerina/log;
import ballerina/websub;
import ballerinax/java.jdbc;

import maryamzi/websub.hub.mysqlstore;

listener http:Listener httpListener = new (config:getAsInt("eclk.pub.port", 8080));

const ERROR_REASON = "{eclk/pubhub}Error";

// The topic against which the publisher will publish updates and the subscribers
// need to subscribe to, to receive result updates.
const RESULTS_TOPIC = "https://github.com/ECLK/Results-Dist"; // TODO: temp

websub:WebSubHub webSubHub = startHubAndRegisterTopic();

// Instead of another service here, we can have an upstream publisher publish directly to the hub. TBD.
@http:ServiceConfig {
    basePath: "/results.dist"
}
service resultDist on httpListener {

    // This resource accepts the discovery requests.
    // Requests received at this resource would respond with a Link Header
    // indicating the topic to subscribe to and the hub(s) to subscribe at.
    @http:ResourceConfig {
        methods: ["GET", "HEAD"]
    }
    resource function discover(http:Caller caller, http:Request req) {
        http:Response response = new;
        // Adds a link header indicating the hub and topic.
        websub:addWebSubLinkHeader(response, [webSubHub.hubUrl], RESULTS_TOPIC);
        var result = caller->accepted(response);
        if (result is error) {
            log:printError("Error responding on ordering", result);
        }
    }

    // This resource accepts result notification requests.
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/publish"
    }
    resource function publishResult(http:Caller caller, http:Request req) {
        json | error results = req.getJsonPayload();
        if (results is json) {
            error? result = caller->accepted();
            if (result is error) {
                log:printError("Error responding on result notification", result);
            }

            // Revisit what we are logging and the level.
            log:printInfo("Notifying results for " + results.toJsonString());

            error? updateResult = webSubHub.publishUpdate(RESULTS_TOPIC, results);
            if (updateResult is error) {
                log:printError("Error publishing update", updateResult);
            }
        } else {
            log:printError("Error retrieving payload", results);
            panic results;
        }
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
        error? result = hubStartUpResult.registerTopic(RESULTS_TOPIC);
        if (result is error) {
            // Not panicking here, since the error would usually be an already registered.
            // TODO: check if we can improve this be more specific
            log:printError("Error registering topic", result);
        }
        return hubStartUpResult;
    } else {
        panic error(ERROR_REASON, message = hubStartUpResult.message);
    }
}
