import ballerina/config;
import ballerina/io;
import ballerina/log;
import ballerinax/java.jdbc;

# This variable will contain all the results received. If the server crashes it will 
# initialize this from the database. As new results come in, we'll put it here as we
# put the result into the db as well. This approach will make sure that the index
# number of a result in the cache will match the auto generated sequenceNo column
# in the database.
# Note that this design only allows one container to be active at once. K8s scale params
# must be done that way! (That's also a limitation of the websub hub right now; see
# https://github.com/ECLK/Results-Dist/issues/35.)
Result[] resultsCache = [];

// TODO: set in `init`.
final ElectionType electionType = ELECTION_TYPE_PARLIAMENTARY;

function(map<json>) cleanupJsonFunc = cleanupPresidentialJson;
function(map<json>) returns CumulativeResult? addToCumulativeFunc = addToPresidentialCumulative;
function(CumulativeResult, string, string, string, Result) returns error? sendIncrementalResultFunc = 
                                                                                sendPresidentialIncrementalResult;
function(json[], string) returns json[] byPartySortFunction = sortPresidentialByPartyResults;

const string CREATE_RESULTS_TABLE = "CREATE TABLE IF NOT EXISTS results (" +
                                    "    sequenceNo INT NOT NULL AUTO_INCREMENT," + 
                                    "    election VARCHAR(50) NOT NULL," +
                                    "    code VARCHAR(100) NOT NULL," +
                                    "    type VARCHAR(100) NOT NULL," +
                                    "    jsonResult LONGTEXT NOT NULL," +
                                    "    imageMediaType VARCHAR(50) DEFAULT NULL," +
                                    "    imageData MEDIUMBLOB DEFAULT NULL," + 
                                    "    PRIMARY KEY (sequenceNo))";
const INSERT_RESULT = "INSERT INTO results (election, code, jsonResult, type) VALUES (?, ?, ?, ?)";
const UPDATE_RESULT_JSON = "UPDATE results SET jsonResult = ? WHERE sequenceNo = ?";
const string UPDATE_RESULT_IMAGE = "UPDATE results SET imageMediaType = ?, imageData = ? WHERE election = ? " + 
                                "AND type = ? AND code = ?";
const SELECT_RESULTS_DATA = "SELECT sequenceNo, election, code, type, jsonResult, imageMediaType, imageData FROM results";
const DROP_RESULTS_TABLE = "DROP TABLE results";

const string CREATE_RECIPIENT_TABLE = "CREATE TABLE IF NOT EXISTS smsRecipients (" +
                                    "    username VARCHAR(100) NOT NULL," +
                                    "    mobileNo VARCHAR(50) NOT NULL," +
                                    "    PRIMARY KEY (username))";
const INSERT_RECIPIENT = "INSERT INTO smsRecipients (username, mobileNo) VALUES (?, ?)";
const DELETE_RECIPIENT = "DELETE FROM smsRecipients WHERE username = ?";
const SELECT_RECIPIENT_DATA = "SELECT * FROM smsRecipients";
const DROP_RECIPIENT_TABLE = "DROP TABLE smsRecipients";
const DELETE_RECIPIENT_TABLE = "DELETE FROM smsRecipients";

jdbc:Client dbClient = new ({
    url: config:getAsString("eclk.distributor.db.url"),
    username: config:getAsString("eclk.distributor.db.username"),
    password: config:getAsString("eclk.distributor.db.password"),
    dbOptions: {
        useSSL: config:getAsString("eclk.distributor.db.useSsl")
    }    
});

type DataResult record {|
    int sequenceNo;
    string election;
    string code;
    string 'type;
    string jsonResult;
    string? imageMediaType;
    byte[]? imageData;
|};

type CumulativeResult record {
    int nadded;
};

type CumulativeVotesResult record {
    *CumulativeResult;
    SummaryResult summary;
};

