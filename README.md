# DAG Blockchain

# UML Schema of the DAG Blockchain
```mermaid
 classDiagram
    class DAGBlockchain {
        +init(allocator)
        +deinit()
        +addTransaction(transaction)
        +runConsensus()
        -initGenesis()
        -updateWeights()
    }

    class Transaction {
        +id: [32]u8
        +sender: [32]u8
        +receiver: [32]u8
        +amount: u64
        +timestamp: i64
        +signature: [64]u8
        +references: [2][32]u8
        +nonce: u64
        +verify()
    }

    class DAGNode {
        +transaction: Transaction
        +weight: f32
        +is_confirmed: bool
        +confirmation_time: ?i64
        +init(transaction)
    }

    class Server {
        +start()
        -handleSimulatorStart()
        -handleSimulatorStop()
        -handleSimulatorStatus()
        -logRequest()
        -logResponse()
    }

    class Request {
        +method: Method
        +version: string
        +uri: string
        +body: string
        +init()
        +parse_request()
        +read_request()
    }

    class Response {
        +send_200()
        +send_404()
        +sendJSON()
    }

    class Socket {
        +_address: Address
        +_stream: Stream
        +init()
    }

    class NetworkSimulator {
        +init(blockchain, tps)
        +start(duration_ms)
        +stop()
        -processBatch()
    }

    class SimulatorState {
        +sim: NetworkSimulator
        +mutex: Thread.Mutex
    }

    class SyllaDB {
        +init(allocator)
        +deinit()
        +store(id, node)
        +get(id)
        +getApprovers(id)
    }

    class TigerBeetle {
        +init(allocator)
        +deinit()
        +checkBalance()
        +updateBalance()
        +getBalance()
    }

    class CLI {
        +init(allocator, blockchain)
        +start()
        -handleCommand()
    }

    DAGBlockchain *-- DAGNode
    DAGNode *-- Transaction
    DAGBlockchain --> SyllaDB : uses
    DAGBlockchain --> TigerBeetle : uses
    Server --> Request : processes
    Server --> Response : sends
    Server --> Socket : uses
    Server o-- SimulatorState : manages
    SimulatorState *-- NetworkSimulator
    NetworkSimulator --> DAGBlockchain : simulates
    CLI --> DAGBlockchain : manages
```

## Build and Run

Build and run the blockchain simulation:
```bash
zig build run
```

Run tests:
```bash
zig build test
```

## CLI Usage

Start the interactive CLI:
```bash
zig build cli
```

### Available Commands

1. Send tokens:
```bash
send <sender_hex> <receiver_hex> <amount>
```

2. Check account balance:
```bash
balance <address_hex>
```

3. Get transaction details:
```bash
tx <transaction_id_hex>
```

4. List all transactions:
```bash
list
```

5. Show help:
```bash
help
```

6. Exit CLI:
```bash
exit
```

### Example Usage

```bash
# Send 100 tokens
> send 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f 202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f 100

# Check balance
> balance 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f

# View transaction details
> tx a1b2c3d4e5f6...

# List all transactions
> list
```

Note: All addresses and transaction IDs should be in hexadecimal format.