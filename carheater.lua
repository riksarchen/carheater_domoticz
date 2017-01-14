local b = require("bakseeda")

-- USERINPUTS REQUIRED
local nSensortemp                   = '<outside temp>'                          -- name of your outside temperature sensor
local nMotorswitch                  = '<your motor relay switch>'                         -- name of the relayswitch
local nUsageswitch                  = '<your usage switch>'                     -- name of the usage sensor
local device_idx                    = '<idx of your cal>'                                         -- INPUT YOUR IDX of the GCal Device switch
local smsPhonenumber                = '<your smsnumber>'                               -- SMS-number for notifications, clickatell required - for setup see below parameters

-- USERSETTINGS
local udebug                        = false                                         -- debugging 
local umaxTempAllowed               = 8                                             -- disable carheater if temperature is above
local umaxTimeLogic                 = 180                                           -- maximum number of minutes the sTemp logic will return
local ubaseTimeLogic                = 60                                            -- adjust this time if the car is to warm or to cold
local uautoPowerOff_noUsage         = true                                          -- enable/disable automatic shutoff if usage = 0 Watt
local umaxTimeNoUsage               = 10                                            -- minutes with no usage before the relay is shutoff
local uautoPowerOff_wUsage          = true                                          -- enable/disable automatic shutoff after x minutes (both timer and manual start)
local umaxTimewUsage                = 300                                           -- shutoff relay after x minutes with usage > 0 Watt. Cannot be less than umaxTimeLogic 
local uautoPowerOff_wUsageSMS       = true                                         -- enable sms notifications. Input your clickatell details in uservariables: ClickatellSender, ClickatellAPIId, ClickatellAPIPassw, ClickatellAPIUser
local uautoPowerOff_noUsageSMS      = false
local ucarheaterSwitchOnSMS         = true
local uautoPowerOff_wUsageNot       = true                                          -- enable notifcations. You need to have at least one notifcation service activated under settings.
local uautoPowerOff_noUsageNot      = true
local ucarheaterSwitchOnNot         = false

-- ##########################################################
-- #            END OF USERSETTINGS                         #
-- ##########################################################


commandArray = {}

-- functions
function timedifference (s, t)
  year = string.sub(s, 1, 4)
  month = string.sub(s, 6, 7)
  day = string.sub(s, 9, 10)
  hour = string.sub(s, 12, 13)
  minutes = string.sub(s, 15, 16)
  seconds = string.sub(s, 18, 19)
  t1 = t
  t2 = os.time{year=year, month=month, day=day, hour=hour, min=minutes, sec=seconds}
  difference2 = os.difftime (t1, t2)
  return difference2
end

function RunTime (s)
    if s > umaxTempAllowed then 
        runningtime = 0 
        return runningtime
    end
    runningtime = (s / 10 * -60) + ubaseTimeLogic
    if runningtime > umaxTimeLogic then runningtime = umaxTimeLogic end
    if runningtime < 0 then runningtime = 0 end
    return runningtime * 60
end

function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

-- variables
local vTimezerousage                = 'Timer'..device_idx..'NoUsageTime'            -- Time when zero usage was sensed
local vTimerLastRun                 = 'Timer'..device_idx..'Run'                    -- Time when timer turned on carheater last time
local vGCaltimeStart                = 'GCal'..device_idx..'NextStart'               -- Next event from google calender (leavetime)
local vGCaltimeStop                 = 'GCal'..device_idx..'NextStop'                -- Next event ending time (ending time for carheater)

-- values
local tNow                          = os.time()
local sTemp                         = tonumber(otherdevices[nSensortemp])
local carheater_runtime             = RunTime(sTemp)
local tGCalStart                    = b.getVar(vGCaltimeStart)
local tGCalStop                     = b.getVar(vGCaltimeStop)
local tLastRun                      = tNow - b.getVar(vTimerLastRun)
local tlStart                       = tNow - tGCalStart + carheater_runtime
local tlStop                        = tNow - tGCalStop

