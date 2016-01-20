#include <stdio.h>

#include <spikehw.h>

SpikeHw *spikeHw;

int main(int argc, const char **argv)
{
    spikeHw = new SpikeHw();
    // not needed yet
    //spikeHw->setupDma(memfd);

    // query mmcm and interrupt status
    spikeHw->status();

    // read boot rom
    uint32_t firstword;
    spikeHw->read(0x000000 + 0x000, (uint8_t *)&firstword);
    fprintf(stderr, "First word of boot ROM %08x (expected %08x)\n", firstword, 0x00001137);

    // read ethernet identification register
    uint32_t id;
    spikeHw->read(0x180000 + 0x4f8, (uint8_t *)&id);
    fprintf(stderr, "AXI Ethernet Identification %08x (expected %08x)\n", id, 0x09000000);
    return 0;
}
