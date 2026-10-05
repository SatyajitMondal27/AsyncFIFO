# Formal Verification of an Asynchronous FIFO

This project explores the **formal verification of an asynchronous FIFO (First-In, First-Out buffer)** using **SymbiYosys**.

The FIFO transfers data between two independent clock domains and uses **Gray-coded read/write pointers** with **two-stage synchronizers** for clock-domain crossing (CDC). The goal of this project is to develop and verify properties covering reset behavior, pointer movement, FIFO full/empty detection, read/write operations, and data integrity.

The project was developed as a hands-on exercise in applying formal verification techniques to a realistic RTL design.

## FIFO Architecture

The FIFO has the following configuration:

| Parameter | Value |
|---|---:|
| FIFO depth | 16 entries |
| Data width | 64 bits |
| Pointer width | 5 bits |
| Write clock | `wclk` |
| Read clock | `rclk` |

Although a 16-entry FIFO requires only four address bits, the read and write pointers contain an additional bit to distinguish between the **full** and **empty** conditions after pointer wrap-around.

The FIFO operates across two independent clock domains:

```text
              Write Clock Domain                    Read Clock Domain

 wdata ─────► FIFO Memory ─────────────────────────► rdata
                 │
                 │
          Gray Write Pointer
                 │
                 │     Two-stage synchronizer
                 └──────────────────────────────► g_wsync2
                                                    │
                                                    ▼
                                             Empty Detection


          Gray Read Pointer
                 ▲
                 │     Two-stage synchronizer
 g_rsync2 ◄──────┘
      │
      ▼
 Full Detection
```

## Clock-Domain Crossing

The FIFO maintains separate read and write pointers.

The write pointer is updated in the `wclk` domain:

```text
Binary Write Pointer
        │
        ▼
Binary → Gray
        │
        ▼
Gray Write Pointer
```

The read pointer follows the same structure in the `rclk` domain.

Gray coding is used when transferring pointers between clock domains because consecutive Gray-code values differ by only one bit.

The write pointer is synchronized into the read domain through:

```text
g_wptr → g_wsync1 → g_wsync2
```

Similarly, the read pointer is synchronized into the write domain through:

```text
g_rptr → g_rsync1 → g_rsync2
```

The synchronized pointers are then used for FIFO full and empty detection.

## Formal Verification Environment

Formal verification is performed using **SymbiYosys**.

The verification environment makes the FIFO control and data inputs symbolic so that the formal engine can explore different combinations of:

- Write requests
- Read requests
- Input data
- FIFO states
- Pointer positions

The project also models separate read and write clocks to exercise the FIFO across different clock domains.

Because several properties depend on previous clock cycles, separate past-valid signals are maintained for the read and write domains before using `$past()`-based assertions.

## Properties Under Verification

The formal verification effort is divided into several categories.

### Reset Behavior

Reset properties verify that the read and write pointers return to their initial state following their respective resets.

Examples of intended behavior include:

```text
wreset
   │
   ▼
Write Pointer = 0
```

and:

```text
rreset
   │
   ▼
Read Pointer = 0
```

The FIFO's full and empty status during reset is also checked according to the interface behavior implemented by the RTL.

### Pointer Arithmetic

Properties check the relationship between the current and next binary pointers.

```text
next_write_pointer = write_pointer + 1

next_read_pointer  = read_pointer + 1
```

The project also verifies the relationship between the binary and Gray-coded pointer representations.

### Write Operations

A successful write is defined as:

```text
wval && !wfull
```

For an accepted write, the verification checks that:

1. The write pointer advances.
2. The input data is written to the memory location corresponding to the previous write pointer.

Conceptually:

```text
Valid Write
    │
    ├────────► Write Pointer Advances
    │
    └────────► FIFO[address] = wdata
```

The complementary case—where no write is accepted—is also intended to verify that the write pointer remains unchanged.

### Read Operations

A valid read occurs when a read request is issued while the FIFO is not empty.

The verification effort checks the relationship between:

```text
ren
rempty
read pointer
FIFO memory
rdata
```

Read-side properties are being refined alongside the exact output semantics of the FIFO.

### Empty Detection

The FIFO is empty when the current read pointer matches the synchronized write pointer in the read clock domain.

```text
g_rptr == g_wsync2
        │
        ▼
     rempty
```

