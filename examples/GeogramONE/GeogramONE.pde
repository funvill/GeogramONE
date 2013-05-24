/*****************************************************************************
The Geogram ONE is an open source tracking device/development board based off 
the Arduino platform.  The hardware design and software files are released 
under CC-SA v3 license.
*****************************************************************************/

#include <AltSoftSerial.h>
#include <PinChangeInt.h>
#include "GeogramONE.h"
#include <EEPROM.h>
#include <I2C.h>
#include "eepromAnything.h"


GeogramONE ggo;
AltSoftSerial GSM;
SIM900 sim900(&GSM);
geoSmsData smsData;
PA6C gps(&Serial); 
goCoord lastValid;
geoFence fence;


volatile uint8_t call;
volatile uint8_t move;
volatile uint8_t battery = 0;
volatile uint8_t charge = 0x02; // force a read of the charger cable
volatile uint8_t d4Switch = 0x00;
volatile uint8_t d10Switch = 0x00;

uint8_t cmd0 = 0;
uint8_t cmd1 = 0;
uint8_t cmd3 = 0;
uint8_t udp = 0x00; 

uint8_t fence1 = 0;
uint8_t fence2 = 0;
uint8_t fence3 = 0;

uint8_t breachSpeed = 0;
uint8_t breachReps = 0;

uint32_t smsInterval = 0;
uint32_t gprsInterval = 0;
uint32_t sleepTimeOn = 0;
uint32_t sleepTimeOff = 0;
uint8_t sleepTimeConfig = 0;

uint8_t speedHyst = 0;
uint16_t speedLimit = 0;

char gprsReply[11];

void setup()
{
	ggo.init();
	gps.init(115200);
	sim900.init(9600);
	MAX17043init(7, 500);
	BMA250init(3, 500);
	attachInterrupt(0, ringIndicator, FALLING);
	attachInterrupt(1, movement, FALLING);
	PCintPort::attachInterrupt(PG_INT, &charger, CHANGE);
	PCintPort::attachInterrupt(FUELGAUGEPIN, &lowBattery, FALLING);
	sim900.goesWhere(smsData.smsNumber);
	call = sim900.checkForMessages();
	if(call == 0xFF)
		call = 0;
	battery = MAX17043getAlertFlag();
	ggo.getFenceActive(1, &fence1); 
	ggo.getFenceActive(2, &fence2); 
	ggo.getFenceActive(3, &fence3);
	ggo.configureSpeed(&cmd3, &speedHyst, &speedLimit);
	ggo.configureBreachParameters(&breachSpeed, &breachReps);
	ggo.configureInterval(&smsInterval, &sleepTimeOn, &sleepTimeOff, &sleepTimeConfig, &gprsInterval);
	if(sleepTimeConfig & 0x02)
		BMA250enableInterrupts();
	uint8_t swInt = EEPROM.read(IOSTATE0);
	if(swInt == 0x05)
		PCintPort::attachInterrupt(4, &d4Interrupt, RISING);
	if(swInt == 0x06)
		PCintPort::attachInterrupt(4, &d4Interrupt, FALLING);
	swInt = EEPROM.read(IOSTATE1);
	if(swInt == 0x05)
		PCintPort::attachInterrupt(10, &d10Interrupt, RISING);
	if(swInt == 0x06)
		PCintPort::attachInterrupt(10, &d10Interrupt, FALLING);
}

