-- sensors
local sensortemp            = 'NAME OF THE SENSOR'                          -- name of your outside temperature sensor

-- relayswitch
local motorSwitch           = 'NAME OF THE SWITCH'                          -- name of the relayswitch

-- usage sensor
local usageSwitch           = 'NAME OF THE USAGE SENSOR'                    -- name of the usage sensor

-- variables
local TimerRunLastTime      = 'Timer265'                                    -- change 265 to your idx, you need to create a uservariable with this name as integer
local GCaltimeStart         = 'GCal265NextStart'                            -- change 265 to your idx, you need to create a uservariable with this name as integer
local GCaltimeStop          = 'GCal265NextStop'                             -- change 265 to your idx, you need to create a uservariable with this name as integer

-- usersettings
local debug                 = false                                         -- debugging 
local maxTemp               = 8                                             -- disable carheater if temperature is above
local MaxTime               = 180                                           -- maximum number of minutes the outsideTemp logic will return
local baseTime              = 60                                            -- adjust this time if the car is to warm or to cold
local autoshutoffnopower    = true                                          -- enable/disable automatic shutoff if usage = 0 Watt
local timeNoPower           = 10                                            -- minutes with no usage before the relay is shutoff
local autoshutoffpower      = true                                          -- enable/disable automatic shutoff after x minutes (both timer and manual start)
local timePower             = 300                                           -- shutoff relay after x minutes with usage > 0 Watt. Cannot be less than MaxTime 

-- ##########################################################
-- #             DON'T CHANGE ANYTHING BELOW                #
-- ##########################################################

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
    if s > maxTemp then 
        runningtime = 0 
        return runningtime
    end
    runningtime = (s / 10 * -60) + baseTime
    if runningtime > MaxTime then runningtime = MaxTime end
    if runningtime < 0 then runningtime = 0 end
    return runningtime * 60
end

commandArray = {}

-- values
local currTime                      = os.time()
local outsideTemp                   = tonumber(otherdevices[sensortemp])
local carheater_runtime             = RunTime(outsideTemp)
local timeGCalStart                 = uservariables[GCaltimeStart]
local timeGCalStop                  = uservariables[GCaltimeStop]
local timeleftStart                 = currTime - timeGCalStart + carheater_runtime
local timeleftStop                  = currTime - timeGCalStop
local timeLastRun                   = timedifference(uservariables_lastupdate[TimerRunLastTime], currTime)
local timeLastOn                    = timedifference(otherdevices_lastupdate[motorSwitch], currTime)
local timeLastUsage                 = timedifference(otherdevices_lastupdate[usageSwitch], currTime)
local motorSwitchStatus             = otherdevices[motorSwitch]
local usageSwitchStatus             = otherdevices[usageSwitch]

-- carheater start
if (timeGCalStart > 0 and motorSwitchStatus == 'Off' and timeleftStart >= 0 and timeleftStart < timeLastRun) then
    if (carheater_runtime > 0) then
        local switchOnfor = timeleftStop / -60
        print("Startar " .. motorSwitch .. "i " .. switchOnfor .. " minuter, utetemperatur är " .. outsideTemp .. " celcius.")
        commandArray[motorSwitch] = 'On FOR ' .. switchOnfor
        commandArray['Variable:' .. TimerRunLastTime] = '1'
    else
        print("Startar inte " .. motorSwitch .. ", utetemperatur är " .. outsideTemp .. " celcius.")
    end
end

-- autoshutoffnopower
if (autoshutoffnopower) then
    if (outsideTemp < maxTemp and motorSwitchStatus == 'On' and timeLastOn >= (timeNoPower * 60) and usageSwitchStatus == '0.0' and timeLastUsage >= (timeNoPower * 60)) then
        print("Slår av " .. motorSwitch .. ", ingen Strömförbrukning senaste " ..  timeLastUsage / 60 .. " min.")
        commandArray['SendNotification']='Motorväramre avslagen!#Motorvärmaren har varit påslagen utan strömförbrukning i ' .. timeNoPower .. ' minuter. Stänger av!#0'
        commandArray[motorSwitch] = 'Off'
    end
end

-- autoshutoffpower
if (autoshutoffpower) then
    if (outsideTemp < maxTemp and motorSwitchStatus == 'On' and timeLastOn >= (timePower * 60) and usageSwitchStatus > "0.0") then
        print("Slår av " .. motorSwitch .. ", Max tillåten körtid är " ..  timePower .. " min.")
        commandArray['SendNotification']='Motorvärmare avslagen!#Motorvärmaren har gått längre än tillåten gångtid. ' .. motorSwitch .. ' är nu avstängd!#0'
        commandArray[motorSwitch] = 'Off'
    end
end

-- debugging
if (debug) then
    print(motorSwitch .. " relay: " .. otherdevices[motorSwitch])
    print("Last timer run: " .. os.date("%c", currTime - timeLastRun))
    print("Leavingtime from google cal: " .. os.date("%c", timeGCalStart))
    print("Endtime from google cal: " .. os.date("%c", timeGCalStop))
    print("carheater starting: " .. os.date("%c", currTime - timeleftStart))
    print("carheater stop at: " .. os.date("%c", currTime - timeleftStop))
    print("Automatic shutoff if usage = 0: " .. tostring(autoshutoffnopower))
    print("Automatic shutoff if usage > 0: " .. tostring(autoshutoffpower))
    print("Automatic shutoff if usage = 0 after: " .. tostring(timeNoPower) .. " minutes.")
    print("Automatic shutoff if usage > 0 after: " .. timePower .. " minutes.")
    print("Current time is: " .. os.date("%X", currTime))
    print("Outside temperature: " .. outsideTemp .. " celcius.")
end
return commandArray
