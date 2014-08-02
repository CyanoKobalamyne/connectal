
// Copyright (c) 2012 Nokia, Inc.
// Copyright (c) 2013-2014 Quanta Research Cambridge, Inc.

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

#include "portal.h"
#include "sock_utils.h"

#ifdef __KERNEL__
#include "linux/delay.h"
#define assert(A)
#else
#include <string.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <time.h> // ctime
#endif

#ifdef ZYNQ
#include <android/log.h>
#include <zynqportal.h>
#else
#include <pcieportal.h> // BNOC_TRACE
#endif

static void init_directory(void);
static PortalInternal globalDirectory;

#ifdef __KERNEL__
static tBoard* tboard;
#endif

void init_portal_internal(PortalInternal *pint, int id, PORTAL_INDFUNC handler)
{
    int rc = 0;
    char buff[128];
    char read_status;
    int addrbits = 16;

    init_directory();
    memset(pint, 0, sizeof(*pint));
    if (id != -1) {
        pint->fpga_number = directory_get_fpga(id);
        addrbits = directory_get_addrbits(id);
    }
    pint->fpga_fd = -1;
    pint->handler = handler;
    snprintf(buff, sizeof(buff), "/dev/fpga%d", pint->fpga_number);
#ifdef BSIM   // BSIM version
    connect_to_bsim();
#elif defined(__KERNEL__)
    pint->map_base = (volatile unsigned int*)(tboard->bar2io + pint->fpga_number * PORTAL_BASE_OFFSET);
#else
#ifdef ZYNQ
    PortalEnableInterrupt intsettings = {3 << 14, (3 << 14) + 4};
    int pgfile = open("/sys/devices/amba.0/f8007000.devcfg/prog_done", O_RDONLY);
    if (pgfile == -1) {
        // 3.9 kernel uses amba.2
        pgfile = open("/sys/devices/amba.2/f8007000.devcfg/prog_done", O_RDONLY);
    }
    if (pgfile == -1) {
	PORTAL_PRINTF("failed to open /sys/devices/amba.[02]/f8007000.devcfg/prog_done %d\n", errno);
	rc = -1;
	goto errlab;
    }
    if (read(pgfile, &read_status, 1) != 1 || read_status != '1') {
	PORTAL_PRINTF("FPGA not programmed: %x\n", read_status);
	rc = -ENODEV;
	goto errlab;
    }
    close(pgfile);
    pint->fpga_fd = open(buff, O_RDWR);
    ioctl(pint->fpga_fd, PORTAL_ENABLE_INTERRUPT, &intsettings);
#else
    // FIXME: bluenoc driver only opens readonly for some reason
    pint->fpga_fd = open(buff, O_RDONLY);
#endif
    if (pint->fpga_fd < 0) {
	PORTAL_PRINTF("Failed to open %s fd=%d errno=%d\n", buff, pint->fpga_fd, errno);
	rc = -errno;
	goto errlab;
    }
    pint->map_base = (volatile unsigned int*)mmap(NULL, 1<<addrbits, PROT_READ|PROT_WRITE, MAP_SHARED, pint->fpga_fd, 0);
    if (pint->map_base == MAP_FAILED) {
        PORTAL_PRINTF("Failed to mmap PortalHWRegs from fd=%d errno=%d\n", pint->fpga_fd, errno);
        rc = -errno;
	goto errlab;
    }  
#endif

errlab:
    if (rc != 0) {
      PORTAL_PRINTF("%s: failed to open Portal fpga%d\n", __FUNCTION__, pint->fpga_number);
#ifndef __KERNEL__
      exit(1);
#endif
    }
}

int setClockFrequency(int clkNum, long requestedFrequency, long *actualFrequency)
{
    int status = 0;
    init_directory();
#ifdef ZYNQ
    PortalClockRequest request;
    request.clknum = clkNum;
    request.requested_rate = requestedFrequency;
    status = ioctl(globalDirectory.fpga_fd, PORTAL_SET_FCLK_RATE, (long)&request);
    if (status == 0 && actualFrequency)
	*actualFrequency = request.actual_rate;
    if (status < 0)
	status = errno;
#endif
    return status;
}