void loop()
{
	gps.getCoordinates(&lastValid);
	if(call)
	{
		sim900.gsmSleepMode(0);
		if(!sim900.getGeo(&smsData))
		{
			if(!smsData.smsPending)
				call = 0; // no more messages
			if(smsData.smsDataValid)
			{
				if(!smsData.smsCmdNum)
					cmd0 = 0x01;
				else if(smsData.smsCmdNum == 1)
					cmd1 = 0x01;
				else if(smsData.smsCmdNum == 2)
					command2();
				else if(smsData.smsCmdNum == 3)
					cmd3 = 0x01;
				else if(smsData.smsCmdNum == 4)
					command4();
				else if(smsData.smsCmdNum == 5)
					command5();
				else if(smsData.smsCmdNum == 6)
					command6();
				else if(smsData.smsCmdNum == 7)
					command7();
				else if(smsData.smsCmdNum == 8)
					command8();
			}
		}
		sim900.gsmSleepMode(2);	
	}
	if(cmd0)
		command0();
	if(cmd1)
		command1();
	if(cmd3)
		command3();
	if(udp)
		udpOrange();
	if(battery)
	{
		sim900.gsmSleepMode(0);
		if(!sim900.sendMessage(2,smsData.smsNumber,NULL,BATTERYMSG))
		{
			battery = 0;
			MAX17043clearAlertFlag();
		}
		sim900.gsmSleepMode(2);
	}
	if(charge & 0x02)
		chargerStatus();
	if(fence1)
	{
		static uint8_t breach1Conf = 0;
		static char previousSeconds1 = lastValid.time[5];
		if((fence1 == 1) && (lastValid.speed >= breachSpeed))
		{
			ggo.configureFence(1,&fence); 
			if(!gps.geoFenceDistance(&lastValid, &fence))
			{
				if(lastValid.time[5] != previousSeconds1)
					breach1Conf++;
				if(breach1Conf > breachReps)
				{
					fence1 = 2;
					breach1Conf = 0;
				}
				previousSeconds1 = lastValid.time[5];
			}
			else
				breach1Conf = 0;
		}
		else
			breach1Conf = 0;
		if(fence1 == 2)
		{
			sim900.gsmSleepMode(0);
			if(!sim900.sendMessage(2,smsData.smsNumber,NULL,FENCE1MSG))
				fence1 = 0;
			sim900.gsmSleepMode(2);
		}
	} 
	if(fence2)
	{
		static uint8_t breach2Conf = 0;
		static char previousSeconds2 = lastValid.time[5];
		if((fence2 == 1) && (lastValid.speed >= breachSpeed))
		{  
			ggo.configureFence(2,&fence);
			if(!gps.geoFenceDistance(&lastValid, &fence))
			{
				if(lastValid.time[5] != previousSeconds2)
					breach2Conf++;
				if(breach2Conf > breachReps)
				{
					fence2 = 2;
					breach2Conf = 0;
				}
				previousSeconds2 = lastValid.time[5];
			}
			else
				breach2Conf = 0;
		}
		else
			breach2Conf = 0;
		if(fence2 == 2)
		{  
			sim900.gsmSleepMode(0);
			if(!sim900.sendMessage(2,smsData.smsNumber,NULL,FENCE2MSG))
				fence2 = 0;
			sim900.gsmSleepMode(2);
		}
	}	
	if(fence3)
	{
		static uint8_t breach3Conf = 0;
		static char previousSeconds3 = lastValid.time[5];
		if((fence3 == 1) && (lastValid.speed >= breachSpeed))
		{  
			ggo.configureFence(3,&fence);
			if(!gps.geoFenceDistance(&lastValid, &fence))
			{
				if(lastValid.time[5] != previousSeconds3)
					breach3Conf++;
				if(breach3Conf > breachReps)
				{
					fence3 = 2;
					breach3Conf = 0;
				}
				previousSeconds3 = lastValid.time[5];
			}
			else
				breach3Conf = 0;
		}
		else
			breach3Conf = 0;
		if(fence3 == 2)
		{  
			sim900.gsmSleepMode(0);
			if(!sim900.sendMessage(2,smsData.smsNumber,NULL,FENCE3MSG))
				fence3 = 0;
			sim900.gsmSleepMode(2);
		}
	}
	if(smsInterval)
		smsTimerMenu();
	if(gprsInterval)
		gprsTimerMenu();
	if(sleepTimeOn && sleepTimeOff)
		sleepTimer();
	if(d4Switch)
	{
		sim900.gsmSleepMode(0);
		if(!sim900.sendMessage(2,smsData.smsNumber,NULL,D4MSG))
			d4Switch = 0x00;
		sim900.gsmSleepMode(2);
	}
	if(d10Switch)
	{
		sim900.gsmSleepMode(0);
		if(!sim900.sendMessage(2,smsData.smsNumber,NULL,D10MSG))
			d10Switch = 0x00;
		sim900.gsmSleepMode(2);
	}
} 

