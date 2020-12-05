![Result-Dist CI Workflow](https://github.com/ECLK/Results-Dist/workflows/Result-Dist%20CI%20Workflow/badge.svg)

# Results Distribution System

This system distributes results to registered entities.

## High Level Architecture

![alt text](images/high_level_architecture.png)

## Components
This result distributor system consists of three components.
- Distributor (publisher)
- Recipient (subscriber)
- Test driver

All three components can be built and run locally, allowing the entire system to be tested locally while simulating an election.

### Distributor (Publisher)
The distributor consists of the following:
- A WebSocket server at which recipients can establish connections
- An HTTP service which on receipt of a new result (e.g., a verified result from an upstream system), delivers the same to all registered recipients. For certain types of results, the distributor may also compute and send an incremental result.
- A simple website which allows downloading the released results.

### Recipient (Subscriber)
The recipient is a WebSocket client service that establishes a persistent, one-directional connection with the distributor to receive results. The recipient will continue to receive data as long as the connection is not closed.
