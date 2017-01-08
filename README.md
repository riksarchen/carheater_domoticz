# carheater_domoticz
Carheater lua script for domoticz with google calendar. 

Many thanks to BakSeeDaa for his work with google cal script for domoticz.

INSTALLATION:
First of all you need to install BakSeeDaa's google calender script, follow this guide: 
https://www.domoticz.com/forum/viewtopic.php?f=38&t=8333

IMPORTANT! 
Before you push the 'Check Switch' for the first time to run the setupscript do the following: 
Replace script_device_gcal.lua with the one downloaded from this project. 
Filepath: /home/pi/domoticz/scripts/lua/

After you have done this you need to create a uservariable as integer with name = Timer<idx> of your GCal Device switch created in the earlier steps. 
I.e. if your GCal Device switch has idx 265 you need to create the uservariable with name Timer265

After this copy carheater.lua to: /home/pi/domoticz/scripts/lua/

Edit .lua file:
sudo nano /home/pi/domoticz/scripts/lua/carheater.lua

Change all parameters in the top of the .lua file to your needs. 
Save file with Ctrl + O and exit nano with Ctrl + X.

Now add events to your google cal and the carheater should turn on so the car is warm at the specified time. 

Remember that the script takes into account the outside temperature and corrects the starttime so when you add an event in your cal, set the event at the time you want to leave home. Carheater will turn off at the end of the event so if you know you will leave somewhere between 07:30 and 08:00 then create a event that starts at 07:30 and ends at 08:00. 

