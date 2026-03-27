#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOPCMCIADeviceDescription.h>
#import <driverkit/i386/IOPCMCIATuple.h>
#import "XircomCE.h"
#import <driverkit/i386/ioPorts.h>

#import "if_xereg.h"
/*
 * One of these structures per allocated device
 */


typedef u_short	u_int16_t;
typedef u_char 	u_int8_t;
typedef u_int	u_int32_t;
/*
 * MII command structure
 */
struct xe_mii_frame {
  u_int8_t  mii_stdelim;
  u_int8_t  mii_opcode;
  u_int8_t  mii_phyaddr;
  u_int8_t  mii_regaddr;
  u_int8_t  mii_turnaround;
  u_int16_t mii_data;
};


/*
 * For accessing card registers
 */
#define XE_INB(r)         inb(iobase+(r))
#define XE_OUTB(r, b)     outb(iobase+(r), (b))

#define XE_INW(r)         inw(iobase+(r))
#define XE_OUTW(r, w)     outw(iobase+(r), (w))

#define XE_INL(r)         inl(iobase+(r))
#define XE_OUTL(r, w)     outl(iobase+(r), (w))


#define XE_SELECT_PAGE(p) XE_OUTB(XE_PR, (p))
/*
 * MII functions
 */
static void      xe_mii_sync		();
static int       xe_mii_init    	();
static void      xe_mii_send		( u_int32_t bits, int cnt);
static int       xe_mii_readreg		( struct xe_mii_frame *frame);
static int       xe_mii_writereg	( struct xe_mii_frame *frame);
static u_int16_t xe_phy_readreg		( u_int16_t reg);
static void      xe_phy_writereg	( u_int16_t reg, u_int16_t data);

@implementation XircomCE


+ (BOOL)probe:(IOPCMCIADeviceDescription *)myDeviceDescription
{
	unsigned short iobase;
		
    IOLog("XircomCEdriver: +probe: called.\n");
	
    if(	[myDeviceDescription numPortRanges] != 1)
	{
		IOLog("XircomCEdriver: numberOfPortRanges != 1 - aborting.\n");
		return NO;
	}
	else
	{
		IORange	*portranges  = [myDeviceDescription portRangeList];
		iobase= portranges[0].start;

		IOLog("XircomCEdriver: Portaddress:%x\n",iobase);
	}
    if(	[myDeviceDescription numInterrupts] != 1)
	{
		IOLog("XircomCEdriver: numInterrupts != 1 - aborting.\n");
		return NO;
	}


/* hard reset card */
	XE_SELECT_PAGE(0x04);
	XE_OUTB(XE_GPR1,0x00);		// power off
	IOSleep(400);				// sleep 400 msec
	XE_OUTB(XE_GPR1,0x01);		// power on
	IOSleep(400);				// sleep 400 msec

	XE_SELECT_PAGE(0x04);
	IOLog("XircomCEdriver: selected page  : 0x%0x ( should be 0x04 )\n", XE_INB(XE_PR));
	IOLog("XircomCEdriver: bonding version: 0x%0x\n", XE_INB(XE_BOV));
	
	if( 0x45 != XE_INB(XE_BOV))
	{
		IOLog("XircomCEdriver: wrong bonding version - aborting.\n");
		return NO;
	}
	return nil != [[self alloc] initFromDeviceDescription:myDeviceDescription];
}




/*
 * Public Instance Methods
 */

