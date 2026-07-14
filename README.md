![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Nano-Bnn-Accelerator

A custom 1-bit Binary Neural Network (BNN) hardware accelerator designed for the Tiny Tapeout ASIC shuttle.

## What is it?

This is an ultra-low-level hardware accelerator for edge AI inference. Instead of using standard, area-heavy multipliers for ML operations, this design compresses weights and activations down to 1-bit (+1 and -1). 

It replaces standard multiplication with simple XNOR logic and uses a 3-stage Popcount adder tree to sum the results into a 10-bit accumulator. It's built for maximum efficiency on strict hardware constraints.

## Architecture

The design follows a modular, nested structure:

* **`src/neuron.v`**: The core processing element. It acts as an FSM-less, 1-bit MAC processor. It also includes an Edge Detector to safely handle Clock Domain Crossing (CDC) between the host processor and the ASIC.
* **`src/tt_um_vmm_bnn.v`**: The top-level silicon wrapper. It instantiates 8 parallel neurons, manages the 64 D-Flip-Flop weight memory, and features an output multiplexer to squeeze the 10-bit results out of the strict 34 I/O pin limit of the Tiny Tapeout tile.
* **`fpga/fpga_top.v`**: The hardware-in-the-loop prototyping wrapper used to bridge the NPU with an ARM host processor on an FPGA prior to tapeout.

## How to Test

### Simulation

The design is verified using `cocotb` (v1.9.2) and `iverilog`. To run the testbench and Gate-Level tests:

1. Navigate to the `test/` directory.
2. Run `make`.

> **Note:** The `test.py` script will feed inputs to the NPU and assert the expected accumulator results.

### Physical Hardware

To run inference on actual hardware (FPGA or the Tiny Tapeout RP2040 carrier board), use the provided C-driver. You can find the source in `software/fullinfer2npu.c`. This script handles sending the 1-bit data pulses to the ASIC and reading back the computed results.
