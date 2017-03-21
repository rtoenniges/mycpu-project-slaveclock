# MyCPU_PRG_SCC
A program written in assembler for the [MyCPU](http://www.mycpu.eu/) from Dennis Kuschel to control a slave clock (https://en.wikipedia.org/wiki/Slave_clock)

## Hardware
- External module (Basic board)
- Rack extension (Clock control & DCF77 signal converting)

## Software
- scc.asm (Main program)
- sl60dcf77.asm (Library for DCF77 decoding (Can be found at https://github.com/rtoenniges/MyCPU_LIB_DCF77))