- initFromDeviceDescription:(IOPCMCIADeviceDescription *)myDeviceDescription
{
	IOLog("XircomCEdriver: -initFromDeviceDescription: called\n");
	{
		IORange	*portranges  = [myDeviceDescription portRangeList];
		iobase= portranges[0].start;

		IOLog("XircomCEdriver: Portaddress:%x\n",iobase);
	}
	if(1)
	{
		if( nil == [super initFromDeviceDescription:myDeviceDescription] ) 
		{
			IOLog("XircomCEdriver: Couldn't init superClass.\n");
			return nil;
		}
		IOLog("XircomCEdriver: [super initFromDeviceDescription:] done.");
		IOSleep(10);
	}
	{
		int i;
		IOPCMCIATuple **tupleList = [myDeviceDescription tupleList];
	
		IOLog("XircomCEdriver: number of PCMCIA-Tuples:%d\n",[myDeviceDescription numTuples]);
		
	    for (i=0; i<[myDeviceDescription numTuples]; i++)
		{
			IOPCMCIATuple *aTuple = tupleList[i];
			
			//IOLog("XircomCEdriver: Found Tuple[%d] code %x length %d\n",i,[aTuple code],[aTuple length]);
			switch( [aTuple code] )
			{
				case 0x20:	{
								u_char *t = [aTuple data];
								if( 7 <= [aTuple length] )
								{
									vendor = t[3]<<8 | t[2];
									revision	=	t[4];
									media		=	t[5];
									product		=	t[6];
									IOLog("XircomCEdriver: Vendor   :%x\n",vendor);
									IOLog("XircomCEdriver: Revision :%x\n",revision);
									IOLog("XircomCEdriver: Media    :%x\n",media);
									IOLog("XircomCEdriver: Product  :%x\n",product);
								}
							};break;
				case 0x22:	{
								u_char *t = [aTuple data];
								if( 10 == [aTuple length] && 0x04==t[2] && 0x06==t[3] )
								{
									IOLog("XircomCEdriver: Ethernet address %x:%x:%x:%x:%x:%x\n",t[4],t[5],t[6],t[7],t[8],t[9]);
									bcopy(t+4,&ethernetaddress,6);

								}
							};break;
				/*
				default:	{
								int j;
								for( j=0; j<[aTuple length]; j++ )
								{
									u_char *t = [aTuple data];
									
									if( t[j]>=0x20 && t[j]<127 )
									{
										IOLog("%c",t[j]);
									}
									else
									{
										IOLog("[%x]",t[j]);
									}
								}
								IOLog("\n");
								IOSleep(10);
							}	/**/
			}
			
	    }
		
	}
	
	IOLog("XircomCEdriver: -init done\n");
	
    network = [super attachToNetworkWithAddress:ethernetaddress];
	return self;
    return nil;		
}

- free
{   
    return [super free];
}

- (void)transmit:(netbuf_t)pkt;
{
  	unsigned short free, ok,rest;
	unsigned short packetlength = nb_size(pkt);
	unsigned short *packetaddress = nb_map(pkt);

    XE_OUTB(XE_CR, 0x00);
	
	XE_SELECT_PAGE(0);											// check transmit buffer space TRS
	XE_OUTW(XE_TRS, packetlength+2);
	
	free = XE_INW(XE_TSO);
  	ok = free & 0x8000;
	free &= 0x7fff;
  	if (free <= packetlength + 2)
	{
		IOLog("XircomCEdriver: Card busy to output\n");
    	nb_free(pkt);
		return;
	}
	
	XE_OUTW(XE_EDP, packetlength);								/* Send packet length to card */

	rest = packetlength & 0x01;
	packetlength = packetlength >>1;
	while(packetlength--)
	{
		XE_OUTW(XE_EDP, *packetaddress++);
	}
	if( rest )
		XE_OUTB(XE_EDP, *(char *)packetaddress);
	
	nb_free(pkt);
    XE_OUTB(XE_CR, XE_CR_TX_PACKET|XE_CR_ENABLE_INTR);
}

