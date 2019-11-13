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

const string CREATE_RESULTS_TABLE = "CREATE TABLE IF NOT EXISTS results (" +
                                    "    sequenceNo INT NOT NULL AUTO_INCREMENT," + 
                                    "    election VARCHAR(50) NOT NULL," +
                                    "    code VARCHAR(100) NOT NULL," +
                                    "    type VARCHAR(100) NOT NULL," +
                                    "    jsonResult VARCHAR(60000) NOT NULL," +
                                    "    imageMediaType VARCHAR(50) DEFAULT NULL," +
                                    "    imageData BLOB DEFAULT NULL," + 
                                    "    PRIMARY KEY (sequenceNo))";
const INSERT_RESULT = "INSERT INTO results (election, code, jsonResult, type) VALUES (?, ?, ?, ?)";
const UPDATE_RESULT_JSON = "UPDATE results SET jsonResult = ? WHERE sequenceNo = ?";
const UPDATE_RESULT_IMAGE = "UPDATE results SET imageMediaType = ?, imageData = ? WHERE election = ? AND code = ?";
const SELECT_RESULTS_DATA = "SELECT sequenceNo, election, code, type, jsonResult, imageMediaType, imageData FROM results";
const DROP_RESULTS_TABLE = "DROP TABLE results";

const string CREATE_CALLBACKS_TABLE = "CREATE TABLE IF NOT EXISTS callbacks (" +
                                    "    username VARCHAR(100) NOT NULL," +
                                    "    topic VARCHAR(100) NOT NULL," +
                                    "    callback VARCHAR(200) NOT NULL," +
                                    "    PRIMARY KEY (username, topic))";
const INSERT_CALLBACK = "INSERT INTO callbacks (username, topic, callback) VALUES (?, ?, ?)";
const UPDATE_CALLBACK = "UPDATE callbacks SET callback = ? WHERE username = ? AND topic = ?";
const SELECT_CALLBACKS = "SELECT * FROM callbacks";
const DROP_CALLBACKS_TABLE = "DROP TABLE callbacks";

const string CREATE_RECIPIENT_TABLE = "CREATE TABLE IF NOT EXISTS smsRecipients (" +
                                    "    username VARCHAR(100) NOT NULL," +
                                    "    mobileNo VARCHAR(50) NOT NULL," +
                                    "    PRIMARY KEY (username))";
const INSERT_RECIPIENT = "INSERT INTO smsRecipients (username, mobileNo) VALUES (?, ?)";
const DELETE_RECIPIENT = "DELETE FROM smsRecipients WHERE username = ? AND mobileNo = ?";
const SELECT_RECIPIENT_DATA = "SELECT * FROM smsRecipients";
const DROP_RECIPIENT_TABLE = "DROP TABLE smsRecipients";

