import ballerina/log;
import ballerina/config;
import ballerina/io;
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
                                    "    jsonResult VARCHAR(10000) NOT NULL," +
                                    "    imageMediaType VARCHAR(50) DEFAULT NULL," +
                                    "    imageData BLOB DEFAULT NULL," + 
                                    "    PRIMARY KEY (sequenceNo))";
const INSERT_RESULT = "INSERT INTO results (election, code, jsonResult, type) VALUES (?, ?, ?, ?)";
const UPDATE_RESULT_JSON = "UPDATE results SET jsonResult = ? WHERE sequenceNo = ?";
const UPDATE_RESULT_IMAGE = "UPDATE results SET imageMediaType = ?, imageData = ? WHERE election = ?, code = ?";
const SELECT_RESULTS_DATA = "SELECT sequenceNo, election, code, type, jsonResult, imageMediaType, imageData FROM results";

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

# Create database and set up at module init time and load any data in there to
# memory for the website to show. Panic if there's any issue.
function __init() {
    // create tables for results
    _ = checkpanic dbClient->update(CREATE_RESULTS_TABLE);

    // load any results in there to our cache - the order will match the autoincrement and will be the sequence #
    table<DataResult> ret = checkpanic dbClient->select(SELECT_RESULTS_DATA, DataResult);
    int count = 0;
    while (ret.hasNext()) {
        DataResult dr = <DataResult> ret.getNext();
        count += 1;

        // read json string and convert to json
        io:StringReader sr = new(dr.jsonResult, encoding = "UTF-8");
        map<json> jm =  <map<json>> sr.readJson();

        resultsCache.push(<Result> {
            sequenceNo: dr.sequenceNo,
            election: dr.election,
            code: dr.code,
            'type: dr.'type,
            jsonResult: jm,
            imageMediaType: dr.imageMediaType,
            imageData: dr.imageData
        });
    }
    if (count > 0) {
        log:printInfo("Loaded " + count.toString() + " previous results from database");
    }

    // create table for sms recipients
    createSmsRecipientsTable();
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

    // update in memory cache of all results
    resultsCache.push (result);
}

# Save an image associated with a result
# + return - error if unable to insert image for the given resultCode
function saveImage(string electionCode, string resultCode, string mediaType, byte[] imageData) returns error? {
    // save in DB
    var ret = dbClient->update(UPDATE_RESULT_IMAGE, mediaType, imageData, electionCode, resultCode);
    if ret is jdbc:DatabaseError {
        log:printError("Unable to save image in database: " + ret.toString());
        return ret;
    }

    // update the in-memory cache of results with this image
    boolean updated = false;
    foreach Result r in resultsCache {
        if r.election == electionCode && r.code == resultCode {
            r.imageMediaType = mediaType;
            r.imageData = imageData;
            updated = true;
            break;
        }
    }
    if !updated {
        // shouldn't happen .. but don't want to panic and die either
        log:printWarn("Updating result cache for new image for election=" + electionCode + ", code='" + resultCode +
                      "' failed as result was missing. WEIRD!");
    }
}