- (BOOL)resetAndEnable:(BOOL)enable;
{
	iobase=0x300;
	IOLog("XircomCEdriver: resetAndEnable called\n");
	[self disableAllInterrupts];
	
	

/* soft reset */
	
	XE_SELECT_PAGE(0x00);
	XE_OUTB(XE_CR,XE_CR_SOFT_RESET);	// soft reset
	IOSleep(60);						// wait
	XE_OUTB(XE_CR,0);
	IOSleep(10);

/* mohawk stuff */
	XE_SELECT_PAGE(0x04);
	XE_OUTB(XE_GPR0,0x0e);				// power up mohawk
	IOSleep(10);



	if( xe_mii_init())
	{
		int bmcr,anar;
		int	i,autoneg=0;
		
		IOLog("XircomCEdriver: mii_inited\n");
	
		bmcr = xe_phy_readreg(PHY_BMCR);
		bmcr &= ~(PHY_BMCR_AUTONEGENBL);
		xe_phy_writereg(PHY_BMCR, bmcr);
		anar = xe_phy_readreg(PHY_ANAR);
		anar &= ~(PHY_ANAR_100BT4|PHY_ANAR_100BTXFULL|PHY_ANAR_10BTFULL);
		anar |= PHY_ANAR_100BTXHALF|PHY_ANAR_10BTHALF;
		xe_phy_writereg(PHY_ANAR, anar);
		bmcr |= PHY_BMCR_AUTONEGENBL|PHY_BMCR_AUTONEGRSTR;
		xe_phy_writereg(PHY_BMCR, bmcr);

		// autonegotiation started 
		
		for(i=0;i<10;i++)
		{
			int bmsr,lpar;
			
			IOLog("XircomCEdriver: Waiting for Link.\n");
			
      		bmsr = xe_phy_readreg(PHY_BMSR);
      		lpar = xe_phy_readreg(PHY_LPAR);
			if (bmsr & (PHY_BMSR_AUTONEGCOMP|PHY_BMSR_LINKSTAT))
			{
				/*
					* XXX - Shouldn't have to do this, but (on my hub at least) the
					* XXX - transmitter won't work after a successful autoneg.  So we see 
					* XXX - what the negotiation result was and force that mode.  I'm
					* XXX - sure there is an easy fix for this.
					*/
				if (lpar & PHY_LPAR_100BTXHALF)
				{
					IOLog("XircomCEdriver: Autonegotiation complete (100Mbit)\n");
					xe_phy_writereg(PHY_BMCR, PHY_BMCR_SPEEDSEL);
					XE_SELECT_PAGE(2);
					XE_OUTB(XE_MSR, XE_INB(XE_MSR) | 0x08);
				}
				else 
				{
					IOLog("XircomCEdriver: Autonegotiation complete (10Mbit)\n");
					/*
					* XXX - Bit of a hack going on in here.
					* XXX - This is derived from Ken Hughes patch to the Linux driver
					* XXX - to make it work with 10Mbit _autonegotiated_ links on CE3B
					* XXX - cards.  What's a CE3B and how's it differ from a plain CE3?
					* XXX - these are the things we need to find out.
					*/
					xe_phy_writereg(PHY_BMCR, 0x0000);
					XE_SELECT_PAGE(2);
					/* BEGIN HACK */
					XE_OUTB(XE_MSR, XE_INB(XE_MSR) | 0x08);
					XE_SELECT_PAGE(0x42);
					XE_OUTB(XE_SWC1, 0x80);
					/* END HACK */
					/*XE_OUTB(XE_MSR, XE_INB(XE_MSR) & ~0x08);*/	/* Disable PHY? */
				}
				break;
			}
			IOSleep(30);
		}
		if( i==10 ) 
		{
			IOLog("XircomCEdriver: didn't get a link - will use 10BaseT.\n");
					xe_phy_writereg(PHY_BMCR, 0x0000);
					XE_SELECT_PAGE(2);
					/* BEGIN HACK */
					XE_OUTB(XE_MSR, XE_INB(XE_MSR) | 0x08);
					XE_SELECT_PAGE(0x42);
					XE_OUTB(XE_SWC1, 0x80);
					/* END HACK */
					/*XE_OUTB(XE_MSR, XE_INB(XE_MSR) & ~0x08);*/	/* Disable PHY? */
		}
	}

	XE_SELECT_PAGE(0x42);
//	XE_OUTB(XE_SWC0, XE_SWC0_LOOPBACK_ENABLE);
	XE_OUTB(XE_SWC1,0x00);
  
/* Set ethernetaddress */
	XE_SELECT_PAGE(0x50);
	XE_OUTB(0x08,*(((char *)&ethernetaddress)+5));
	XE_OUTB(0x09,*(((char *)&ethernetaddress)+4));
	XE_OUTB(0x0a,*(((char *)&ethernetaddress)+3));
	XE_OUTB(0x0b,*(((char *)&ethernetaddress)+2));
	XE_OUTB(0x0c,*(((char *)&ethernetaddress)+1));
	XE_OUTB(0x0d,*(((char *)&ethernetaddress)+0));

  /*
   * Set the 'local memory dividing line' -- splits the 32K card memory into
   * 8K for transmit buffers and 24K for receive.  This is done automatically
   * on newer revision cards.
   */
	XE_SELECT_PAGE(2);
	XE_OUTW(XE_RBS, 0x2000);
	XE_SELECT_PAGE(0);
	XE_OUTW(XE_DO, 0x2000);

  /*
   * Set MAC interrupt masks and clear status regs.  The bit names are direct
   * from the Linux code; I have no idea what most of them do.
   */
	XE_SELECT_PAGE(0x40);		/* Bit 7..0 */
	XE_OUTB(XE_RX0Msk, 0xff);	/* ROK, RAB, rsv, RO,  CRC, AE,  PTL, MP  */
	XE_OUTB(XE_TX0Msk, 0xff);	/* TOK, TAB, SQE, LL,  TU,  JAB, EXC, CRS */
	XE_OUTB(XE_TX0Msk+1, 0xb0);	/* rsv, rsv, PTD, EXT, rsv, rsv, rsv, rsv */
	XE_OUTB(XE_RST0, 0x00);	/* ROK, RAB, REN, RO,  CRC, AE,  PTL, MP  */
	XE_OUTB(XE_TXST0, 0x00);	/* TOK, TAB, SQE, LL,  TU,  JAB, EXC, CRS */
	XE_OUTB(XE_TXST1, 0x00);	/* TEN, rsv, PTD, EXT, retry_counter:4    */

	/* put MAC online */
	XE_SELECT_PAGE(0x40);
    XE_OUTB(XE_CMD0, XE_CMD0_RX_ENABLE|XE_CMD0_ONLINE);
	
	
	//IOSleep(400);

	


	XE_SELECT_PAGE(2);
	XE_OUTB(XE_LED, 0x3b);
	XE_OUTB(XE_LED3, 0x04);	// Led 3 light 10 or 100 tx detected


	if( enable && [self enableAllInterrupts] != IO_R_SUCCESS)
	{
        IOLog("XircomCEdriver: resetAndEnable: interrupts not allowed ..\n");
        [self setRunning:NO];
        return NO;
    }
    [self setRunning:enable];
    return YES;
}

