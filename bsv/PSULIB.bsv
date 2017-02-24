
// Copyright (c) 2013 Quanta Research Cambridge, Inc.

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
`include "ConnectalProjectConfig.bsv"
import BuildVector::*;
import Clocks::*;
import DefaultValue::*;
import GetPut::*;
import Connectable::*;
import ConnectableWithTrace::*;
import Bscan::*;
import Vector::*;
import XilinxCells::*;
import ConnectalXilinxCells::*;
import ConnectalClocks::*;
import AxiMasterSlave::*;
import Axi4MasterSlave::*;
import AxiDma::*;
import AxiBits::*;
import MemTypes::*;
import Platform::*;
import ZYNQ_ULTRA::*;

(* always_ready, always_enabled *)
interface Bidir#(numeric type data_width);
    method Action             i(Bit#(data_width) v);
    method Bit#(data_width)   o();
    method Bit#(data_width)   t();
endinterface

interface ZynqPins;
endinterface

interface PSULIB;
    (* prefix="" *)
    interface Vector#(1, PsultraMaxigp)     m_axi_gp;
    method Action                             interrupt(Bit#(1) v);
    interface Vector#(4, Clock) plclk;
    interface Clock portalClock;
    interface Reset portalReset;
    interface Clock derivedClock;
    interface Reset derivedReset;
endinterface

module mkPSULIB#(Clock axiClock)(PSULIB);
   // B2C converts a bit to a clock, enabling us to break the apparent cycle
   Vector#(4, B2C) b2c <- replicateM(mkB2C());

   // need the bufg here to reduce clock skew
   module mkBufferedClock#(Integer i)(Clock); let c <- mkClockBUFG(clocked_by b2c[i].c); return c; endmodule
   module mkBufferedReset#(Integer i)(Reset); let r <- mkResetBUFG(clocked_by b2c[i].c, reset_by b2c[i].r); return r; endmodule
   Vector#(4, Clock) fclk <- genWithM(mkBufferedClock);
   Vector#(4, Reset) freset <- genWithM(mkBufferedReset);

`ifndef TOP_SOURCES_PORTAL_CLOCK
   Clock single_clock = fclk[0];
`ifdef ZYNQ_NO_RESET
   freset[0]          = noReset;
`endif
   let single_reset   = freset[0];
`else
   //Clock axiClockBuf <- mkClockBUFG(clocked_by axiClock);
   Clock axiClockBuf = axiClock;
   Clock single_clock = axiClockBuf;
   Reset axiResetUnbuffered <- mkSyncReset(10, freset[0], single_clock);
   Reset axiReset <- mkResetBUFG(clocked_by axiClockBuf, reset_by axiResetUnbuffered);
   let single_reset   = axiReset;
`endif

   ClockGenerator7Params clockParams = defaultValue;
   // input clock 200MHz for speed grade -2, 100MHz for speed grade -1
   // fpll needs to be in the range 600MHz - 1200MHz for either input clock
   //
   // fclkin = 1e9 / mainClockPeriod
   // fpll = 1e9 = mult_f * 1e9 / mainClockPeriod
   // mult_f = mainClockPeriod
   //
   // fclkout0 = 1e9 / divide_f = 1e9 / derivedClockPeriod
   // divide_f = derivedClockPeriod
   //
   clockParams.clkfbout_mult_f       = mainClockPeriod;
   clockParams.clkfbout_phase     = 0.0;
   clockParams.clkfbout_phase     = 0.0;
   clockParams.clkin1_period      = mainClockPeriod;
   clockParams.clkout0_divide_f   = derivedClockPeriod;
   clockParams.clkout0_duty_cycle = 0.5;
   clockParams.clkout0_phase      = 0.0000;
   clockParams.clkout0_buffer     = True;
   clockParams.clkin_buffer = False;
   ClockGenerator7   clockGen <- mkClockGenerator7(clockParams, clocked_by single_clock, reset_by single_reset);
   let derived_clock = clockGen.clkout0;
   let derived_reset_unbuffered <- mkSyncReset(10, single_reset, derived_clock);
   let derived_reset <- mkResetBUFG(clocked_by derived_clock, reset_by derived_reset_unbuffered);

   ZYNQ_ULTRA::PSUltra psu <- ZYNQ_ULTRA::mkPSUltra(single_clock, single_clock);

   // this rule connects the pl_clk wires to the clock net via B2C
   for (Integer i = 0; i < 1; i = i + 1) begin
      ReadOnly#(Bit#(1)) fclkb;
      fclkb       <- mkNullCrossingWire(b2c[i].c, psu.pl.clk0);
      rule b2c_rule1;
	 b2c[i].inputclock(fclkb[i]);
      endrule
   end

    interface m_axi_gp = vec(psu.maxigp0);
    interface plclk = fclk;
