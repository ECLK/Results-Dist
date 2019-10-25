import ballerina/io;
import ballerina/http;

map<NNationalResult> allresults = {};

public function main() returns error? {
    // load presidential election data from Nuwan
    check loadData();

    // send some results to the results system
    http:Client resultsSystem = new ("https://localhost:8181");

    

    io:println(allresults["2015"]?.year);
}

function loadData() returns error? {
    service svc = 
        @http:ServiceConfig {
            basePath: "/"
        }
        service {
            @http:ResourceConfig {
                methods: ["POST"],
                path: "/{year}",
                body: "result"
            }
            resource function data(http:Caller caller, http:Request req, string year, NNationalResult result) returns error? {
                allresults[year] = result;
                check caller->ok ("Thanks!");
            }
        };

    http:Listener hl = new(4444);
    check hl.__attach(svc);
    check hl.__start();
    _ = io:readln("POST json data to http://localhost:4444/YEAR now and hit RETURN to continue!");
    if allresults.length() == 0 {
        io:println("No results received!");
        return error("No results received");
    }
    check hl.__detach(svc);
    check hl.__immediateStop();
}