- (void)timeoutOccurred;
{
	IOLog("XircomCEdriver: timeoutOccurred called\n");
	IOSleep(10);
}
- (void)interruptOccurred;
{
	u_int16_t rxs, txs;
	u_int8_t isr, esr, rsr;

	XE_OUTB(XE_CR, 0);		/* Disable interrupts */

	//IOLog("XircomCEdriver: interrupt occured.\n");
	
  	if( (isr = XE_INB(XE_ISR)) && isr != 0xff)			// did we generate the interrupt
	{

	    XE_SELECT_PAGE(0x40);
	    rxs = XE_INB(XE_RST0);
	    XE_OUTB(XE_RST0, ~rxs & 0xff);
	    txs = XE_INB(XE_TXST0);
	    txs |= XE_INB(XE_TXST1) << 8;
	    XE_OUTB(XE_TXST0, 0);
	    XE_OUTB(XE_TXST1, 0);
   		XE_SELECT_PAGE(0);
		
		/*
	    * Handle transmit interrupts
		*/
		if( isr & XE_ISR_TX_PACKET )
		{
			[network incrementInputErrors];

			//IOLog("XircomCEdriver: transmit interrupt received\n");
		}

		if (txs & 0x0002)
		{
			//IOLog("XircomCEdriver: massive transmit failure - restarting the transmitter.");
			[network incrementCollisions];
			XE_OUTB(XE_CR, XE_CR_RESTART_TX);
		}
		if (txs & 0x0040)
		{
			[network incrementCollisions];
			//IOLog("XircomCEdriver: transmit aborted - probably collisions.\n");
		}

	    /*
	     * Handle receive interrupts 
	     */
    	esr = XE_INB(XE_ESR);				/* Read the other status registers */
    	while(esr & XE_ESR_FULL_PACKET_RX) 
		{
			//IOLog("XircomCEdriver: Got packet\n");
			
			if( (rsr = XE_INB(XE_RSR)) & XE_RSR_RX_OK)
			{
				netbuf_t ethernetpacket;
				u_int16_t ethernetpacketlength;
				ethernetpacketlength = XE_INW(XE_RBC)&0x1fff;
				
				//IOLog("XircomCEdriver: Got good packet length: %d\n",ethernetpacketlength);

				if( ethernetpacketlength<60 || ethernetpacketlength>1518)
				{
					//IOLog("XircomCEdriver: Got bogus packet with length %d-bytes.\n",ethernetpacketlength);
					[network incrementInputErrors];
					continue;
				}
				
				if( NULL == (ethernetpacket	= nb_alloc(ethernetpacketlength)) )
				{
					IOLog("XircomCEdriver: Couldn't allocate network buffer.\n");
					continue;
				}
				else
				{
					short *ethernetpacketmemory = nb_map(ethernetpacket);
					if( ethernetpacketlength & 0x01 )
						ethernetpacketlength++;
					
					ethernetpacketlength=ethernetpacketlength>>1;
					while(ethernetpacketlength--)
						*ethernetpacketmemory++ = XE_INW(XE_EDP);
					[network handleInputPacket:ethernetpacket extra:0];
					XE_OUTW(XE_DO, 0x8000);		/* skip_rx_packet command */
				}
			}
			else if( rsr & XE_RSR_LONG_PACKET )
			{
				IOLog("XircomCEdriver: got too long packet\n");
			}
			else if( rsr & XE_RSR_CRC_ERROR)
			{
				IOLog("XircomCEdriver: got packet with crc error\n");
			}
			else if( rsr & XE_RSR_ALIGN_ERROR)
			{
				IOLog("XircomCEdriver: got misaligned packet\n");
			}
			else
			{
				IOLog("XircomCEdriver: got weird packet\n");
			}
			esr = XE_INB(XE_ESR);
		}
		if (rxs & 0x10)
		{						
			IOLog("XircomCEdriver: receiver underrun occured.\n");
			XE_OUTB(XE_CR, XE_CR_CLEAR_OVERRUN);
		}
	}
	else
	{
	//	IOLog("XircomCEdriver: Got interrupt which wasn't for supposed for us.\n");
	}
	XE_OUTB(XE_CR, XE_CR_ENABLE_INTR);		/* Re-enable interrupts */
}


