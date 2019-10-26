import ballerina/log;
import ballerina/config;
import ballerinax/java.jdbc;

const string CREATE_RESULTS_TABLE = "CREATE TABLE IF NOT EXISTS results (" +
                                    "    sequenceNo INT NOT NULL AUTO_INCREMENT," + 
                                    "    code VARCHAR(100) NOT NULL," +
                                    "    type VARCHAR(100) NOT NULL," +
                                    "    jsonResult VARCHAR(10000) NOT NULL," +
                                    "    mediaType VARCHAR(50) DEFAULT NULL," +
                                    "    image BLOB DEFAULT NULL," + 
                                    "    PRIMARY KEY (sequenceNo))";
const INSERT_RESULT = "INSERT INTO results (code, jsonResult, type) VALUES (?, ?, ?)";
const INSERT_RESULT_IMAGE = "UPDATE results SET mediaType = ?, image = ? WHERE code = ?";
const SELECT_RESULTS_DATA = "SELECT code, jsonResult, type FROM results";
const SELECT_RESULT = "SELECT jsonResult, type FROM results where sequenceNo=?";

jdbc:Client dbClient = new ({
    url: config:getAsString("eclk.hub.db.url"),
    username: config:getAsString("eclk.hub.db.username"),
    password: config:getAsString("eclk.hub.db.password"),
    dbOptions: {
        useSSL: config:getAsString("eclk.hub.db.useSsl")
    }    
});

# Create database and set up at module init time. Panic if there's any issue.
function __init() {
    _ = checkpanic dbClient->update(CREATE_RESULTS_TABLE);
}

# Save an incoming result to make sure we don't lose it after getting it
# + return - error if unable to insert to the database
function saveResult(string resultCode, json jsonResult, string resultType) returns error? {
    var r = dbClient->update(INSERT_RESULT, resultCode, jsonResult.toJsonString(), resultType);
    if r is jdbc:DatabaseError {
        log:printError("Unable to save result in database: " + r.toString());
        return r;
    }
}

# Save an image associated with a result
# + return - error if unable to insert image for the given resultCode
function saveImage(string resultCode, string mediaType, byte[] imageData) returns error? {
    // save in DB
    var r = dbClient->update(INSERT_RESULT_IMAGE, mediaType, imageData, resultCode);
    if r is jdbc:DatabaseError {
        log:printError("Unable to save image in database: " + r.toString());
        return r;
    }
}