jdbc:Client dbClient = new ({
    url: config:getAsString("eclk.hub.db.url"),
    username: config:getAsString("eclk.hub.db.username"),
    password: config:getAsString("eclk.hub.db.password"),
    dbOptions: {
        useSSL: config:getAsString("eclk.hub.db.useSsl")
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

type UserCallback record {|
    string username;
    string topic;
    string callback;
|};

type CumulativeResult record {|
    int nadded;
    PartyResult[] by_party;
    SummaryResult summary;
|};

CumulativeResult emptyCumResult = { 
    nadded: 0,
    by_party: [], 
    summary: { 
        valid: 0, 
        rejected: 0, 
        polled: 0, 
        electors: 0,
        percent_valid: "",
        percent_rejected: "",
        percent_polled: ""
    }
};
CumulativeResult cumulativeRes = emptyCumResult;
CumulativeResult prefsCumulativeRes = emptyCumResult;

# Create database and set up at module init time and load any data in there to
# memory for the website to show. Panic if there's any issue.
function __init() {
    // create tables
    _ = checkpanic dbClient->update(CREATE_RESULTS_TABLE);
    _ = checkpanic dbClient->update(CREATE_CALLBACKS_TABLE);
    _ = checkpanic dbClient->update(CREATE_RECIPIENT_TABLE);

    // load any results in there to our cache - the order will match the autoincrement and will be the sequence #
    table<DataResult> ret = checkpanic dbClient->select(SELECT_RESULTS_DATA, DataResult);
    int count = 0;
    resultsCache = [];
    cumulativeRes = emptyCumResult.clone();
    prefsCumulativeRes = emptyCumResult.clone();
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

        // add up cumulative result from all the PD results to get current cumulative total
        if jm.level == "POLLING-DIVISION" {
            addToCumulative (<@untainted> jm);
        }
    }
    if (count > 0) {
        log:printInfo("Loaded " + count.toString() + " previous results from database");
    }

    // load username-callback data for already added subscriptions
    table<UserCallback> callbackRet = checkpanic dbClient->select(SELECT_CALLBACKS, UserCallback);
    count = 0;
    while (callbackRet.hasNext()) {
        UserCallback userCb = <UserCallback> callbackRet.getNext();

        if (userCb.topic == JSON_TOPIC) {
            resultCallbackMap[userCb.username] = <@untainted> userCb.callback;
        } else if (userCb.topic == IMAGE_PDF_TOPIC) {
            imageCallbackMap[userCb.username] = <@untainted> userCb.callback;
        } else {
            // assume AWAIT_RESULTS_TOPIC
            awaitResultsCallbackMap[userCb.username] = <@untainted> userCb.callback;
        }

        count += 1;
    }
    if (count > 0) {
        log:printInfo("Loaded " + count.toString() + " registered callback(s) from database");
    }

    // load sms recipients to in-memory array
    table<Recipient> retrievedNos = checkpanic dbClient->select(SELECT_RECIPIENT_DATA, Recipient);
    count = 0;
    while (retrievedNos.hasNext()) {
        Recipient recipient = <Recipient> retrievedNos.getNext();
        mobileSubscribers[recipient.username] = <@untainted> recipient.mobile;
        count += 1;
    }
    if (count > 0) {
        log:printInfo("Loaded " + count.toString() + " previous SMS recipient(s) from database");
    }
    // validate twilio account
    var account = twilioClient->getAccountDetails();
    if account is error {
        log:printError("SMS notification is disabled due to invalid twilio account details. " +
                        "Please provide valid 'eclk.sms.twilio.accountSid'/'authToken'/'source'(twilio mobile no):" +
                         <string> account.detail()?.message);
    } else {
        validTwilioAccount = true;
        log:printInfo("SMS notification is enabled : twilio.account.status=" + account.status.toString());
    }
}

# Save an incoming result to make sure we don't lose it after getting it
# + return - error if unable to insert to the database
function saveResult(Result result) returns error? {
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

    // add up cumulative result from all the PD results to get current cumulative total
    if result.jsonResult.level == "POLLING-DIVISION" {
        addToCumulative (result.jsonResult);
    }

    // update in memory cache of all results
    resultsCache.push (result);
}

# Save an image associated with a result
# + return - error if unable to insert image for the given resultCode
function saveImage(string electionCode, string resultCode, string mediaType, byte[] imageData) returns Result|error? {
    // save in DB
    var ret = dbClient->update(UPDATE_RESULT_IMAGE, mediaType, imageData, electionCode, resultCode);
    if ret is jdbc:DatabaseError {
        log:printError("Unable to save image in database: " + ret.toString());
        return ret;
    }

    // update the in-memory cache of results with this image
    boolean updated = false;
    Result? res = ();
    foreach Result r in resultsCache {
        if r.election == electionCode && r.code == resultCode {
            r.imageMediaType = mediaType;
            r.imageData = imageData;
            res = r;
            updated = true;
            break;
        }
    }
    if !updated {
        // shouldn't happen .. but don't want to panic and die either
        log:printWarn("Updating result cache for new image for election=" + electionCode + ", code='" + resultCode +
                      "' failed as result was missing. WEIRD!");
    }

    return res;
}

# Save a subscription username-calback combination.
function saveUserCallback(string username, string topic, string callback) {
    var r = dbClient->update(INSERT_CALLBACK, username, topic, callback);
    if r is error {
        log:printError("Unable to save username-callback in database: ", r);
    }
}

# Update a subscription username-calback combination.
function updateUserCallback(string username, string topic, string callback) {
    var r = dbClient->update(UPDATE_CALLBACK, callback, username, topic);
    if r is error {
        log:printError("Unable to update username-callback in database: ", r);
    }
}

# Clean everything from the DB and the in-memory cache
# + return - error if something goes wrong
function resetResults() returns error? {
    _ = check dbClient->update(DROP_RESULTS_TABLE);
    _ = check dbClient->update(DROP_CALLBACKS_TABLE);
    _ = check dbClient->update(DROP_RECIPIENT_TABLE);
    __init();
}

# Add a polling division level result to the cumulative total.
function addToCumulative (map<json> jm) {
    boolean firstRound = jm.'type == PRESIDENTIAL_RESULT;
    json[] pr = <json[]> checkpanic jm.by_party;

    CumulativeResult accum = emptyCumResult; // avoiding optional
    if firstRound {
        accum = cumulativeRes;
    } else {
        if prefsCumulativeRes.summary.electors == 0 {
            // just starting round 2 - copy over summary data from the previous cumulative
            // total as that's where we start for round 2
            io:println("*** loading prefs summary: " + cumulativeRes.summary.toString());
            prefsCumulativeRes.summary = cumulativeRes.summary;
        }
        accum = prefsCumulativeRes;
    }

    // add the summary counts in round 1. N/A when adding up 2nd/3rd prefs
    if firstRound {
        accum.summary.valid += <int>jm.summary.valid;
        accum.summary.rejected += <int>jm.summary.rejected;
        accum.summary.polled += <int>jm.summary.polled;
        // don't add up electors from postal PDs as those are already in the district elsewhere
        string pdCode = <string>jm.pd_code;
        if !pdCode.endsWith("P") {
            accum.summary.electors += <int>jm.summary.electors;
        }
        accum.summary.percent_valid = (accum.summary.polled == 0) ? "0.00" : io:sprintf("%.2f", accum.summary.valid*100.0/accum.summary.polled);
        accum.summary.percent_rejected = (accum.summary.polled == 0) ? "0.00" : io:sprintf("%.2f", accum.summary.rejected*100.0/accum.summary.polled);
        accum.summary.percent_polled = (accum.summary.electors == 0) ? "0.00" : io:sprintf("%.2f", accum.summary.polled*100.0/accum.summary.electors);
    }

    // if first PD being added to cumulative then just copy the party results over
    if accum.nadded == 0 {
        pr.forEach (x => accum.by_party.push(checkpanic PartyResult.constructFrom(x)));
    } else {
        // record by party votes from this result (copying name etc. is silly after first hit)
        foreach int i in 0 ..< pr.length() {
            accum.by_party[i].party_code = <string>pr[i].party_code;
            accum.by_party[i].party_name = <string>pr[i].party_name;
            accum.by_party[i].candidate = <string>pr[i].candidate;
            accum.by_party[i].votes += <int>pr[i].votes;
            if !firstRound {
                accum.by_party[i]["votes1st"] = (accum.by_party[i]["votes1st"] ?: 0) + <int>pr[i].votes1st;
                accum.by_party[i]["votes2nd"] = (accum.by_party[i]["votes2nd"] ?: 0) + <int>pr[i].votes2nd;
                accum.by_party[i]["votes3rd"] = (accum.by_party[i]["votes3rd"] ?: 0) + <int>pr[i].votes3rd;
            }
            accum.by_party[i].percentage = (accum.summary.valid == 0) ? "0.00% : io:sprintf ("%.2f", ((accum.by_party[i].votes*100.0)/accum.summary.valid));
        }
    }
    accum.nadded += 1;
    if firstRound {
        cumulativeRes = accum;
    } else {
        prefsCumulativeRes = accum;
    }
}
