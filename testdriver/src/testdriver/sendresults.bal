import ballerina/io;
import ballerina/http;
import ballerina/lang.'int;
import ballerina/time;
import ballerina/math;
import ballerina/runtime;
import ballerina/encoding;

function sendResults(string resultType, string electionCode, http:Client rc, map<map<json>>[] results, map<json>[] resultsByPD) returns error? {
    
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

        // add missing info in test data: party_name and candidate for each party result if nedeed only (2019 set has it)
        json[] pr = <json[]>resultsByPD[pdCode]?.by_party;
        foreach int i in 0 ..< pr.length() {
            map<json> onePr = <map<json>>pr[i];
            if pr[i].party_name is string {
                continue;
            }
            onePr["party_name"] = (pr[i].party_name is string) ? check pr[i].party_name : "Party " + <string>pr[i].party_code;
            onePr["candidate"] = (pr[i].candidate is string) ? check pr[i].candidate : "Candidate " + <string>pr[i].party_code;
            // change percentage to string
            var val = trap <float>pr[i].vote_percentage;
            if val is error {
                // already a string so let it go
            } else {
                onePr["vote_percentage"] = io:sprintf ("%.2f", val);
            }
           // this line causes generated code to hang here: the cast is in error but no runtime error but just STOP!
           // looks like updating a json property that is already there really upsets the code :(
           //onePr["vote_percentage"] = io:sprintf ("%.2f", <string>pr[i].vote_percentage);
        }

        // set the percentages in the summary
        map<json> summary = <map<json>>resultsByPD[pdCode].summary;
        summary["percent_valid"] = (<int>resultsByPD[pdCode].summary.polled == 0) ? "0.00" : io:sprintf("%.2f", <int>resultsByPD[pdCode].summary.valid*100.0/<int>resultsByPD[pdCode].summary.polled);
        summary["percent_rejected"] = (<int>resultsByPD[pdCode].summary.polled == 0) ? "0.00" : io:sprintf("%.2f", <int>resultsByPD[pdCode].summary.rejected*100.0/<int>resultsByPD[pdCode].summary.polled);
        summary["percent_polled"] = (<int>resultsByPD[pdCode].summary.electors == 0) ? "0.00" : io:sprintf("%.2f", <int>resultsByPD[pdCode].summary.polled*100.0/<int>resultsByPD[pdCode].summary.electors);

        string resCode = resultsByPD[pdCode]?.pd_code.toString();
        string edCodeFromPD = resultsByPD[pdCode]?.ed_code.toString();
        io:println(io:sprintf("Sending PD results for %s", resCode));
        check sendResult (rc, electionCode, resultType, resCode, resultsByPD[pdCode]);
        edSent[edCode] = edSent[edCode] + 1; // sent another result for this ED
        sentCount = sentCount + 1;
 
        // send ED result if I've sent as many PD results for this district as there are PDs there
        if edSent[edCode] == results[edCode].length() { 
            resCode = io:sprintf("%02d", edCode+1);
            io:println(io:sprintf("Sending ED results for resCode=%s", resCode));
            check sendResult (rc, electionCode, resultType, resCode, check createEDResult(resultType, results, resultsByPD, edCode));
            sentCount = sentCount + 1;
        }

        // delay a bit
        runtime:sleep(sleeptime);
    }

    io:println("Sending national results");
    check sendResult (rc, electionCode, resultType, "FINAL", check createNationalResult(resultType, results, resultsByPD)); // "FINAL" is unused
    io:println("Published ", sentCount+1, " results.");
    alreadyRunning = false;
    runCount = runCount + 1;
}

type Summary record {
    int valid;
    int rejected;
    int polled;
    int electors;
    string percent_valid;
    string percent_rejected;
    string percent_polled;
}; 

