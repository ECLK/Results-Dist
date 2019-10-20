import ballerina/config;
import ballerina/log;
import ballerina/runtime;
import ballerina/test;
import ballerina/websub;

const TWO_DAYS_IN_SECONDS = 172800;

@tainted json receivedJsonOrNil = ();
@tainted xml? receivedXmlOrNil = ();
@tainted string? receivedTextOrNil = ();

///////////////////////////// The Subscriber Services /////////////////////////////

// The listener to which the subscriber services are bound.
listener websub:Listener subscriberListener = new(8181);

@websub:SubscriberServiceConfig {
    path: "/json",
    subscribeOnStartUp: true,
    target: ["http://localhost:9090/websub/hub", "https://github.com/ECLK/Results-Dist-json"],
    leaseSeconds: TWO_DAYS_IN_SECONDS
}
service jsonSubscriber on subscriberListener {

    // The resource which accepts the content delivery requests.
    resource function onNotification(websub:Notification notification) {
        var payload = notification.getJsonPayload();
        if (payload is json) {
            log:printInfo("WebSub JSON notification received: " + payload.toJsonString());
            receivedJsonOrNil = payload;
        } else {
            log:printError("Error retrieving JSON payload", payload);
        }
    }
}

@websub:SubscriberServiceConfig {
    path: "/xml",
    subscribeOnStartUp: true,
    target: ["http://localhost:9090/websub/hub", "https://github.com/ECLK/Results-Dist-xml"],
    leaseSeconds: TWO_DAYS_IN_SECONDS,
    secret: config:getAsString("subs.secret.xml")
}
service xmlSubscriber on subscriberListener {

    resource function onNotification(websub:Notification notification) {
        var payload = notification.getXmlPayload();
        if (payload is xml) {
            log:printInfo("WebSub XML notification received: " + payload.toString());
            receivedXmlOrNil = payload;
        } else {
            log:printError("Error retrieving XML payload", payload);
        }
    }
}

@websub:SubscriberServiceConfig {
    path: "/text",
    subscribeOnStartUp: true,
    target: ["http://localhost:9090/websub/hub", "https://github.com/ECLK/Results-Dist-text"],
    leaseSeconds: TWO_DAYS_IN_SECONDS,
    secret: config:getAsString("subs.secret.text")
}
service textSubscriber on subscriberListener {

    resource function onNotification(websub:Notification notification) {
        var payload = notification.getTextPayload();
        if (payload is string) {
            log:printInfo("WebSub text notification received: " + payload.toString());
            receivedTextOrNil = payload;
        } else {
            log:printError("Error retrieving text payload", payload);
        }
    }
}

const map<map<int>> jsonUpdate = {"Result": {"candOne": 110500, "candTwo": 9500}};
final xml xmlUpdate = xml `<Result><candOne>110500</candOne><candTwo>9500</candTwo></Result>`;
const textUpdate = "Result: candOne: 110500, candTwo: 9500";

@test:BeforeSuite
function publish() {
    runtime:sleep(5000); // wait for subscription process to complete.
    websub:Client hubClient = new("http://localhost:9090/websub/hub");
    error? res = webSubHub.publishUpdate("https://github.com/ECLK/Results-Dist-json",
                                         jsonUpdate,
                                         "application/json");
    checkpanic hubClient->publishUpdate("https://github.com/ECLK/Results-Dist-xml", xmlUpdate,
                                        "application/xml");
    checkpanic hubClient->publishUpdate("https://github.com/ECLK/Results-Dist-text", textUpdate, "text/plain");
    runtime:sleep(5000); // wait for update notification
}

@test:Config {}
function testContentReceipt() {
    test:assertEquals(receivedJsonOrNil, jsonUpdate);
    test:assertEquals(receivedXmlOrNil, xmlUpdate);
    test:assertEquals(receivedTextOrNil, textUpdate);
}
