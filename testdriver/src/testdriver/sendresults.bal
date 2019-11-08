import ballerina/io;
import ballerina/http;
import ballerina/lang.'int;
import ballerina/time;
import ballerina/math;
import ballerina/runtime;

const PRESIDENTIAL_RESULT = "PRESIDENTIAL-FIRST";

function publishOneSet () returns error? {
    string electionCode = "2015-PRE-REPLAY-" + io:sprintf("%03d", runCount);
    http:Client rc = new (resultsURL);

    io:println("Publishing new result set starting at " + time:currentTime().toString());
    _ = check rc->get("/result/reset"); // reset the results store
    
    boolean[] pdSent = [];
    int[] edSent = []; // # of result sent per ED
    int nPDs = 160 + 22; // including polling divs
    int nEDs = 22;

    // init these as I'm reading them before assigning - looks like default value can't be read (?)
    foreach int i in 0..< nPDs {
        pdSent[i] = false;
        if i < nEDs {
            edSent[i] = 0;
        }
    }

    int sentCount = 0;
    while sentCount < nPDs+nEDs {
        int edCode = check math:randomInRange(0, nEDs);
        // if we've sent as many results for this ED as there are PDs there then done with that district
        if edSent[edCode] == results[edCode].length() { 
            // find an unfinished ED
            edCode = -1;
            foreach int i in 0 ..< 22 {
                if edSent[i] < results[i].length() {
                    edCode = i;
                    break;
                }
            }
            if edCode == -1 {
                panic error ("World is flat - No EDs which are not complete! What am I doing here?!");
            }
        }

        // get a PD result from the selected ED
        int pdCode = check math:randomInRange(0, nPDs);
        int edOfPD = check 'int:fromString(resultsByPD[pdCode].ed_code.toString()) - 1; // code in results is 1-based
        if edOfPD != edCode || pdSent[pdCode] == true { // if PD is in wrong ED or is already sent then find another
            // find an unsent PD in the selected ED
            pdCode = -1;
            foreach int i in 0 ..< nPDs {
                edOfPD = check 'int:fromString(resultsByPD[i].ed_code.toString()) - 1; // code in results is 1-based
                if pdSent[i] == false && edOfPD == edCode {
                    pdCode = i;
                    break;
                }
            }
            if pdCode == -1 {
                panic error ("World is flat - No unsent PD in this ED: " + edCode.toString());
            }
        }

        // send PD result
        if pdSent[pdCode] == true {
            panic error ("World is flat - Trying to resend result for pdCode = " + pdCode.toString());
        }
        pdSent[pdCode] = true;

        // add missing info in test data: party_name and candidate for each party result
        json[] pr = <json[]>resultsByPD[pdCode]?.by_party;
        foreach int i in 0 ..< pr.length() {
            map<json> onePr = <map<json>>pr[i];
            onePr["party_name"] = "Party " + <string>pr[i].party_code;
            onePr["candidate"] = "Candidate " + <string>pr[i].party_code;
            // change percentage to string
            var val = trap <float>pr[i].percentage;
            if val is error {
                // already a string so let it go
            } else {
                onePr["percentage"] = io:sprintf ("%.2f", val);
            }
           // this line causes generated code to hang here: the cast is in error but no runtime error but just STOP!
           // looks like updating a json property that is already there really upsets the code :(
           //onePr["percentage"] = io:sprintf ("%.2f", <string>pr[i].percentage);
        }

        string resCode = resultsByPD[pdCode]?.pd_code.toString();
        string edCodeFromPD = resultsByPD[pdCode]?.ed_code.toString();
        io:println(io:sprintf("Sending PD results for %s", resCode));
        check sendResult (rc, electionCode, PRESIDENTIAL_RESULT, resCode, resultsByPD[pdCode]);
        edSent[edCode] = edSent[edCode] + 1; // sent another result for this ED
        sentCount = sentCount + 1;
 
        // send ED result if I've sent as many PD results for this district as there are PDs there
        if edSent[edCode] == results[edCode].length() { 
            resCode = io:sprintf("%02d", edCode+1);
            io:println(io:sprintf("Sending ED results for resCode=%s", resCode));
            check sendResult (rc, electionCode, PRESIDENTIAL_RESULT, resCode, check createEDResult(edCode));
            sentCount = sentCount + 1;
        }

        // delay a bit
        runtime:sleep(sleeptime);
    }
    io:println("Published ", sentCount, " results.");
    alreadyRunning = false;
    runCount = runCount + 1;
}

