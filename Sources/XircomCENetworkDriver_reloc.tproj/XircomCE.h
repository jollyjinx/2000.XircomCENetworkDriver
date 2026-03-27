#import <driverkit/IOEthernet.h>
#import <driverkit/IONetwork.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/IODirectDevice.h>

@interface XircomCE:IOEthernet
{
   	unsigned short		iobase;					/* port base 					     */
    int					irq;					/* interrupt					     */
    IORange				port;					/* port							     */
    IONetwork			*network;
	enet_addr_t			ethernetaddress;		/* local copy of ethernet address    */
	
	unsigned short		vendor;
	unsigned char		media;
	unsigned char		revision;
	unsigned char		product;
}

+ (BOOL)probe:(IOPCMCIADeviceDescription *)devDesc;

- initFromDeviceDescription:(IOPCMCIADeviceDescription *)devDesc;
- free;


@end