function createEDResult (string resultType, map<map<json>>[] results, map<json>[]resultsByPD, int edCode) returns map<json> | error {
    map<map<json>> byPDResults = results[edCode];
    string ed_code = "";
    string ed_name = "";
    map<json>[] distByParty = []; // array of json value each for a single party results for the district
    Summary distSummary = { // aggregate results (not by_party)
        valid: 0, 
        rejected: 0, 
        polled: 0, 
        electors: 0,
        percent_valid: "",
        percent_rejected: "",
        percent_polled: ""
    };
    int[] votes_by_party = [];
    int[] votes1st_by_party = [];
    int[] votes2nd_by_party = [];
    int[] votes3rd_by_party = [];
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
                votes1st_by_party[i] = 0;
                votes2nd_by_party[i] = 0;
                votes3rd_by_party[i] = 0;

                // set up 
                distByParty[i] = {};
                distByParty[i]["party_code"] = check by_party[i].party_code;
                distByParty[i]["party_name"] = (by_party[i].party_name is string) ? check by_party[i].party_name : "Party " + <string>distByParty[i]["party_code"]; // no party_name in test data
                distByParty[i]["candidate"] = (by_party[i].candidate is string) ? check by_party[i].candidate : "Candidate " + <string>distByParty[i]["party_code"]; // no candidate name in test data
            } else if pdCount > 1 && distByParty[i].party_code != by_party[i].party_code {
                // all parties are supposed to be in the same order in each PD
                panic error("Unexpected problem: party codes are not in the same order across all PDs of district " +
                            pdResult.ed_name.toString());
            }
            // add up votes and do %ge later as totals are not yet known
            votes_by_party[i] = votes_by_party[i] + <int>by_party[i].vote_count;  
            if resultType == "PRESIDENTIAL-PREFS" { // add up pref votes too then
                votes1st_by_party[i] += <int>by_party[i].votes1st;  
                votes2nd_by_party[i] += <int>by_party[i].votes2nd;  
                votes3rd_by_party[i] += <int>by_party[i].votes3rd;  
            }
        }

        distSummary.valid += <int>pdResult.summary.valid;
        distSummary.rejected += <int>pdResult.summary.rejected;
        distSummary.polled += <int>pdResult.summary.polled;
        // don't add up electors from postal PDs as those are already in the district elsewhere
        if !pdCode.endsWith("P") {
            distSummary.electors += <int>pdResult.summary.electors;
        }

        pdCount += 1;
    }

    // put the vote total & percentages in the result json
    foreach int i in 0 ... votes_by_party.length()-1 {
        distByParty[i]["votes"] = votes_by_party[i];
        if resultType == "PRESIDENTIAL-PREFS" { // pref votes too then
            distByParty[i]["votes1st"] = votes1st_by_party[i];
            distByParty[i]["votes2nd"] = votes2nd_by_party[i];
            distByParty[i]["votes3rd"] = votes3rd_by_party[i];
        }
        distByParty[i]["vote_percentage"] = (distSummary.valid == 0) ? "0.00" : io:sprintf ("%.2f", votes_by_party[i]*100.0/distSummary.valid);
    }

    // set the percentages in the summary
    distSummary.percent_valid = (distSummary.polled == 0) ? "0.00" : io:sprintf("%.2f", distSummary.valid*100.0/distSummary.polled);
    distSummary.percent_rejected = (distSummary.polled == 0) ? "0.00" : io:sprintf("%.2f", distSummary.rejected*100.0/distSummary.polled);
    distSummary.percent_polled = (distSummary.electors == 0) ? "0.00" : io:sprintf("%.2f", distSummary.polled*100.0/distSummary.electors);

    return {
        'type: resultType, 
        timestamp: check time:format(time:currentTime(), "yyyy-MM-dd'T'HH:mm:ss.SSSZ"),
        level: "ELECTORAL-DISTRICT", 
        ed_code: ed_code,
        ed_name: ed_name,
        by_party: distByParty,
        summary: check json.constructFrom(distSummary)
    };
}