- (IOReturn)enableAllInterrupts
{
	XE_SELECT_PAGE(1);
	XE_OUTB(XE_IMR0, XE_IMR0_RX_PACKET|XE_IMR0_FORCE_INTR); // 0xff);		/* Unmask everything */
	//XE_OUTB(XE_IMR1, 0x01);		/* Unmask TX underrun detection */

	IOSleep(2);
	XE_SELECT_PAGE(0);
	XE_OUTB(XE_CR,XE_CR_ENABLE_INTR);	/* Enable interrupts */

    return [super enableAllInterrupts];
}

- (void)disableAllInterrupts
{
	XE_SELECT_PAGE(0);
	XE_OUTB(XE_CR, 0);			/* Disable interrupts */

	XE_SELECT_PAGE(1);
	XE_OUTB(XE_IMR0, 0);			/* Forbid all interrupts */
//	XE_OUTB(XE_IMR1, 0);
	
    [super disableAllInterrupts];
}

@end
#define iobase  0x300
#define DELAY(m)	IOSleep(m/1000)

/**************************************************************
 *                                                            *
 *                  M I I  F U N C T I O N S                  *
 *                                                            *
 **************************************************************/

/*
 * Alternative MII/PHY handling code adapted from the xl driver.  It doesn't
 * seem to work any better than the xirc2_ps stuff, but it's cleaner code.
 * XXX - this stuff shouldn't be here.  It should all be abstracted off to
 * XXX - some kind of common MII-handling code, shared by all drivers.  But
 * XXX - that's a whole other mission.
 */
#define XE_MII_SET(x)	XE_OUTB(XE_GPR2, (XE_INB(XE_GPR2) | 0x04) | (x))
#define XE_MII_CLR(x)	XE_OUTB(XE_GPR2, (XE_INB(XE_GPR2) | 0x04) & ~(x))


/*
 * Sync the PHYs by setting data bit and strobing the clock 32 times.
 */
static void
xe_mii_sync() {
  register int i;

  XE_SELECT_PAGE(2);
  XE_MII_SET(XE_MII_DIR|XE_MII_WRD);

  for (i = 0; i < 32; i++) {
    XE_MII_SET(XE_MII_CLK);
    DELAY(1);
    XE_MII_CLR(XE_MII_CLK);
    DELAY(1);
  }
}


/*
 * Look for a MII-compliant PHY.  If we find one, reset it.
 */
static int xe_mii_init() {
  u_int16_t status;

  status = xe_phy_readreg( PHY_BMSR);
  if ((status & 0xff00) != 0x7800) {
    return 0;
  }
  else {

    /* Reset the PHY */
    xe_phy_writereg(PHY_BMCR, PHY_BMCR_RESET);
    DELAY(500);
    while(xe_phy_readreg( PHY_BMCR) & PHY_BMCR_RESET);
    return 1;
  }
}


/*
 * Clock a series of bits through the MII.
 */
static void
xe_mii_send(u_int32_t bits, int cnt) {
  int i;

  XE_SELECT_PAGE(2);
  XE_MII_CLR(XE_MII_CLK);
  
  for (i = (0x1 << (cnt - 1)); i; i >>= 1) {
    if (bits & i) {
      XE_MII_SET(XE_MII_WRD);
    } else {
      XE_MII_CLR(XE_MII_WRD);
    }
    DELAY(1);
    XE_MII_CLR(XE_MII_CLK);
    DELAY(1);
    XE_MII_SET(XE_MII_CLK);
  }
}