`ifndef TOP_SOURCES_PORTAL_CLOCK
    interface portalClock = fclk[0];
    interface portalReset = freset[0];
`else
    interface portalClock = axiClockBuf;
    interface portalReset = axiReset;
`endif
    interface derivedClock = derived_clock;
    interface derivedReset = derived_reset;
    method Action interrupt(Bit#(1) v);
       //psu.irq.f2p({19'b0, v});
    endmethod
endmodule

interface PsultraAruser;
    method Action      aruser(Bit#(5) v);
    method Action      awuser(Bit#(5) v);
endinterface

instance ToAxi4MasterBits#(Axi4MasterBits#(40,128,16,PsultraAruser), PsultraMaxigp);
function Axi4MasterBits#(40,128,16,PsultraAruser) toAxi4MasterBits(PsultraMaxigp m);
   return (interface Axi4MasterBits#(40,128,16,PsultraAruser);
      method araddr = m.araddr;
	   method arburst = m.arburst;
	   method arcache = m.arcache;
	   method Bit#(1) aresetn(); return 1; endmethod
	   method Bit#(16)     arid(); return 0; endmethod
	   method arlen = m.arlen;
	   method arlock = 0;
	   method arprot = m.arprot;
	   method arqos = 0;
	   method arready = m.arready;
	   method arsize = m.arsize;
	   method arvalid = m.arvalid;
	   method Bit#(40)     awaddr(); return 0; endmethod
	   method Bit#(2)     awburst(); return 0; endmethod
	   method Bit#(4)     awcache(); return 0; endmethod
	   method Bit#(16)     awid(); return 0; endmethod
	   method Bit#(8)     awlen(); return 0; endmethod
	   method Bit#(2)     awlock(); return 0; endmethod
	   method Bit#(3)     awprot(); return 0; endmethod
	   method Bit#(4)     awqos(); return 0; endmethod
	   method Action      awready(Bit#(1) v); endmethod
	   method Bit#(3)     awsize(); return 0; endmethod
	   method Bit#(1)     awvalid(); return 0; endmethod
	   method Action      bid(Bit#(16) v); endmethod
	   method Bit#(1)     bready(); return 0; endmethod
	   method Action      bresp(Bit#(2) v); endmethod
	   method Action      bvalid(Bit#(1) v); endmethod
	   method rdata = m.rdata;
	   method Action      rid(Bit#(16) v); endmethod
	   method rlast = m.rlast;
	   method rready = m.rready;
	   method rresp = m.rresp;
	   method rvalid = m.rvalid;
	   method Bit#(128)     wdata(); return 0; endmethod
	   method Bit#(16)     wid(); return 0; endmethod
	   method Bit#(1)     wlast(); return 0; endmethod
	   method Action      wready(Bit#(1) v); endmethod
	   method Bit#(TDiv#(128,8))     wstrb(); return 0; endmethod
	   method Bit#(1)     wvalid(); return 0; endmethod
	 interface extra = ?;   
	 endinterface);
   endfunction: toAxi4MasterBits
endinstance

instance ConnectableWithTrace#(PSULIB, Platform, traceType);
   module mkConnectionWithTrace#(PSULIB psu, Platform top, traceType readout)(Empty);
      Axi4MasterBits#(40,128,16,PsultraAruser) master = toAxi4MasterBits(psu.m_axi_gp[0]);
      PhysMemMaster#(32,32) physMemMaster <- mkPhysMemMaster(master);
      mkConnection(physMemMaster, top.slave);
   endmodule
endinstance
