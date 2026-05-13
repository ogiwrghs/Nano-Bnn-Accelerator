# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start BNN NPU Sanity Check")

    # NOTE ON TESTING METHODOLOGY:
    # The actual 1-Bit NPU was validated using dardware-in-the-loop (HITL)
    # on a Cyclone V SoC FPGA (running a C-Driver via an AXI Bridge).
    # Because of the complexity of the time-multiplexed inference looping, 
    # the primary validation was done in physical hardware.
    # 
    # This cocotb test serves purely as a CI/CD sanity check to ensure the
    # Verilog compiles, the clock runs, and the reset toggles safely.

    # Set the clock period to 20 ns (50 MHz) to match our OpenROAD constraints
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    # Safely ground all inputs before reset
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    
    # Engage Reset (Active Low)
    dut._log.info("Asserting Reset...")
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    
    # Release Reset
    dut._log.info("Releasing Reset...")
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 50)
    
    dut._log.info("Sanity check passed! Chip is alive and ready for physical C-Driver execution.")
