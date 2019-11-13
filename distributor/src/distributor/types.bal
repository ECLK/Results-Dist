
type ResultLevel 
    "POLLING-DIVISION" | 
    "ELECTORAL-DISTRICT" | 
    "NATIONAL-INCREMENTAL" | 
    "NATIONAL-FINAL";

type PartyResult record {|
    string party_code;
    string party_name;
    string candidate;
    int votes;
    int votes1st?;
    int votes2nd?;
    int votes3rd?;
    string percentage;
|};

type SummaryResult record {|
    int valid;
    int rejected;
    int polled;
    int electors;
    string percent_valid;
    string percent_rejected;
    string percent_polled;
|};

const PRESIDENTIAL_RESULT = "PRESIDENTIAL-FIRST";

type PresidentialResult record {|
    PRESIDENTIAL_RESULT 'type;
    string timestamp;
    ResultLevel level;
    string ed_code?;
    string ed_name?;
    string pd_code?;
    string pd_name?;
    PartyResult[] by_party;
    SummaryResult summary;
|};

const PRESIDENTIAL_PREFS_RESULT = "PRESIDENTIAL-PREFS";

type PreferencesResultLevel
    "POLLING-DIVISION-PREFS-ONLY" |
    "POLLING-DIVISION-WITH-PREFS" |
    "ELECTORAL-DISTRICT-PREFS-ONLY" |
    "ELECTORAL-DISTRICT-WITH-PREFS" |
    "NATIONAL-INCREMENTAL-WITH-PREFS" | 
    "NATIONAL-FINAL-WITH-PREFS";

type PresidentialPreferencesResult record {|
    PRESIDENTIAL_PREFS_RESULT 'type;
    string timestamp;
    PreferencesResultLevel level;
    string ed_code?;
    string ed_name?;
    string pd_code?;
    string pd_name?;
    PartyResult[] by_party;
|};

// Shared record structure for all results that we can persist as well
type Result record {|
    int sequenceNo;
    string election;
    string code;
    string 'type;
    map<json> jsonResult;
    string? imageMediaType;
    byte[]? imageData;
|};

// SMS recipient record
type Recipient record {|
    string username;
    string mobile;
|};