Formal properties are used to verify this relationship.

### Full Detection

FIFO full detection is based on the relationship between the Gray-coded write pointer and the synchronized read pointer.

The additional pointer bit allows the design to distinguish between:

```text
Read Pointer == Write Pointer
             → EMPTY
```

and the wrap-around condition corresponding to a full FIFO.

## Multi-Clock Formal Verification

One of the main challenges in formally verifying this design is the presence of two independent clocks.

The formal environment therefore models `wclk` and `rclk` separately rather than treating the design as a conventional single-clock FIFO.

This allows properties to be associated with the clock domain in which the corresponding state is updated.

For example:

```text
Write-domain properties → posedge wclk

Read-domain properties  → posedge rclk
```

This project has been particularly useful for exploring the interaction between formal verification and clock-domain crossing logic.

## Counterexample-Driven Debugging

An important goal of the project is not simply to make assertions pass, but to use formal counterexamples to understand incorrect RTL behavior or incorrect verification assumptions.

During development, counterexample traces were inspected using waveform traces generated by the formal tool. This process helped identify differences between the expected FIFO interface behavior and the implemented read-data behavior.

This highlighted an important aspect of formal verification:

> A failing assertion does not automatically mean that the RTL is incorrect. It can also indicate that the property or assumed specification does not match the actual design.

The project therefore treats counterexample analysis as an integral part of the verification process.

## Current Verification Status

This project is a work in progress.

The current verification environment covers or is being developed to cover:

- Reset behavior
- Binary and Gray pointer relationships
- Pointer progression
- FIFO full detection
- FIFO empty detection
- Write behavior
- Read behavior
- Memory updates
- Multi-clock operation

Additional properties are being developed to strengthen the verification from individual RTL mechanisms toward complete FIFO-level correctness.

## Planned Improvements

The next stage of the project will focus on stronger system-level properties, including:

- Read-pointer advancement and stability
- Write-pointer stability when writes are blocked
- Two-stage synchronizer behavior
- Stronger full/empty equivalence properties
- Pointer wrap-around
- FIFO full and empty transitions
- Formal cover properties
- Inductive invariants
- Arbitrary clock relationships
- End-to-end data integrity
- No lost entries
- No duplicated entries
- FIFO ordering

A major target is an end-to-end ordering property demonstrating that data accepted by the write interface is returned in the same order by the read interface.

For example:

```text
WRITE                           READ

A ──┐
B ──┼────► Async FIFO ────────► A
C ──┘                          B
                               C
```

The FIFO must never return:

```text
A → C → B
```

for writes accepted in the order:

```text
A → B → C
```

## Tools

- SystemVerilog
- SymbiYosys
- Yosys
- SMT-based formal verification
- GTKWave / VCD traces for counterexample analysis

## Learning Objectives

This project is intended to develop practical experience with:

- Formal property development
- Assertions and assumptions
- `$past()` and temporal reasoning
- Symbolic inputs
- Bounded model checking
- Inductive proofs
- Counterexample analysis
- Formal clock modeling
- Clock-domain crossing
- Gray-coded pointers
- Formal verification of memory structures
- State-space and invariant reasoning

## Repository Structure

A typical repository structure for the project is:

```text
async-fifo-formal/
│
├── rtl/
│   └── async_fifo.sv
│
├── formal/
│   ├── async_fifo.sby
│   └── properties/
│
├── traces/
│   └── README.md
│
└── README.md
```

Generated SymbiYosys build directories and solver output should generally be excluded from version control through `.gitignore`. Counterexample traces that demonstrate particularly interesting bugs can instead be preserved intentionally and documented.

## Project Motivation

Asynchronous FIFOs are small enough to understand at the RTL level while still containing several verification challenges:

- Multiple clock domains
- Clock-domain crossing
- Pointer synchronization
- Gray-code encoding
- Wrap-around
- Full/empty detection
- Memory correctness
- Temporal ordering

These characteristics make an asynchronous FIFO a useful design for studying how formal verification can establish properties that are difficult to cover comprehensively using simulation alone.

## Disclaimer

This repository is an educational formal-verification project and is under active development. Passing individual assertions should not be interpreted as a claim that every possible correctness property of the asynchronous FIFO has already been proven.

The long-term objective is to build toward a complete set of safety, data-integrity, ordering, reachability, and inductive properties for the design.
