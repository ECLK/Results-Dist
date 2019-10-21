import ballerina/config;
import ballerina/websub;

@websub:SubscriberServiceConfig {
    path: getAsStringOrPanic("subscriber.path"),
    subscribeOnStartUp: true,
    target: [getAsStringOrPanic("subscriber.hub"), getTopic()],
    leaseSeconds: 172800,
    secret: getAsStringOrPanic("subscriber.secret"),
    callback: getAsStringOrPanic("subscriber.url")
}
service subscriberService on new websub:Listener(getAsIntOrPanic("subscriber.port")) {
   resource function onNotification (websub:Notification notification) {
       // Intro logic to write to files.
   }
}

function getAsIntOrPanic(string key) returns int {
    int value = config:getAsInt(key);

    if (value == 0) {
        panic error("Error", message = key + " not specified or 0");
    }
    return value;
}

function getAsStringOrPanic(string key) returns string {
    string value = config:getAsString(key);

    if (value.trim() == "") {
        panic error("Error", message = key + " not specified or empty");
    }
    return value;
}

function getTopic() returns string {
    string topic = getAsStringOrPanic("subscriber.topic");

    match topic {
        "https://github.com/ECLK/Results-Dist-json"|
        "https://github.com/ECLK/Results-Dist-xml"|
        "https://github.com/ECLK/Results-Dist-text" => {
            return topic;
        }
        _ => {
            panic error("Error", message = "invalid topic specified: " + topic);
        }
    }
}
