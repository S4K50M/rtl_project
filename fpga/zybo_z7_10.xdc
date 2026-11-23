## Constraints for noc_board_top on Zybo Z7-10 (xc7z010clg400-1)

## 125 MHz system clock (pin K17)
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -name sys_clk -period 8.000 -waveform {0 4} [get_ports clk]

## reset_n (active low) -> slide switch SW0 (G15). Switch UP/ON = run, DOWN = reset
set_property -dict { PACKAGE_PIN G15 IOSTANDARD LVCMOS33 } [get_ports reset_n]

## uart_tx -> Pmod JE pin 1 (V12). Connect to RX of a 3.3V USB-UART adapter, share GND
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports uart_tx]