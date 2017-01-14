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

After you have done this you need to create these uservariables.

Replace (idx) with the idx of your GCal Device switch created in the earlier steps.
Timer(idx)Run 
Timer(idx)NoUsageTime 

Your uservar should look like this if your idx = 200:
Timer200Run
Timer200NoUsageTime

Both should be created as INTEGER.

Now there are two methods to install the carheater script. 

#####################################################################################
The first one is to copy the script into domoticz script directory
To do this: 
copy carheater.lua to /home/pi/domoticz/scripts/lua/
make sure that the script is only trigged once a minute.

Edit settings: 
sudo nano /home/pi/domoticz/scripts/lua/carheater.lua

Change all parameters in the top of the .lua file to your needs. 
Save file with Ctrl + O and exit nano with Ctrl + X.
#####################################################################################


#####################################################################################
The other way which I recommend is to paste the code into domoticz script editor: 
Goto domoticz script editor. 
Click New
select lua in the dropdown menu.
select time in the dropdown menu below. 
Remove all code
paste all code from carheater.lua

Now you need to copy bakseeda.lua to /usr/local/lib/lua/5.2/
sudo mkdir -p /usr/local/lib/lua/5.2/
sudo cp /home/pi/domoticz/scripts/lua/bakseeda.lua /usr/local/lib/lua/5.2/bakseeda.lua

Edit settings:
open domoticz script editor
Change all parameters in the top of the script to your needs. 

#####################################################################################

If you don't have an outside temperature sensor you can use Weather underground. You need to separate temperature from WU's multisensor. To do this use ExtractTempWU.lua. 

Remember to edit the settings in that file. 

#####################################################################################

Now add events to your google cal and the carheater should turn on so the car is warm at the specified time. 

Remember that the script takes into account the outside temperature and corrects the starttime so when you add an event in your cal, set the event at the time you want to leave home. Carheater will turn off at the end of the event so if you know you will leave somewhere between 07:30 and 08:00 then create a event that starts at 07:30 and ends at 08:00. 