function createNationalResult (string resultType, map<map<json>>[] results, map<json>[]resultsByPD) returns map<json> | error {
    map<json>[] natByParty = []; // array of json value each for a single party results for the district
    Summary natSummary = { // aggregate results (not by_party)
        valid: 0, 
        rejected: 0, 
        polled: 0, 
        electors: 0,
        percent_valid: "",
        percent_rejected: "",
        percent_polled: ""
    };
    int[] votes_by_party = [];
    int[] votes1st_by_party = [];
    int[] votes2nd_by_party = [];
    int[] votes3rd_by_party = [];    int pdCount = 0;
    foreach map<json> pdResult in resultsByPD {
        json[] by_party = <json[]> pdResult.by_party;
        int nparties = by_party.length();
        foreach int i in 0 ..< nparties {
            if pdCount == 0 { // at the first PD of the country
                // init vote count to zero for i-th party at first PD in district
                votes_by_party[i] = 0;
                votes1st_by_party[i] = 0;
                votes2nd_by_party[i] = 0;
                votes3rd_by_party[i] = 0;

                // set up 
                natByParty[i] = {};
                natByParty[i]["party_code"] = check by_party[i].party_code;
                natByParty[i]["party_name"] = (by_party[i].party_name is string) ? check by_party[i].party_name : "Party " + <string>by_party[i].party_code; // no party_name in test data
                natByParty[i]["candidate"] = (by_party[i].candidate is string) ? check by_party[i].candidate : "Candidate " + <string>by_party[i].party_code; // no candidate name in test data
            } else if pdCount > 1 && natByParty[i].party_code != by_party[i].party_code {
                // all parties are supposed to be in the same order in each PD
                panic error("Unexpected problem: party codes are not in the same order across all PDs of the country " +
                            pdResult.ed_name.toString() + "/" + pdResult.pd_name.toString());
            }
            // add up votes and do %ge later as totals are not yet known
            votes_by_party[i] = votes_by_party[i] + <int>by_party[i].vote_count;            
            if resultType == "PRESIDENTIAL-PREFS" { // add up pref votes too then
                votes1st_by_party[i] += <int>by_party[i].votes1st;  
                votes2nd_by_party[i] += <int>by_party[i].votes2nd;  
                votes3rd_by_party[i] += <int>by_party[i].votes3rd;  
            }
        }

        natSummary.valid += <int>pdResult.summary.valid;
        natSummary.rejected += <int>pdResult.summary.rejected;
        natSummary.polled += <int>pdResult.summary.polled;
        // don't add up electors from postal PDs as those are already in the district elsewhere
        string pdCode = <string>pdResult.pd_code;
        if !pdCode.endsWith("P") {
            natSummary.electors += <int>pdResult.summary.electors;
        }
        pdCount += 1;
    }

    // put the vote total & percentages in the result json
    foreach int i in 0 ..< votes_by_party.length() {
        natByParty[i]["votes"] = votes_by_party[i];
        if resultType == "PRESIDENTIAL-PREFS" { // pref votes too then
            natByParty[i]["votes1st"] = votes1st_by_party[i];
            natByParty[i]["votes2nd"] = votes2nd_by_party[i];
            natByParty[i]["votes3rd"] = votes3rd_by_party[i];
        }
        natByParty[i]["vote_percentage"] = (natSummary.valid == 0) ? "0.00" : io:sprintf ("%.2f", votes_by_party[i]*100.0/natSummary.valid);
    }

    // set the percentages in the summary
    natSummary.percent_valid = (natSummary.polled == 0) ? "0.00" : io:sprintf("%.2f", natSummary.valid*100.0/natSummary.polled);
    natSummary.percent_rejected = (natSummary.polled == 0) ? "0.00" : io:sprintf("%.2f", natSummary.rejected*100.0/natSummary.polled);
    natSummary.percent_polled = (natSummary.electors == 0) ? "0.00" : io:sprintf("%.2f", natSummary.polled*100.0/natSummary.electors);

    return {
        'type: resultType, 
        timestamp: check time:format(time:currentTime(), "yyyy-MM-dd'T'HH:mm:ss.SSSZ"),
        level: "NATIONAL-FINAL", 
        by_party: natByParty,
        summary: check json.constructFrom(natSummary)
    };
}

function sendResult (http:Client hc, string electionCode, string resType, string resCode, map<json> result) returns error? {
    // reset time stamp of the result to now
    result["timestamp"] = check time:format(time:currentTime(), "yyyy-MM-dd'T'HH:mm:ss.SSSZ");
    http:Response hr;

    // sent alert
    string params = "/?level=" + <string>result.level;
    if result.ed_name is string {
        params += "&ed_name=" + check encoding:encodeUriComponent(<string>result.ed_name, "UTF-8");
        if result.pd_name is string {
            params += "&pd_name=" + check encoding:encodeUriComponent(<string>result.pd_name, "UTF-8");
        }
    }
    hr = check hc->post ("/result/notification/" + electionCode + "/" + resType + "/" + resCode + params, <json>{});
    if hr.statusCode != http:STATUS_ACCEPTED {
        io:println("Error while posting result notification to: /result/notification/" + electionCode + "/" + resType + "/" + resCode + params);
        io:println("\tstatus=", hr.statusCode, ", contentType=", hr.getContentType(), " payload=", hr.getTextPayload());
        return error ("Unable to post notification for " + resCode);
    }

    hr = check hc->post ("/result/data/" + electionCode + "/" + resType + "/" + resCode, result);
    if hr.statusCode != http:STATUS_ACCEPTED {
        io:println("Error while posting result to: /result/data/" + electionCode + "/" + resType + "/" + resCode);
        io:println("\tstatus=", hr.statusCode, ", contentType=", hr.getContentType(), " payload=", hr.getTextPayload());
        return error ("Unable to post result for " + resCode);
    }
}