type PresidentialCumulativeVotesResult record {|
    *CumulativeVotesResult;
    PresidentialPartyResult[] by_party;
|};

type ParliamentaryCumulativeVotesResult record {|
    *CumulativeVotesResult;
    ParliamentaryPartyResult[] by_party;
|};

type ParliamentaryCumulativeSeatsResult record {|
    *CumulativeResult;
    ParliamentaryPartyResult[] by_party;
|};

SummaryResult emptySummaryResult = { 
    valid: 0, 
    rejected: 0, 
    polled: 0, 
    electors: 0,
    percent_valid: "",
    percent_rejected: "",
    percent_polled: ""
};

////////////////////// Presidential Cumulatives ////////////////////// 
PresidentialCumulativeVotesResult emptyPresidentialCumResult = { 
    nadded: 0,
    by_party: [], 
    summary: emptySummaryResult
};
PresidentialCumulativeVotesResult presidentialCumulativeVotesRes = emptyPresidentialCumResult;
PresidentialCumulativeVotesResult presidentialPrefsCumulativeVotesRes = emptyPresidentialCumResult;

////////////////////// Parliamentary Cumulatives ////////////////////// 
ParliamentaryCumulativeVotesResult emptyParliamentaryCumVotesResult = { 
    nadded: 0,
    by_party: [], 
    summary: emptySummaryResult
}; 

ParliamentaryCumulativeSeatsResult emptyParliamentaryCumSeatsResult = { 
    nadded: 0,
    by_party: []
}; 

map<ParliamentaryCumulativeVotesResult> parliamentaryDistrictwiseCumVotesRes = initializeDistrictwiseCumulativeVotesMap();

ParliamentaryCumulativeSeatsResult parliamentaryCumSeatsRes = emptyParliamentaryCumSeatsResult;

# Set the election type and relevant modes.
# Create database and set up at module init time and load any data in there to
# memory for the website to show. Panic if there's any issue.
function __init() {
    if electionType == ELECTION_TYPE_PARLIAMENTARY {
        cleanupJsonFunc = cleanupParliamentaryJson;
        addToCumulativeFunc = addToParliamentaryCumulative;
        byPartySortFunction = sortParliamentaryByPartyResults;
        sendIncrementalResultFunc = sendParliamentaryIncrementalResult;
        parliamentaryDistrictwiseCumVotesRes = initializeDistrictwiseCumulativeVotesMap();
        parliamentaryCumSeatsRes = emptyParliamentaryCumSeatsResult;
    } else {
        presidentialCumulativeVotesRes = emptyPresidentialCumResult.clone();
        presidentialPrefsCumulativeVotesRes = emptyPresidentialCumResult.clone();
    }

    // create tables
    _ = checkpanic dbClient->update(CREATE_RESULTS_TABLE);
    _ = checkpanic dbClient->update(CREATE_RECIPIENT_TABLE);

    // load any results in there to our cache - the order will match the autoincrement and will be the sequence #
    table<record {}> res = checkpanic dbClient->select(SELECT_RESULTS_DATA, DataResult);
    table<DataResult> ret = <table<DataResult>> res;
    int count = 0;
    resultsCache = [];

    while (ret.hasNext()) {
        DataResult dr = <DataResult> ret.getNext();
        count += 1;

        // read json string and convert to json
        io:StringReader sr = new(dr.jsonResult, encoding = "UTF-8");
        map<json> jm =  <map<json>> sr.readJson();

        // put results in the cache
        resultsCache.push(<Result> {
            sequenceNo: dr.sequenceNo,
            election: dr.election,
            code: dr.code,
            'type: dr.'type,
            jsonResult: jm,
            imageMediaType: dr.imageMediaType,
            imageData: dr.imageData
        });

        _ = addToCumulativeFunc(<@untainted> jm);
    }
    if (count > 0) {
        log:printInfo("Loaded " + count.toString() + " previous results from database");
    }

    // load sms recipients to in-memory map
    table<record {}> retrievedRes = checkpanic dbClient->select(SELECT_RECIPIENT_DATA, Recipient);
    table<Recipient> retrievedNos = <table<Recipient>> retrievedRes;
    count = 0;
    while (retrievedNos.hasNext()) {
        Recipient recipient = <Recipient> retrievedNos.getNext();
        mobileSubscribers[recipient.username] = <@untainted> recipient.mobile;
        count += 1;
    }
    if (count > 0) {
        log:printInfo("Loaded " + count.toString() + " previous SMS recipient(s) from database");
    }
    // validate GovSMS authentication
    var account = smsClient->sendSms(sourceDepartment, "Test authentication", "");
    if account is error {
        log:printError("SMS notification is disabled due to '" + <string> account.detail()?.message +
                       "'. Please provide valid 'eclk.govsms.username'/'password'/'source'(department title)");
    } else {
        validSmsClient = true;
        log:printInfo("SMS notification is enabled");
    }
}

