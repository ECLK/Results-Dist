import ballerina/http;
import ballerina/io;
import ballerina/log;
import ballerina/xmlutils;
import ballerina/stringutils as su;

const PRESIDENTIAL_RESULT = "PRESIDENTIAL-FIRST";
const R_V = "R_V";
const R_VI = "R_VI";
const R_S = "R_S";
const R_SI = "R_SI";
const R_SC = "R_SC";
const R_VSN = "R_VSN";
const R_NC = "R_NC";

const LEVEL_PD = "POLLING-DIVISION";
const LEVEL_ED = "ELECTORAL-DISTRICT";
const LEVEL_NI = "NATIONAL-INCREMENTAL";
const LEVEL_NF = "NATIONAL";


function saveResult(map<json> resultAll) {
    string electionCode = resultAll.election_code.toString();
    map<json> result = <map<json>> resultAll?.result;

    string fileBase = getFileNameBase(electionCode, result);
    if wantJson {
        string jsonfile = fileBase + JSON_EXT;
        error? e = writeJson(jsonfile, result);
        if e is error {
            log:printError("Unable to write result #" + result.sequence_number.toString() + " " + jsonfile + e.reason());
        } else {
            log:printInfo("New result written: " + jsonfile);
        }
    }
    if wantXml {
        string xmlfile = fileBase + XML_EXT;
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
        string|error html = generateHtml(electionCode, result, sortedHtml);
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

function saveImagePdf(map<json> imageJson) {
    string electionCode = imageJson.election_code.toString();
    string seqNo = imageJson.sequence_number.toString();

    string pdfFile = getFileNameBase(electionCode, imageJson) + PDF_EXT;
    http:Client cl = <http:Client> imageClient;
    http:Response|error res = cl->get(string `/release/${electionCode}/${seqNo}`);

    byte[]? pdfBytes = ();
    if res is http:Response {
        byte[]|error binaryContent = res.getBinaryPayload();
        if binaryContent is byte[] {
            pdfBytes = binaryContent;
        } else {
           log:printError("Error retrieving PDF binary payload", binaryContent);
           return;
        }
    } else {
        log:printError("Error retrieving PDF", res);
        return;
    }

    error? e = writePdf(pdfFile, <byte[]> pdfBytes);
    if e is error {
        log:printError("Unable to write result #" + seqNo + " " + pdfFile,
                        e);
    } else {
        log:printInfo("New result written: " + pdfFile);
    }
}

# Return the file name to store this result using the election format:
# 	NNN-{TypeCode}-{LevelCode}[-{Code}[--{EDName[--{PDName}]]].{ext}
# where
# 	NNN			Sequence number of the result with 0s if needed (001, 002, ..).
#	{TypeCode}	Presidential result type- first preference or 2nd/3rd preference. “PE1” for
#				first preference count and “PE2” for 2nd/3rd preference counts.
#               Parliamentary Result type- "R_V", "R_VI", "R_S", "R_SI", "R_SC", "R_VSN", "R_NC".
#	{LevelCode}	Presidential result level: PD for polling division, ED for electoral district,
#				NI for national incremental result and NF for national final result.
#               Parliamentary result level: PD for polling division, ED for electoral district, and N for national.
#   {Code}      If ED results, then 2 digit code of the district. If PD results then 2 digit ED code followed by one
#               character PD code. For Postal, Displaced and Quarantine results, the pd_code will be “PV”, “DV” and
#               “QV” respectively.
#	{EDName}	Name of the electoral district in English.
#	{PDName}	Name of the polling division in English.
#	{ext}		Either “json” or “xml” depending on the format of the file.
# 
# + return - returns the base name for the file 
function getFileNameBase(string electionCode, map<json> result) returns string {
    // result type code
    string resultType = result.'type.toString();
    match resultType {
        R_V|R_VI|R_S|R_SI|R_SC|R_VSN|R_NC => { }
        PRESIDENTIAL_FIRST => { resultType = "PE1"; }
        _ => { resultType = "PE2"; }
    }

    // start with sequence # and type code
    string name = (wantCode ? electionCode + "-" : "") + result.sequence_number.toString() + "-" + resultType + "-";

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

function writeJson(string path, json content) returns @tainted error? {
    return writeContent(path, 
                        function(io:WritableCharacterChannel wch) returns error? {
                            return wch.writeJson(content);
                        });
}

function writeXml(string path, xml content) returns @tainted error? {
    return writeContent(path, function(io:WritableCharacterChannel wch) returns error? {
        return wch.writeXml(content);
    });
}

function writePdf(string path, byte[] content) returns @tainted error? {
    io:WritableByteChannel wbc = check io:openWritableFile(path);
    _ = check wbc.write(content, 0); // TODO: replace check to ensure channels are closed
    check wbc.close();
}

function writeString(string path, string content) returns @tainted error? {
    return writeContent(path, function(io:WritableCharacterChannel wch) returns error? {
        var r = wch.write(content, 0);
        if r is error {
            return r;
        } else {
            return;
        }
    });
}

function writeContent(string path, function(io:WritableCharacterChannel wch) returns error? writeFunc) 
        returns @tainted error? {
    io:WritableByteChannel wbc = check io:openWritableFile(path);
    io:WritableCharacterChannel wch = new(wbc, "UTF8");
    check writeFunc(wch); // TODO: replace check to ensure channels are closed
    check wch.close();
    check wbc.close(); // should use return here but there's a taint detection bug in the compiler that
                       // apparently considers this error as tainted. huh??
}
