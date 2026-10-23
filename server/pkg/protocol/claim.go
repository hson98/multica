package protocol

import "time"

// DaemonBatchClaimRequestTimeout is the existing HTTP client timeout and WS
// execution budget. Servers must leave room inside it for claim recovery and
// response delivery so installed daemons can still receive partial batches.
//
// Personal build: raised from 5s because the database sits ~220ms away, and a
// claim with a queued task runs a dozen sequential queries.
const DaemonBatchClaimRequestTimeout = 20 * time.Second