# Save an incoming result to make sure we don't lose it after getting it
# + return - error if unable to insert to the database
function saveResult(Result result) returns CumulativeResult|error? {
    // save it without the proper json first so we can put the sequence number into that
    var r = dbClient->update(INSERT_RESULT, result.election, result.code, "", result.'type);
    if r is jdbc:UpdateResult {
        int sequenceNo = check trap <int>r.generatedKeys["GENERATED_KEY"];
        result.sequenceNo = sequenceNo;

        // put sequence # to json that's going to get distributed as a 3 digit #
        result.jsonResult["sequence_number"] = io:sprintf("%04d", sequenceNo);

        // now put the json string into the db against the record we just created
        _ = check dbClient->update(UPDATE_RESULT_JSON, result.jsonResult.toJsonString(), result.sequenceNo);
    } else {
        log:printError("Unable to save result in database: " + r.toString());
        return r;
    }

    // update in memory cache of all results
    resultsCache.push(result);
    
    return addToCumulativeFunc(result.jsonResult);
}

# Save an image associated with a result
# + return - error if unable to insert image for the given resultCode
function saveImage(string electionCode, string resultType, string resultCode, string mediaType, 
                   byte[] imageData) returns Result|error? {
    // save in DB
    var ret = dbClient->update(UPDATE_RESULT_IMAGE, mediaType, imageData, electionCode, resultType, resultCode);
    if ret is jdbc:DatabaseError {
        log:printError("Unable to save image in database: " + ret.toString());
        return ret;
    }

    // update the in-memory cache of results with this image
    boolean updated = false;
    Result? res = ();
    foreach Result r in resultsCache {
        if r.election == electionCode && r.'type == resultType && r.code == resultCode {
            r.imageMediaType = mediaType;
            r.imageData = imageData;
            res = r;
            updated = true;
            break;
        }
    }
    if !updated {
        // shouldn't happen .. but don't want to panic and die either
        log:printWarn("Updating result cache for new image for election='" + electionCode + 
                      "', type='" + resultType + "', code='" + resultCode + "' failed as result was missing. WEIRD!");
    }

    return res;
}

# Clean everything from the DB and the in-memory cache
# + return - error if something goes wrong
function resetResults() returns error? {
    _ = check dbClient->update(DROP_RESULTS_TABLE);
    _ = check dbClient->update(DROP_RECIPIENT_TABLE);
    __init();
}