-- uautoPowerOff_noUsage
if (uautoPowerOff_noUsage) then 
    
    local tlNoUsageSwitch   = timedifference(otherdevices_lastupdate[nMotorswitch], tNow) - (umaxTimeNoUsage * 60)
    local tlNoUsageSensor   = tNow - b.getVar(vTimezerousage) - (umaxTimeNoUsage * 60)

    -- UPDATE USERVARIABLE WITH LAST TIME USAGE > 0
    if (tonumber(otherdevices_svalues[nUsageswitch]) == 0) then
        if (b.getVar(vTimezerousage) == 0) then b.setVar(vTimezerousage, tNow, 0) end
    else
        if (b.getVar(vTimezerousage) > 0) then b.setVar(vTimezerousage, 0, 0) end
    end

    -- CHECK IF TIME WITH ZERO USAGE IS LONGER THAN ALLOWED
    if (b.getVar(vTimezerousage) > 0 and tlNoUsageSwitch >= 0 and tlNoUsageSensor >= 0 and otherdevices[nMotorswitch] == 'On') then
        
        msg = nMotorswitch..' har varit påslagen utan strömförbrukning i ' .. umaxTimeNoUsage .. ' minuter. Stänger av!'
        
        print(msg)
        if (uautoPowerOff_noUsageSMS) then b.sendSMS(msg, smsPhonenumber) end
        if (uautoPowerOff_noUsageNot) then commandArray['SendNotification']='Motorvärmare avslagen!#'..msg..'#0' end
        
        commandArray[nMotorswitch] = 'Off'
    end
    
    -- DEBUGGING
    if (udebug) then
        print("LAST_TIME_USAGE: "..tonumber(otherdevices_svalues[nUsageswitch]).." = 0 == usagesensor")
        print("LAST_TIME_USAGE: "..tlNoUsageSwitch.." >= 0 == tlNoUsageSwitch")
        print("LAST_TIME_USAGE: "..tlNoUsageSensor.." >= 0 == tlNoUsageSensor")
        print("LAST_TIME_USAGE: ".."last usage: "..os.date("%c", b.getVar(vTimezerousage)))
        print("LAST_TIME_USAGE: ".."time since usage: "..tNow - b.getVar(vTimezerousage))
    end
end

-- uautoPowerOff_wUsage
if (uautoPowerOff_wUsage) then
    local tlUsageSwitch = timedifference(otherdevices_lastupdate[nMotorswitch], tNow) - (umaxTimewUsage * 60)
    
    if (otherdevices[nMotorswitch] == 'On' and tlUsageSwitch >= 0 and tonumber(otherdevices_svalues[nUsageswitch]) > 0) then
        msg = nMotorswitch..' har gått i '..round((timedifference(otherdevices_lastupdate[nMotorswitch], tNow) / 60), 0)..' minuter vilket är längre än tillåten gångtid. Stänger av!'
        
        print(msg)
        
        if (uautoPowerOff_wUsageSMS) then b.sendSMS(msg, smsPhonenumber) end
        if (uautoPowerOff_wUsageNot) then commandArray['SendNotification']='Motorvärmare avstängd!#'..msg..'#0' end
        
        commandArray[nMotorswitch] = 'Off'
    end
end

-- carheater start
if (udebug) then
    print("CARHEATER_START: "..tGCalStart.." > 0 == tGCalStart")
    print("CARHEATER_START: "..tlStart.." >= 0 == tlStart")
    print("CARHEATER_START: "..tlStart.." < "..tLastRun.. " == tlStart < tLastRun")
    print("CARHEATER_START: ".."nMotorswitch == 'Off': "..otherdevices[nMotorswitch])
    print("CARHEATER_START: "..carheater_runtime.. " > 0 == carheater_runtime > 0: ")
end
     
if (tGCalStart > 0 and tlStart >= 0 and tlStop < 0 and tlStart < tLastRun) then
    if (otherdevices[nMotorswitch] == 'Off') then
        if (carheater_runtime > 0) then

            -- calculate runtime
            local switchOnfor = round(tlStop / -60, 0)
            if (switchOnfor > umaxTimewUsage) then switchOnfor = umaxTimewUsage end
                
            msg = nMotorswitch..' startades kl. '..os.date("%X", tNow)..', utetemperatur är '..sTemp..' celcius. Den kommer stängas av kl. '..os.date("%X", (switchOnfor * 60) + tNow)
            
            print(msg)
            
            if (ucarheaterSwitchOnSMS) then b.sendSMS(msg, smsPhonenumber) end
            if (ucarheaterSwitchOnNot) then commandArray['SendNotification']='Motorvärmare påslagen!#'..msg..'#0' end
            b.setVar(vTimerLastRun, tNow, 0)
            commandArray[nMotorswitch] = 'On FOR ' .. switchOnfor
        else
            print("Startar inte " .. nMotorswitch .. ", utetemperatur är " .. sTemp .. " celcius.")
        end
    end
end

-- debugging
if (udebug) then
    print(nMotorswitch .. " relay: " .. otherdevices[nMotorswitch])
    print("Last timer run: " .. os.date("%c", b.getVar(vTimerLastRun)))
    print("Leavingtime from google cal: " .. os.date("%c", tGCalStart))
    print("Endtime from google cal: " .. os.date("%c", tGCalStop))
    print("carheater starting: " .. os.date("%c", tNow - tlStart))
    print("carheater stop at: " .. os.date("%c", tNow - tlStop))
    print("Automatic shutoff if usage = 0: " .. tostring(uautoPowerOff_noUsage))
    print("Automatic shutoff if usage > 0: " .. tostring(uautoPowerOff_wUsage))
    print("Automatic shutoff if usage = 0 after: " .. tostring(umaxTimeNoUsage) .. " minutes.")
    print("Automatic shutoff if usage > 0 after: " .. umaxTimewUsage .. " minutes.")
    print("Current time is: " .. os.date("%X", tNow))
    print("Outside temperature: " .. sTemp .. " celcius.")
end
return commandArray
