import ballerina/io;
import ballerina/log;
import ballerina/xmlutils;
import ballerina/stringutils as su;

const PRESIDENTIAL_RESULT = "PRESIDENTIAL-FIRST";
const LEVEL_PD = "POLLING-DIVISION";
const LEVEL_ED = "ELECTORAL-DISTRICT";
const LEVEL_NI = "NATIONAL-INCREMENTAL";
const LEVEL_NF = "NATIONAL-FINAL";


function saveResult(map<json> resultAll) {
    string electionCode = resultAll.election_code.toString();
    map<json> result = <map<json>> resultAll?.result;

    string fileBase = getFileNameBase(electionCode, result);
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
    if wantHtml {
        string htmlfile = fileBase + ".html";
        string|error html = generateHtml(electionCode, result);
        if html is error {
            log:printError("Unable to generate HTML for result #"+ result.sequence_number.toString() + " " + html.reason());
        } else {
            error? e = writeString(htmlfile, html);
            if e is error {
                log:printError("Unable to write result #" + result.sequence_number.toString() + " " + htmlfile + e.reason());
            } else {
                log:printInfo("New result written: " + htmlfile);
            }
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
#	{Code}		If ED result, then 2 digit code of the district. If PD result then
#				2 digit ED code followed by one character PD code, with “P” 
#				being used for postal results for the district.
#	{PDName}	Name of the polling division in English.
#	{ext}		Either “json” or “xml” depending on the format of the file.
# 
# + return - returns the base name for the file 
function getFileNameBase(string electionCode, map<json> result) returns string {
    // start with sequence # and type code
    string name = electionCode + "-" + result.sequence_number.toString() + "-" +
        (result.'type.toString() == PRESIDENTIAL_RESULT ? "PE1" : "PE2") + "-";

    string resultLevel = result.level.toString();

    // add level code and ED / PD code if needed
    match resultLevel {
        LEVEL_PD => { name = name + "PD" + "-" + result.pd_code.toString(); }
        LEVEL_ED => { name = name + "ED" + "-" + result.ed_code.toString(); }
        LEVEL_NI => { name = name + "NI"; }
        LEVEL_NF => { name = name + "NF"; }
    }

    // add electoral district / polling division names if needed with spaces replaced with _
    if resultLevel == LEVEL_ED || resultLevel == LEVEL_PD {
        name = name + "--" + su:replaceAll(result.ed_name.toString()," ", "_");
        if resultLevel == LEVEL_PD {
            name = name + "--" + su:replaceAll(result.pd_name.toString()," ", "_");
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

function writeString(string path, string content) returns error? {
    return writeContent(path, function(io:WritableCharacterChannel wch) returns error? {
        var r = wch.write(content, 0);
        if r is error {
            return r;
        } else {
            return;
        }
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
