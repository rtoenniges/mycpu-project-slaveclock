# Hardware
## External module (Basic board without DCF77-Input)
This board only generates the alternating current to drive the clock.

## Rack Extension (DCF77-Input and slave-clock control)
This board is connected directly to the MyCPU-Backplane Bus._
It provides support to connect an DCF77-Receiver and generates the alternating
current to drive the clock._
Also it displays the status of the time synchronization and the active clock output.

**If you use this board and you have set the adress jumpers to the default position, you
have to change the "OUTPUT" declaration in "scc.asm" to '3500h'!**

