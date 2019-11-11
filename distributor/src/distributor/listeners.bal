import ballerina/auth;
import ballerina/config;
import ballerina/http;

# Listener for results tabulation to deliver results to us.
listener http:Listener resultsListener = new (config:getAsInt("eclk.pub.port", 8181));

http:BasicAuthHandler inboundBasicAuthHandler = new(new auth:InboundBasicAuthProvider());

# Listener for media orgs to subscribe, for the website and for them to pull specific results.
listener http:Listener mediaListener = new (config:getAsInt("eclk.hub.port", 9090), config = {
    auth: {
        authHandlers: [inboundBasicAuthHandler],
        mandateSecureSocket: false
    },
    filters: [new SubscriptionFilter()]
});
