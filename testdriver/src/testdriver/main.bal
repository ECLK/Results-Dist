import ballerina/io;
import ballerina/http;
import ballerina/lang.'int;
import ballerina/time;
import ballerina/stringutils as su;

const PRESIDENTIAL_RESULT = "PRESIDENTIAL-FIRST";

map<NNationalResult> allresults = {};

public function main(string resultsURL) returns error? {
    // load presidential election data from Nuwan
    check loadData();

    // send some results to the results system
    string electionCode = allresults.keys()[0];
    NNationalResult? nr = allresults[electionCode];
    if nr is () {
        return error("No results found");
    } else {
        http:Client resultsSystem = new (resultsURL);

        io:println("Publishing results:");
        while true {
            int edNum = check readInt("\nEnter polling district code (0-21) or -1 to exit: ");
            if edNum == -1 {
                break;
            }
            if edNum < 0 || edNum > 21 {
                io:println("Bad ED entered!");
                continue;
            }
            NEDResult ner = nr.by_ed[edNum];
            int maxPDnum = ner.by_pd.length() - 1;
            int pdNum = check readInt("Enter PD number from district (0-" + maxPDnum.toString() + "): ");
            if pdNum < 0 || pdNum > maxPDnum {
                io:println("Bad PD entered");
                continue;
            }
            NPDResult npr = ner.by_pd[pdNum];
            string resCode = createResultCode (ner.ed_name.toString(), npr.pd_name.toString());
            NSummaryStats ns = npr.summary_stats;
            json[] by_party = 
                npr.by_party.map(
                    x => <json>{ 
                            party: x.party,
                            candidate: x.candidate,
                            votes: x.votes,
                            percentage: getPercentage(x.votes, ns.total_polled)
                        });

            // convert to right format
            json sr = {
                    'type : PRESIDENTIAL_RESULT,
                    timestamp: check time:format(time:currentTime(), "yyyy-MM-dd'T'HH:mm:ss.SSSZ"),
                    level: "POLLING-DIVISION",
                    ed_name: ner.ed_name,
                    pd_name: npr.pd_name,
                    by_party: by_party,
                    summary: {
                        valid: ns.valid_votes,
                        rejected: ns.rejected_votes,
                        polled: ns.total_polled,
                        electors: ns.registered_voters
                    }
            };

            io:println("posting to /result/data/: electionCode=" + electionCode + 
                       "; resCode=" + resCode + "; data=" + sr.toJsonString());
            var res = check resultsSystem->post ("/result/data/" + electionCode + "/" + resCode, sr);
        }
    }

    io:println("ALL DONE: press ^C to exit (not sure why!)");
}

function createResultCode (string edName, string pdName) returns string {
    string code = edName + "--" + pdName;
    return su:replaceAll(code, " ", "_");
}

// return %ge with 2 digits precision
function getPercentage (int votes, int total_polled) returns string {
    float f;

    f = (votes*100.0)/total_polled;
    return io:sprintf("%.2f", f);
}

function loadData() returns error? {
    service svc = 
        @http:ServiceConfig {
            basePath: "/"
        }
        service {
            @http:ResourceConfig {
                methods: ["POST"],
                path: "/{election}",
                body: "result"
            }
            resource function data(http:Caller caller, http:Request req, string election, NNationalResult result) returns error? {
                allresults[<@untainted> election] = <@untainted> result;
                io:println("Received data for election: " + election);
                check caller->ok ("Thanks!");
            }
        };

    http:Listener hl = new(4444);
    check hl.__attach(svc);
    check hl.__start();
    _ = io:readln("POST json data to http://localhost:4444/ELECTION now and hit RETURN to continue!");
    if allresults.length() == 0 {
        io:println("No results received!");
        return error("No results received");
    }
    check hl.__detach(svc);
    check hl.__immediateStop();
}

function readInt (string msg) returns int | error {
    string input = io:readln(msg);
    return <@untainted> 'int:fromString(input);
}