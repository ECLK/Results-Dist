import ballerina/http;
import ballerina/config;

# Listener for results tabulation to deliver results to us
listener http:Listener resultsListener = new (config:getAsInt("eclk.pub.port", 8181));

# Listener for media orgs to subscribe, for the website and for them to pull specific results
listener http:Listener mediaListener = new (config:getAsInt("eclk.hub.port", 9090));