static void init_directory(void)
{
  unsigned int i;
  static int once = 0;

  if (once)
      return;
  once = 1;
#ifdef __KERNEL__
  tboard = get_pcie_portal_descriptor();
#endif
  init_portal_internal(&globalDirectory, -1, NULL);
#ifdef ZYNQ /* There is no way to set userclock freq from host on PCIE */
  // start by setting the clock frequency (this only has any effect on the zynq platform)
  PortalClockRequest request;
  long reqF = 100000000; // 100 Mhz
  request.clknum = 0;
  request.requested_rate = reqF;
  int status = ioctl(globalDirectory.fpga_fd, PORTAL_SET_FCLK_RATE, (long)&request);
  if (status < 0)
    PORTAL_PRINTF("init_directory: error setting fclk0, errno=%d\n", errno);
  PORTAL_PRINTF("init_directory: set fclk0 (%ld,%ld)\n", reqF, request.actual_rate);
#endif

  // finally scan
  if(1) PORTAL_PRINTF("init_directory: scan(fpga%d)\n", globalDirectory.fpga_number);
  if(1){
    time_t timestamp  = READL(&globalDirectory, PORTAL_DIRECTORY_TIMESTAMP);
    uint32_t numportals = READL(&globalDirectory, PORTAL_DIRECTORY_NUMPORTALS);
    PORTAL_PRINTF("version=%d\n",  READL(&globalDirectory, PORTAL_DIRECTORY_VERSION));
#ifndef __KERNEL__
    PORTAL_PRINTF("timestamp=%s",  ctime(&timestamp));
#endif
    PORTAL_PRINTF("numportals=%d\n", numportals);
    PORTAL_PRINTF("addrbits=%d\n", READL(&globalDirectory, PORTAL_DIRECTORY_ADDRBITS));
    for(i = 0; (i < numportals) && (i < 32); i++)
      PORTAL_PRINTF("portal[%d]: ifcid=%d, ifctype=%08x\n", i, READL(&globalDirectory, PORTAL_DIRECTORY_PORTAL_ID(i)), READL(&globalDirectory, PORTAL_DIRECTORY_PORTAL_TYPE(i)));
  }
}

unsigned int directory_get_fpga(unsigned int id)
{
  int numportals, i;
    init_directory();
  numportals = READL(&globalDirectory, PORTAL_DIRECTORY_NUMPORTALS);
  for(i = 0; i < numportals; i++){
    if(READL(&globalDirectory, PORTAL_DIRECTORY_PORTAL_ID(i)) == id)
      return i+1;
  }
  PORTAL_PRINTF("directory_fpga(id=%d) id not found\n", id);
  //exit(1);
  return 0;
}

unsigned int directory_get_addrbits(unsigned int id)
{
    init_directory();
  return READL(&globalDirectory, PORTAL_DIRECTORY_ADDRBITS);
}

void portalTrace_start()
{
    init_directory();
#if !defined(ZYNQ) && !defined(__KERNEL__)
  tTraceInfo traceInfo;
  traceInfo.trace = 1;
  int res = ioctl(globalDirectory.fpga_fd,BNOC_TRACE,&traceInfo);
  if (res)
    PORTAL_PRINTF("Failed to start tracing. errno=%d\n", errno);
#endif
}
void portalTrace_stop()
{
    init_directory();
#if !defined(ZYNQ) && !defined(__KERNEL__)
  tTraceInfo traceInfo;
  traceInfo.trace = 0;
  int res = ioctl(globalDirectory.fpga_fd,BNOC_TRACE,&traceInfo);
  if (res)
    PORTAL_PRINTF("Failed to stop tracing. errno=%d\n", errno);
#endif
}

uint64_t directory_cycle_count()
{
  unsigned int high_bits, low_bits;
    init_directory();
  high_bits = READL(&globalDirectory, PORTAL_DIRECTORY_COUNTER_MSB);
  low_bits  = READL(&globalDirectory, PORTAL_DIRECTORY_COUNTER_LSB);
  return (((uint64_t)high_bits)<<32) | ((uint64_t)low_bits);
}

void portal_enable_interrupts(PortalInternal *p)
{
   WRITEL(p, &(p->map_base[IND_REG_INTERRUPT_MASK]), 1);
}