# Add a polling division level result to the cumulative total.
# 
# + return - the module level record with accumulated results if this result contributed to a cumulative result, 
#               `()` if not
function addToPresidentialCumulative(map<json> jm) returns PresidentialCumulativeVotesResult? {
    if jm.level != "POLLING-DIVISION" {
        return;
    }

    boolean firstRound = jm.'type == PRESIDENTIAL_RESULT;
    json[] pr = <json[]> checkpanic jm.by_party;

    PresidentialCumulativeVotesResult accum = emptyPresidentialCumResult; // avoiding optional
    if firstRound {
        accum = presidentialCumulativeVotesRes;
    } else {
        if presidentialPrefsCumulativeVotesRes.summary.electors == 0 {
            // just starting round 2 - copy over summary data from the previous cumulative
            // total as that's where we start for round 2
            presidentialPrefsCumulativeVotesRes.summary = presidentialCumulativeVotesRes.summary;
        }
        accum = presidentialPrefsCumulativeVotesRes;
    }

    // add the summary counts in round 1. N/A when adding up 2nd/3rd prefs
    if firstRound {
        accum.summary.valid += <int>jm.summary.valid;
        accum.summary.rejected += <int>jm.summary.rejected;
        accum.summary.polled += <int>jm.summary.polled;
        // don't add up electors from postal PDs as those are already in the district elsewhere
        string pdCode = <string>jm.pd_code; // check 
        accum.summary.electors += <int>jm.summary.electors;
        accum.summary.percent_valid = (accum.summary.polled == 0) ? "0.00" : io:sprintf("%.2f", accum.summary.valid*100.0/accum.summary.polled);
        accum.summary.percent_rejected = (accum.summary.polled == 0) ? "0.00" : io:sprintf("%.2f", accum.summary.rejected*100.0/accum.summary.polled);
        accum.summary.percent_polled = (accum.summary.electors == 0) ? "0.00" : io:sprintf("%.2f", accum.summary.polled*100.0/accum.summary.electors);
    }

    // if first PD being added to cumulative then just copy the party results over
    if accum.nadded == 0 {
        pr.forEach (x => accum.by_party.push(checkpanic PresidentialPartyResult.constructFrom(x)));
    } else {
        // record by party votes from this result (copying name etc. is silly after first hit)
        foreach int i in 0 ..< pr.length() {
            accum.by_party[i].party_code = <string>pr[i].party_code;
            accum.by_party[i].party_name = <string>pr[i].party_name;
            accum.by_party[i].candidate = <string>pr[i].candidate;
            accum.by_party[i].vote_count += <int>pr[i].vote_count;
            if !firstRound {
                accum.by_party[i]["votes1st"] = (accum.by_party[i]["votes1st"] ?: 0) + <int>pr[i].votes1st;
                accum.by_party[i]["votes2nd"] = (accum.by_party[i]["votes2nd"] ?: 0) + <int>pr[i].votes2nd;
                accum.by_party[i]["votes3rd"] = (accum.by_party[i]["votes3rd"] ?: 0) + <int>pr[i].votes3rd;
            }
            accum.by_party[i].vote_percentage = (accum.summary.valid == 0) ? "0.00" : io:sprintf ("%.2f", ((accum.by_party[i].vote_count*100.0)/accum.summary.valid));
        }
    }
    accum.nadded += 1;
    if firstRound {
        presidentialCumulativeVotesRes = accum;
    } else {
        presidentialPrefsCumulativeVotesRes = accum;
    }
    return accum;
}

# Add a polling division level result to the cumulative parliamentary total.
# 
# + return - the record with accumulated results if this result contributed to a cumulative result, `()` if not
function addToParliamentaryCumulative(map<json> jm) 
        returns ParliamentaryCumulativeVotesResult|ParliamentaryCumulativeSeatsResult? {
    match jm.level {
        "POLLING-DIVISION" => {
            return addToParliamentaryCumulativeVotes(jm);
        }
        "ELECTORAL-DISTRICT" => {
            return addToParliamentaryCumulativeSeats(jm);
        }
    }
}

