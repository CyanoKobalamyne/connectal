// bsv libraries
import Clocks :: *;
import GetPut::*;
import GetPutWithClocks::*;

// portz libraries
import AxiMasterSlave::*;
import CtrlMux::*;
//import Leds::*;
//import Top::*;
import PPS7::*;
import PS7::*;
import Portal::*;

module mkPS7Slave#(Clock axi_clock, Reset axi_reset, StdPortalTop axiTop)(StdPS7);
    StdPS7 ps7 <- mkPS7(axi_clock, axi_reset);

    rule send_int_rule;
    ps7.irq.f2p({15'b0, axiTop.interrupt ? 1'b1 : 1'b0});
    endrule

    rule m_ar_rule;
        let m_ar <- ps7.m_axi_gp[0].req_ar.get();
        axiTop.ctrl.read.readAddr(m_ar.addr, m_ar.len, m_ar.size, m_ar.burst, m_ar.prot, m_ar.cache, m_ar.id);
    endrule

    rule m_aw_rule;
        let m_aw <- ps7.m_axi_gp[0].req_aw.get();
        axiTop.ctrl.write.writeAddr(m_aw.addr, m_aw.len, m_aw.size, m_aw.burst, m_aw.prot, m_aw.cache, m_aw.id);
    endrule

    rule m_arespb_rule;
        AxiRESP#(12/*id_width*/) m_arespb;
        m_arespb.id <- axiTop.ctrl.write.bid();
        m_arespb.resp <- axiTop.ctrl.write.writeResponse();
        ps7.m_axi_gp[0].resp_b.put(m_arespb);
    endrule

    rule m_arespr_rule;
        AxiRead#(32/*data_width*/, 12/*id_width*/) m_arespr;
        m_arespr.r.id = axiTop.ctrl.read.rid();
        m_arespr.r.resp = 2'b0; //.M_AXI_GP0_RRESP(ctrl_rresp),
        m_arespr.rd.data <- axiTop.ctrl.read.readData();
        m_arespr.rd.last = axiTop.ctrl.read.last();
        ps7.m_axi_gp[0].resp_read.put(m_arespr);
    endrule

    rule m_arespw_rule;
        let m_arespw <- ps7.m_axi_gp[0].resp_write.get();
        axiTop.ctrl.write.writeData(m_arespw.wd.data, m_arespw.wstrb, m_arespw.wd.last, m_arespw.wid);
    endrule

/* m_axi interface not bound in examples/echo/Top.bsv
    rule s_areqr_rule;
        AxiREQ#(12/*id_width* /) s_areqr;
        s_areqr.lock = 0;
        s_areqr.qos = 0;
        s_areqr.addr = top_m_axi.read.readAddr();
        s_areqr.burst = top_m_axi.read.readBurstType();
        s_areqr.cache = top_m_axi.read.readBurstCache();
        s_areqr.id = top_m_axi.read.readId();
        s_areqr.len = top_m_axi.read.readBurstLen();
        s_areqr.prot = top_m_axi.read.readBurstProt();
        s_areqr.size = top_m_axi.read.readBurstWidth();
        ps7.s_axi_hp[0].axi.req_ar.put(s_areqr);
    endrule

    rule s_areqw_rule;
        AxiREQ#(12/*id_width* /) s_areqw;
        s_areqw.lock = 0;
        s_areqw.qos = 0;
        s_areqw.addr = top_m_axi.write.writeAddr();
        s_areqw.burst = top_m_axi.write.writeBurstType();
        s_areqw.cache = top_m_axi.write.writeBurstCache();
        s_areqw.id = top_m_axi.write.writeId();
        s_areqw.len = top_m_axi.write.writeBurstLen();
        s_areqw.prot = top_m_axi.write.writeBurstProt();
        s_areqw.size = top_m_axi.write.writeBurstWidth();
        ps7.s_axi_hp[0].axi.req_ar.put(s_areqr);
    endrule

    rule s_arespb_rule;
        let s_arespb = ps7.s_axi_hp[0].axi.resp_b.get();
        top_m_axi.write.writeResponse(s_arespb.resp, s_arespb.id);
    endrule

    rule s_arespr_rule;
        let s_arespr = ps7.s_axi_hp[0].axi.resp_read.get();
        top_m_axi.read.readData(s_arespr.rd.data, s_arespr.r.resp, s_arespr.rd.last, s_arespr.r.id);
    endrule

    rule s_arespw_rule;
        AxiWrite#(32/*data_width* /, 12/*id_width* /) s_arespw;
        s_arespw.wid = top_m_axi.write.writeWid();
        //??s_arespw.wd.data <= top_m_axi.write.writeWid(); //.m_axi_write_writeData(m_axi_wdata_wire),
        //.S_AXI_HP0_WDATA(m_axi_wdata),
        s_arespw.wd.last = top_m_axi.write.writeLastDataBeat();
        s_arespw.wstrb = top_m_axi.write.writeDataByteEnable();
        ps7.s_axi_hp[0].axi.resp_write.put(s_arespw);
    endrule
end of m_axi */
    return ps7;
endmodule
