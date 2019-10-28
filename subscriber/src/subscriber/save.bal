import ballerina/io;
import ballerina/log;
import ballerina/xmlutils;
import ballerina/stringutils as su;

const PRESIDENTIAL_RESULT = "PRESIDENTIAL-FIRST";
const LEVEL_PD = "POLLING-DIVISION";
const LEVEL_ED = "ELECTORAL-DISTRICT";
const LEVEL_NI = "NATIONAL-INCREMENTAL";
const LEVEL_NF = "NATIONAL-FINAL";


function saveResult(map<json> result) {
    string fileBase = getFileNameBase(result);
    if wantJson {
        string jsonfile = fileBase + ".json";
        error? e = writeJson(jsonfile, result);
        if e is error {
            log:printError("Unable to write result #" + result.sequence_number.toString() + " " + jsonfile + e.reason());
        } else {
            log:printInfo("New result written: " + jsonfile);
        }
    }
    if wantXml {
        string xmlfile = fileBase + ".xml";
        // put the result json object into a wrapper object to get a parent element
        // NOTE: this code must match the logic in the distributor website code as 
        // both add this object wrapper with the property named "result". Bit
        // dangerous as someone can forget to change both together - hence this comment!
        json j = { result: result };

        error? e = trap writeXml(xmlfile, checkpanic xmlutils:fromJSON(j));
        if e is error {
            log:printError("Unable to write result #" + result.sequence_number.toString() + " " + xmlfile + e.reason());
        } else {
            log:printInfo("New result written: " + xmlfile);
        }
    }
}

# Return the file name to store this result using the format:
# 	NNN-{TypeCode}-{LevelCode}[--{EDCode[--{PDCode}]].{ext}
# where
# 	NNN			Sequence number of the result with 0s if needed (001, 002, ..).
#	{TypeCode}	Result type- first preference or 2nd/3rd preference. “PE1” for
#				first preference count and “PE2” for 2nd/3rd preference counts.
#	{LevelCode}	Result level: PD for polling division, ED for electoral district,
#				NI for national incremental result and NF for national final result.
#	{EDName}	Name of the electoral district in English.
#	{PDName}	Name of the polling division in English.
#	{ext}		Either “json” or “xml” depending on the format of the file.
# 
# + return - returns the base name for the file 
function getFileNameBase(map<json> result) returns string {
    // start with sequence # and type code
    string name = result.sequence_number.toString() + "-" +
        (result.'type.toString() == PRESIDENTIAL_RESULT ? "PE1" : "PE2") + "-";

    string resultLevel = result.level.toString();

    // add level code
    match resultLevel {
        LEVEL_PD => { name = name + "PD"; }
        LEVEL_ED => { name = name + "ED"; }
        LEVEL_NI => { name = name + "NI"; }
        LEVEL_NF => { name = name + "NF"; }
    }
    // add electoral district / polling division names if needed with spaces replaced with _
    if resultLevel == LEVEL_ED || resultLevel == LEVEL_PD {
        name = name + "-" + su:replaceAll(result.ed_name.toString()," ", "_");
        if resultLevel == LEVEL_PD {
            name = name + "-" + su:replaceAll(result.pd_name.toString()," ", "_");
        }
    }
    return name;
}

function writeJson(string path, json content) returns error? {
    return writeContent(path, 
                        function(io:WritableCharacterChannel wch) returns error? {
                            return wch.writeJson(content);
                        });
}

function writeXml(string path, xml content) returns error? {
    return writeContent(path, function(io:WritableCharacterChannel wch) returns error? {
        return wch.writeXml(content);
    });
}

function writeContent(string path, function(io:WritableCharacterChannel wch) returns error? writeFunc) returns error? {
    io:WritableByteChannel wbc = check io:openWritableFile(path);
    io:WritableCharacterChannel wch = new(wbc, "UTF8");
    check writeFunc(wch);
    check wch.close();
    check wbc.close(); // should use return here but there's a taint detection bug in the compiler that
                       // apparently considers this error as tainted. huh??
}