function addToParliamentaryCumulativeVotes(map<json> jm) returns ParliamentaryCumulativeVotesResult? {
    if jm.'type != RP_V {
        return;
    }

    string edCode = <string> jm.ed_code;

    var accum = <ParliamentaryCumulativeVotesResult> parliamentaryDistrictwiseCumVotesRes[edCode];

    json[] pr = <json[]> checkpanic jm.by_party;

    SummaryResult summary = accum.summary;
    summary.valid += <int>jm.summary.valid;
    summary.rejected += <int>jm.summary.rejected;
    summary.polled += <int>jm.summary.polled;
    // // don't add up electors from postal PDs as those are already in the district elsewhere
    // string pdCode = <string>jm.pd_code; // check 
    summary.electors += <int>jm.summary.electors;
    summary.percent_valid = (accum.summary.polled == 0) ? "0.00" : io:sprintf("%.2f", accum.summary.valid*100.0/accum.summary.polled);
    summary.percent_rejected = (accum.summary.polled == 0) ? "0.00" : io:sprintf("%.2f", accum.summary.rejected*100.0/accum.summary.polled);
    summary.percent_polled = (accum.summary.electors == 0) ? "0.00" : io:sprintf("%.2f", accum.summary.polled*100.0/accum.summary.electors);

    if accum.nadded == 0 {
        pr.forEach(x => accum.by_party.push(checkpanic ParliamentaryPartyResult.constructFrom(x)));
    } else {
        foreach int i in 0 ..< pr.length() {
            json currentPartyRes = pr[i];
            ParliamentaryPartyResult? res = getMatchingByPartyRecord(accum.by_party, <string>currentPartyRes.party_code);

            if res is () {
                accum.by_party.push(checkpanic ParliamentaryPartyResult.constructFrom(currentPartyRes));
            } else {
                int accumVoteCount = <int> accum.by_party[i]?.vote_count + <int>pr[i].vote_count;
                accum.by_party[i].vote_count = accumVoteCount;
                accum.by_party[i].vote_percentage = (accum.summary.valid == 0) ? "0.00" : io:sprintf ("%.2f", ((accumVoteCount*1.0)/accum.summary.valid));
            }
        }
    }
    accum.nadded += 1;
    return accum;
}

function getMatchingByPartyRecord(ParliamentaryPartyResult[] partyResultArray, string partyCode) 
        returns ParliamentaryPartyResult? {
    foreach ParliamentaryPartyResult res in partyResultArray {
        if res.party_code == partyCode {
            return res;
        }
    }
}

function addToParliamentaryCumulativeSeats(map<json> jm) returns ParliamentaryCumulativeSeatsResult? {
    if jm.'type != RE_S {
        return;
    }

    json[] pr = <json[]> checkpanic jm.by_party;

    if parliamentaryCumSeatsRes.nadded == 0 {
        pr.forEach(x => parliamentaryCumSeatsRes.by_party.push(checkpanic ParliamentaryPartyResult.constructFrom(x)));
    } else {
        foreach int i in 0 ..< pr.length() {
            json currentPartyRes = pr[i];
            ParliamentaryPartyResult? res = getMatchingByPartyRecord(parliamentaryCumSeatsRes.by_party, 
                                                                     <string>currentPartyRes.party_code);

            if res is () {
                parliamentaryCumSeatsRes.by_party.push(checkpanic ParliamentaryPartyResult.constructFrom(currentPartyRes));
            } else {
                res.seat_count = <int> res?.seat_count + <int> currentPartyRes.seat_count;
            }
        }
    }
    parliamentaryCumSeatsRes.nadded += 1;
    return parliamentaryCumSeatsRes;
}

function initializeDistrictwiseCumulativeVotesMap() returns map<ParliamentaryCumulativeVotesResult> {
    map<ParliamentaryCumulativeVotesResult> cumulativeResultMap = {};

    foreach int index in 1 ... 9 {
        cumulativeResultMap[string `0${index.toString()}`] = emptyParliamentaryCumVotesResult.clone();
    }

    foreach int index in 10 ... 22 {
        cumulativeResultMap[index.toString()] = emptyParliamentaryCumVotesResult.clone();
    }

    return cumulativeResultMap;
}
