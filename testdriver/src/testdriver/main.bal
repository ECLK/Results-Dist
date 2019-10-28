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
    map<boolean> published = {};

    if nr is () {
        return error("No results found");
    } else {
        http:Client resultsSystem = new (resultsURL);
        json result = null;
        string resCode = "";

        io:println("Publishing results:");
        while true {
            NSummaryStats ss = { registered_voters: 0, total_polled: 0, valid_votes: 0, rejected_votes: 0};
            NPartyResult[] pr;
            string level;
            string ed_name;
            string pd_name;

            int edNum = check readInt("\nEnter polling district code (1 to 22), 0 for national or -1 to exit: ");
            if edNum == -1 {
                break;
            } else if edNum == 0 {
                //result = sendNationalResult (nr, resultsSystem);
                io:println ("National not yet implemented");
                continue;
            } else if edNum < 1 || edNum > 22 {
                io:println("Bad ED entered!");
                continue;
            } else {
                NEDResult ner = nr.by_ed[edNum-1];
                int maxPDnum = ner.by_pd.length();

                ed_name = ner.ed_name;

                int pdNum = check readInt("Enter PD number from district (1-" + maxPDnum.toString() + ") or 0 for district: ");
                if pdNum < 0 || pdNum > maxPDnum {
                    io:println("Bad PD entered");
                    continue;
                } else if pdNum == 0 {
                    pd_name = ""; // N/A since this is a district total

                    // need to add up all the PDs in this ED
                    pr = ner.by_pd[0].by_party.clone();
                    boolean first = true;
                    ner.by_pd.forEach(
                        function (NPDResult n) {
                            if first == false {
                                int max = n.by_party.length()-1;
                                foreach int i in 0 ... max {
                                    pr[i].votes = pr[i].votes + n.by_party[i].votes;
                                }
                            }
                            first = false;
                            ss.registered_voters = ss.registered_voters + n.summary_stats.registered_voters;
                            ss.total_polled = ss.total_polled + n.summary_stats.total_polled;
                            ss.valid_votes = ss.valid_votes + n.summary_stats.valid_votes;
                            ss.rejected_votes = ss.rejected_votes + n.summary_stats.rejected_votes;
                        }
                    );
                    level = "ELECTORAL-DISTRICT";
                } else {
                    NPDResult npr = ner.by_pd[pdNum-1];
                    pd_name = npr.pd_name;
                    resCode = createResultCode (ner.ed_name.toString(), npr.pd_name.toString());
                    ss = npr.summary_stats;
                    pr = npr.by_party;
                    level = "POLLING-DIVISION";
                }
            }

            json[] by_party = pr.map(
                x => <json> { 
                    party_name: x.party, 
                    party_code: x.party, // note: we don't have proper data in the old data feeds
                    candidate: x.candidate,
                    votes: x.votes,
                    percentage: getPercentage(x.votes, ss.total_polled)
                }
            );

            // convert to right format
            result = {
                    'type : PRESIDENTIAL_RESULT,
                    timestamp: check time:format(time:currentTime(), "yyyy-MM-dd'T'HH:mm:ss.SSSZ"),
                    level: level,
                    ed_name: ed_name,
                    pd_name: pd_name,
                    by_party: by_party,
                    summary: {
                        valid: ss.valid_votes,
                        rejected: ss.rejected_votes,
                        polled: ss.total_polled,
                        electors: ss.registered_voters
                    }
            };
            string pubkey = result.level.toString()+result.ed_name.toString()+result.pd_name.toString();
            if published[pubkey] ?: false {
                io:println ("That is already published; pick something else");
                continue;
            }
            published[pubkey] = true;

            io:println("posting to /result/data/: electionCode=" + electionCode + 
                       "; resCode=" + resCode + "; data=" + result.toJsonString());
            _ = check resultsSystem->post ("/result/data/" + electionCode + "/" + resCode, result);
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