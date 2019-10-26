const PRESIDENTIAL_RESULT = "PRESIDENTIAL";

type ResultLevel 
    "POLLING-DIVISION" | 
    "ELECTORAL-DISTRICT" | 
    "NATIONAL-INCREMENTAL" | 
    "NATIONAL-FINAL";

type PresidentialResult record {|
    PRESIDENTIAL_RESULT 'type;
    string timestamp;
    ResultLevel level;
    string ed_code?;
    string ed_name?;
    string pd_code?;
    string pd_name?;
    record {|
        string party;
        string candidate;
        int votes;
        decimal percentage;
    |}[] by_party;
    record {|
        int valid;
        int rejected;
        int polled;
        int electors;
    |} summary;
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
    record {|
        string party;
        string candidate;
        int votes;
        decimal percentage;
    |}[] by_party;
|};
