const ERROR_REASON = "{eclk/pubhub}Error";

// TODO: finalize topics
# The topic against which the publisher will publish updates and the subscribers
# need to subscribe to, to receive result updates in `json` format.
public const JSON_RESULTS_TOPIC = "https://github.com/ECLK/Results-Dist-json";

# The topic against which the publisher will publish updates and the subscribers
# need to subscribe to, to receive result updates in `xml` format.
public const XML_RESULTS_TOPIC = "https://github.com/ECLK/Results-Dist-xml";

# The topic against which the publisher will publish updates and the subscribers
# need to subscribe to, to receive result updates in text format.
public const TEXT_RESULTS_TOPIC = "https://github.com/ECLK/Results-Dist-text";

# The topic against which the publisher will publish updates and the subscribers
# need to subscribe to, to receive an image of the result update.
public const IMAGE_RESULTS_TOPIC = "https://github.com/ECLK/Results-Dist-image";
