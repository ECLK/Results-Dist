import ballerina/http;
import ballerina/log;

listener http:Listener exposer = new http:Listener(8181);

http:Client resultsEp = new ("http://result-dist-1crbnh.pxe-dev-platformer-1552477983757-1pdna.svc");

@http:ServiceConfig {
    basePath: "/result"
}
service RPE on exposer {
    @http:ResourceConfig {
        path: "/data/{electionCode}/{resultCode}"
    }
    resource function forward (http:Caller hc, http:Request hr, string electionCode, string resultCode) returns error? {
        log:printInfo("Received request for /result/data/${electionCode}/${resultCode}");
        http:Response|error resp = resultsEp->forward("/result/data/${electionCode}/${resultCode}", hr);
        log:printInfo("Received response from backend: code=" + resp.toString());
        if resp is error {
            log:printInfo("Received error: " + resp.toString());
            return resp;
        } else {
            log:printInfo("Published to results distributor: " + resp.toString()); 
        }
    }
}