/*
 * Read an PHY register through the MII.
 */
static int
xe_mii_readreg(struct xe_mii_frame *frame) {
  int i, ack;


  /*
   * Set up frame for RX.
   */
  frame->mii_stdelim = XE_MII_STARTDELIM;
  frame->mii_opcode = XE_MII_READOP;
  frame->mii_turnaround = 0;
  frame->mii_data = 0;
	
  XE_SELECT_PAGE(2);
  XE_OUTB(XE_GPR2, 0);

  /*
   * Turn on data xmit.
   */
  XE_MII_SET(XE_MII_DIR);

  xe_mii_sync();

  /*	
   * Send command/address info.
   */
  xe_mii_send( frame->mii_stdelim, 2);
  xe_mii_send( frame->mii_opcode, 2);
  xe_mii_send( frame->mii_phyaddr, 5);
  xe_mii_send( frame->mii_regaddr, 5);

  /* Idle bit */
  XE_MII_CLR((XE_MII_CLK|XE_MII_WRD));
  DELAY(1);
  XE_MII_SET(XE_MII_CLK);
  DELAY(1);

  /* Turn off xmit. */
  XE_MII_CLR(XE_MII_DIR);

  /* Check for ack */
  XE_MII_CLR(XE_MII_CLK);
  DELAY(1);
  XE_MII_SET(XE_MII_CLK);
  DELAY(1);
  ack = XE_INB(XE_GPR2) & XE_MII_RDD;

  /*
   * Now try reading data bits. If the ack failed, we still
   * need to clock through 16 cycles to keep the PHY(s) in sync.
   */
  if (ack) {
    for(i = 0; i < 16; i++) {
      XE_MII_CLR(XE_MII_CLK);
      DELAY(1);
      XE_MII_SET(XE_MII_CLK);
      DELAY(1);
    }
    goto fail;
  }

  for (i = 0x8000; i; i >>= 1) {
    XE_MII_CLR(XE_MII_CLK);
    DELAY(1);
    if (!ack) {
      if (XE_INB(XE_GPR2) & XE_MII_RDD)
	frame->mii_data |= i;
      DELAY(1);
    }
    XE_MII_SET(XE_MII_CLK);
    DELAY(1);
  }

fail:

  XE_MII_CLR(XE_MII_CLK);
  DELAY(1);
  XE_MII_SET(XE_MII_CLK);
  DELAY(1);


  if (ack)
    return(1);
  return(0);
}


/*
 * Write to a PHY register through the MII.
 */
static int
xe_mii_writereg(struct xe_mii_frame *frame) {

  /*
   * Set up frame for TX.
   */
  frame->mii_stdelim = XE_MII_STARTDELIM;
  frame->mii_opcode = XE_MII_WRITEOP;
  frame->mii_turnaround = XE_MII_TURNAROUND;
	
  XE_SELECT_PAGE(2);

  /*		
   * Turn on data output.
   */
  XE_MII_SET(XE_MII_DIR);

  xe_mii_sync();

  xe_mii_send( frame->mii_stdelim, 2);
  xe_mii_send( frame->mii_opcode, 2);
  xe_mii_send( frame->mii_phyaddr, 5);
  xe_mii_send( frame->mii_regaddr, 5);
  xe_mii_send( frame->mii_turnaround, 2);
  xe_mii_send( frame->mii_data, 16);

  /* Idle bit. */
  XE_MII_SET(XE_MII_CLK);
  DELAY(1);
  XE_MII_CLR(XE_MII_CLK);
  DELAY(1);

  /*
   * Turn off xmit.
   */
  XE_MII_CLR(XE_MII_DIR);


  return(0);
}


/*
 * Read a register from the PHY.
 */
static u_int16_t
xe_phy_readreg( u_int16_t reg) {
  struct xe_mii_frame frame;

  bzero((char *)&frame, sizeof(frame));

  frame.mii_phyaddr = 0;
  frame.mii_regaddr = reg;
  xe_mii_readreg( &frame);

  return(frame.mii_data);
}


/*
 * Write to a PHY register.
 */
static void
xe_phy_writereg( u_int16_t reg, u_int16_t data) {
  struct xe_mii_frame frame;

  bzero((char *)&frame, sizeof(frame));

  frame.mii_phyaddr = 0;
  frame.mii_regaddr = reg;
  frame.mii_data = data;
  xe_mii_writereg( &frame);

  return;
}