type DistSummary record {
    int valid;
    int rejected;
    int polled;
    int electors;
}; 

function createEDResult (int edCode) returns map<json> | error {
    map<map<json>> byPDResults = results[edCode];
    string ed_code = "";
    string ed_name = "";
    map<json>[] distByParty = []; // array of json value each for a single party results for the district
    DistSummary distSummary = { // aggregate results (not by_party)
        valid: 0, 
        rejected: 0, 
        polled: 0, 
        electors: 0
    };
    int[] votes_by_party = [];
    int pdCount = 0;
    foreach [string, json] [pdCode, pdResult] in byPDResults.entries() {
        ed_code = <string> pdResult.ed_code;
        ed_name = <string> pdResult.ed_name;
        json[] by_party = <json[]> pdResult.by_party;
        int nparties = by_party.length();
        foreach int i in 0 ..< nparties {
            if pdCount == 0 { // at the first PD of the ED
                // init vote count to zero for i-th party at first PD in district
                votes_by_party[i] = 0;

                // set up 
                distByParty[i] = {};
                distByParty[i]["party_code"] = check by_party[i].party_code;
                distByParty[i]["party_name"] = "Party " + <string>distByParty[i]["party_code"]; // no party_name in test data
                distByParty[i]["candidate"] = "Candidate " + <string>distByParty[i]["party_code"]; // no candidate name in test data
            } else if pdCount > 1 && distByParty[i].party_code != by_party[i].party_code {
                // all parties are supposed to be in the same order in each PD
                panic error("Unexpected problem: party codes are not in the same order across all PDs of district " +
                            pdResult.ed_name.toString());
            }
            // add up votes and do %ge later as totals are not yet known
            votes_by_party[i] = votes_by_party[i] + <int>by_party[i].votes;            
        }

        // add up the summary results
        DistSummary summary = check DistSummary.constructFrom(check pdResult.summary);
        distSummary.valid += summary.valid;
        distSummary.rejected += summary.rejected;
        distSummary.polled += summary.polled;
        distSummary.electors += summary.electors;

        pdCount += 1;
    }

    // put the vote total & percentages in the result json
    foreach int i in 0 ... votes_by_party.length()-1 {
        distByParty[i]["votes"] = votes_by_party[i];
        distByParty[i]["percentage"] = io:sprintf ("%.2f", votes_by_party[i]*100.0/distSummary.valid);
    }

    return {
        'type: "PRESIDENTIAL-FIRST", 
        timestamp: check time:format(time:currentTime(), "yyyy-MM-dd'T'HH:mm:ss.SSSZ"),
        level: "ELECTORAL-DISTRICT", 
        ed_code: ed_code,
        ed_name: ed_name,
        by_party: distByParty,
        summary: check json.constructFrom(distSummary)
    };
}

function sendResult (http:Client hc, string electionCode, string resType, string resCode, map<json> result) returns error? {
    // reset time stamp of the result to now
    result["timestamp"] = check time:format(time:currentTime(), "yyyy-MM-dd'T'HH:mm:ss.SSSZ");

    http:Response hr = check hc->post ("/result/data/" + electionCode + "/" + resType + "/" + resCode, result);
    if hr.statusCode != http:STATUS_ACCEPTED {
        io:println("Error while posting result to: /result/data/" + electionCode + "/" + resType + "/" + resCode);
        io:println("\tstatus=", hr.statusCode, ", contentType=", hr.getContentType(), " payload=", hr.getTextPayload());
        return error ("Unable to post result for " + resCode);
    }
}
